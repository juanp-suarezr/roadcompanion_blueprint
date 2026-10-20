import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/widgets/storm_badge.dart';
import '../../domain/entities/gpx_tracking_status.dart';
import '../state/gpx_route_tracker.dart';

/// Panel de telemetría y controles de seguimiento GPS en vivo sobre la ruta GPX.
class GpxLiveTrackingPanel extends StatelessWidget {
  final GpxRouteTracker tracker;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;

  const GpxLiveTrackingPanel({
    super.key,
    required this.tracker,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(18.0),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.whiteSurface,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: isDark
              ? AppColors.steelBlue.withValues(alpha: 0.35)
              : AppColors.silver,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Cabecera con estado de seguimiento y badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStatusBadge(tracker.status, tracker.offRouteDistanceMeters),
              if (tracker.currentPosition != null)
                Row(
                  children: [
                    Icon(
                      Icons.gps_fixed,
                      size: 13.0,
                      color: isDark
                          ? AppColors.accentBlue
                          : AppColors.steelBlue,
                    ),
                    const SizedBox(width: 4.0),
                    Text(
                      '±${tracker.currentPosition!.accuracyMeters.toStringAsFixed(0)} m',
                      style: TextStyle(
                        fontSize: 11.0,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppColors.secondaryTextDark
                            : AppColors.secondaryTextLight,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12.0),

          // 2. Velocidad instantánea sobredimensionada para visibilidad en moto
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                tracker.currentSpeedKmh != null
                    ? tracker.currentSpeedKmh!.toStringAsFixed(0)
                    : '--',
                style: AppTypography.maneuverDistance.copyWith(
                  color: isDark
                      ? AppColors.primaryTextDark
                      : AppColors.primaryTextLight,
                ),
              ),
              const SizedBox(width: 6.0),
              Text(
                'km/h',
                style: AppTypography.maneuverUnit.copyWith(
                  color: isDark ? AppColors.accentBlue : AppColors.steelBlue,
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'TIEMPO ACTIVO',
                    style: AppTypography.badgeLabel.copyWith(
                      fontSize: 9.0,
                      color: isDark
                          ? AppColors.secondaryTextDark
                          : AppColors.secondaryTextLight,
                    ),
                  ),
                  Text(
                    _formatDuration(tracker.sessionDuration),
                    style: TextStyle(
                      fontSize: 16.0,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                      color: isDark
                          ? AppColors.primaryTextDark
                          : AppColors.primaryTextLight,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14.0),

          // 3. Barra de avance y distancias
          LinearProgressIndicator(
            value: (tracker.progressPercentage / 100.0).clamp(0.0, 1.0),
            minHeight: 6.0,
            borderRadius: BorderRadius.circular(3.0),
            backgroundColor: isDark
                ? AppColors.darkSurfaceVariant
                : AppColors.silver.withValues(alpha: 0.5),
            color: tracker.status == GpxTrackingStatus.offRoute
                ? AppColors.warning
                : (isDark ? AppColors.accentBlue : AppColors.steelBlue),
          ),
          const SizedBox(height: 10.0),

          // Métricas de odometría estimada
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMetricColumn(
                context,
                label: 'RECORRIDO',
                value:
                    '${(tracker.distanceTraveledMeters / 1000).toStringAsFixed(1)} km',
              ),
              _buildMetricColumn(
                context,
                label: 'PROGRESO',
                value: '${tracker.progressPercentage.toStringAsFixed(0)} %',
                alignEnd: true,
              ),
              _buildMetricColumn(
                context,
                label: 'RESTANTE',
                value:
                    '${(tracker.remainingDistanceMeters / 1000).toStringAsFixed(1)} km',
                alignEnd: true,
              ),
            ],
          ),
          const SizedBox(height: 12.0),

          // 4. Mensaje informativo de estado
          if (tracker.statusMessage != null)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10.0,
                vertical: 6.0,
              ),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.stormNavy.withValues(alpha: 0.6)
                    : const Color(0xFFF0F4F8),
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 14.0,
                    color: isDark ? AppColors.accentBlue : AppColors.steelBlue,
                  ),
                  const SizedBox(width: 8.0),
                  Expanded(
                    child: Text(
                      tracker.statusMessage!,
                      style: TextStyle(
                        fontSize: 11.0,
                        color: isDark
                            ? AppColors.secondaryTextDark
                            : AppColors.secondaryTextLight,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14.0),

          // 5. Controles táctiles grandes
          _buildControls(context, isDark),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context, bool isDark) {
    if (!tracker.isTracking && !tracker.isPaused && !tracker.isSearching) {
      return FilledButton.icon(
        onPressed: onStart,
        icon: const Icon(Icons.navigation, size: 20.0),
        label: const Text(
          'INICIAR SEGUIMIENTO GPS',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5),
        ),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          backgroundColor: isDark ? AppColors.accentBlue : AppColors.steelBlue,
          foregroundColor: isDark ? AppColors.stormNavy : Colors.white,
        ),
      );
    }

    return Row(
      children: [
        if (tracker.isPaused)
          Expanded(
            child: FilledButton.icon(
              onPressed: onResume,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Reanudar'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14.0),
              ),
            ),
          )
        else
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onPause,
              icon: const Icon(Icons.pause),
              label: const Text('Pausar'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14.0),
              ),
            ),
          ),
        const SizedBox(width: 10.0),
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: () => _confirmFinish(context),
            icon: const Icon(Icons.stop),
            label: const Text('Finalizar'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14.0),
              backgroundColor: const Color(0xFFEF5350).withValues(alpha: 0.2),
              foregroundColor: const Color(0xFFC62828),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricColumn(
    BuildContext context, {
    required String label,
    required String value,
    bool alignEnd = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.badgeLabel.copyWith(
            fontSize: 9.0,
            color: isDark
                ? AppColors.secondaryTextDark
                : AppColors.secondaryTextLight,
          ),
        ),
        const SizedBox(height: 2.0),
        Text(
          value,
          style: TextStyle(
            fontSize: 13.0,
            fontWeight: FontWeight.w700,
            color: isDark
                ? AppColors.primaryTextDark
                : AppColors.primaryTextLight,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(GpxTrackingStatus status, double offRouteDistance) {
    switch (status) {
      case GpxTrackingStatus.idle:
        return const StormBadge(
          label: 'LISTO PARA SEGUIR',
          icon: Icons.play_circle_outline,
          variant: StormBadgeVariant.neutral,
        );
      case GpxTrackingStatus.searchingGps:
        return const StormBadge(
          label: 'BUSCANDO GPS...',
          icon: Icons.satellite_alt_outlined,
          variant: StormBadgeVariant.info,
        );
      case GpxTrackingStatus.lowAccuracy:
        return const StormBadge(
          label: 'PRECISIÓN BAJA',
          icon: Icons.gps_not_fixed,
          variant: StormBadgeVariant.warning,
        );
      case GpxTrackingStatus.tracking:
        return const StormBadge(
          label: 'SIGUIENDO RUTA',
          icon: Icons.navigation_outlined,
          variant: StormBadgeVariant.success,
        );
      case GpxTrackingStatus.offRoute:
        return StormBadge(
          label: 'DESVÍO (+${offRouteDistance.toStringAsFixed(0)} m)',
          icon: Icons.warning_amber_rounded,
          variant: StormBadgeVariant.warning,
        );
      case GpxTrackingStatus.gpsLost:
        return const StormBadge(
          label: 'SEÑAL PERDIDA',
          icon: Icons.signal_cellular_connected_no_internet_0_bar,
          variant: StormBadgeVariant.warning,
        );
      case GpxTrackingStatus.paused:
        return const StormBadge(
          label: 'PAUSADO',
          icon: Icons.pause,
          variant: StormBadgeVariant.neutral,
        );
      case GpxTrackingStatus.completed:
        return const StormBadge(
          label: 'COMPLETADA',
          icon: Icons.check_circle,
          variant: StormBadgeVariant.success,
        );
      case GpxTrackingStatus.stopped:
        return const StormBadge(
          label: 'DETENIDO',
          icon: Icons.stop_circle_outlined,
          variant: StormBadgeVariant.neutral,
        );
    }
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  void _confirmFinish(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Finalizar sesión de seguimiento?'),
        content: const Text(
          'Se guardarán las métricas acumuladas de la sesión de viaje en el registro local.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Continuar ruta'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              onStop();
            },
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );
  }
}
