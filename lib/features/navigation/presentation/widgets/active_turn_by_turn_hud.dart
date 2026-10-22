import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../domain/entities/maneuver.dart';
import '../../../../domain/entities/maneuver_type.dart';
import '../state/gpx_route_tracker.dart';

/// HUD superior e inferior superpuesto sobre el mapa cartográfico durante la navegación activa.
class ActiveTurnByTurnHud extends StatelessWidget {
  final GpxRouteTracker tracker;
  final Maneuver? currentManeuver;
  final double? distanceToManeuverMeters;
  final bool isVoiceMuted;
  final VoidCallback? onToggleVoiceMute;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;

  const ActiveTurnByTurnHud({
    super.key,
    required this.tracker,
    this.currentManeuver,
    this.distanceToManeuverMeters,
    this.isVoiceMuted = false,
    this.onToggleVoiceMute,
    required this.onPause,
    required this.onResume,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        // 1. Tarjeta Superior de Maniobra (Turn-by-turn banner)
        if (currentManeuver != null)
          Positioned(
            top: 10.0,
            left: 12.0,
            right: 12.0,
            child: SafeArea(
              bottom: false,
              child: _buildManeuverCard(isDark),
            ),
          ),

        // 2. Panel Inferior de Telemetría y Controles Flotantes
        Positioned(
          bottom: 12.0,
          left: 12.0,
          right: 12.0,
          child: SafeArea(
            top: false,
            child: _buildBottomTelemetry(context, isDark),
          ),
        ),
      ],
    );
  }

  Widget _buildManeuverCard(bool isDark) {
    final distanceText = _formatDistance(distanceToManeuverMeters);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
      decoration: BoxDecoration(
        color: (isDark ? AppColors.surfaceNavy : AppColors.whiteSurface)
            .withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(14.0),
        border: Border.all(
          color: isDark ? const Color(0xFF264660) : AppColors.silver,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 12.0,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Icono compacto de maniobra
          Container(
            width: 44.0,
            height: 44.0,
            decoration: BoxDecoration(
              color: isDark ? AppColors.nightBlue : const Color(0xFFE2EDF7),
              borderRadius: BorderRadius.circular(10.0),
            ),
            child: Icon(
              _getManeuverIcon(currentManeuver!.type),
              size: 26.0,
              color: isDark ? AppColors.cyanLuminous : AppColors.surfaceNavy,
            ),
          ),
          const SizedBox(width: 12.0),

          // Distancia al giro e instrucción
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (distanceText.isNotEmpty)
                  Text(
                    'En $distanceText',
                    style: TextStyle(
                      fontSize: 15.0,
                      fontWeight: FontWeight.w900,
                      color: isDark
                          ? AppColors.cyanLuminous
                          : AppColors.surfaceNavy,
                    ),
                  ),
                Text(
                  currentManeuver!.instruction,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppColors.coldWhite
                        : AppColors.primaryTextLight,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (onToggleVoiceMute != null) ...[
            const SizedBox(width: 6.0),
            IconButton(
              tooltip: isVoiceMuted ? 'Activar voz' : 'Silenciar voz',
              icon: Icon(
                isVoiceMuted
                    ? Icons.volume_off_rounded
                    : Icons.volume_up_rounded,
                color: isVoiceMuted
                    ? AppColors.silver
                    : (isDark
                        ? AppColors.cyanLuminous
                        : AppColors.surfaceNavy),
                size: 24.0,
              ),
              onPressed: onToggleVoiceMute,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomTelemetry(BuildContext context, bool isDark) {
    final pos = tracker.currentPosition;
    final hasFix = pos != null;
    final accuracy = pos?.accuracyMeters;
    final accuracyStr =
        accuracy != null ? '±${accuracy.toStringAsFixed(0)}m' : null;
    final timeStr = pos != null
        ? '${pos.timestamp.hour.toString().padLeft(2, '0')}:${pos.timestamp.minute.toString().padLeft(2, '0')}:${pos.timestamp.second.toString().padLeft(2, '0')}'
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
      decoration: BoxDecoration(
        color: (isDark ? AppColors.nightBlue : AppColors.whiteSurface)
            .withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: isDark ? const Color(0xFF264660) : AppColors.silver,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 14.0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Barra de estado de fuente GPS / DEMO
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7.0, vertical: 2.0),
                decoration: BoxDecoration(
                  color: hasFix
                      ? AppColors.success.withValues(alpha: 0.15)
                      : AppColors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6.0),
                  border: Border.all(
                    color: hasFix
                        ? AppColors.success.withValues(alpha: 0.4)
                        : AppColors.warning.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hasFix ? Icons.gps_fixed_rounded : Icons.gps_not_fixed_rounded,
                      size: 11.0,
                      color: hasFix ? AppColors.success : AppColors.warning,
                    ),
                    const SizedBox(width: 4.0),
                    Text(
                      hasFix ? 'GPS REAL' : 'BUSCANDO GPS',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: hasFix ? AppColors.success : AppColors.warning,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (accuracyStr != null) ...[
                const SizedBox(width: 6.0),
                Text(
                  accuracyStr,
                  style: TextStyle(
                    fontSize: 10.0,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.secondaryTextDark : AppColors.secondaryTextLight,
                  ),
                ),
              ],
              if (timeStr != null) ...[
                const SizedBox(width: 6.0),
                Text(
                  '• $timeStr',
                  style: TextStyle(
                    fontSize: 10.0,
                    color: isDark ? AppColors.secondaryTextDark : AppColors.secondaryTextLight,
                  ),
                ),
              ],
              const Spacer(),
              if (tracker.isPaused)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4.0),
                  ),
                  child: const Text(
                    'PAUSADO',
                    style: TextStyle(
                      fontSize: 9.0,
                      fontWeight: FontWeight.w800,
                      color: AppColors.warning,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8.0),

          // Velocidad y Odometría
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                tracker.currentSpeedKmh != null
                    ? tracker.currentSpeedKmh!.toStringAsFixed(0)
                    : '--',
                style: const TextStyle(
                  fontSize: 34.0,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 4.0),
              Text(
                'km/h',
                style: TextStyle(
                  fontSize: 13.0,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? AppColors.cyanLuminous
                      : AppColors.electricBlue,
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'RESTANTE',
                    style: AppTypography.badgeLabel.copyWith(fontSize: 8.5),
                  ),
                  Text(
                    '${(tracker.remainingDistanceMeters / 1000).toStringAsFixed(1)} km',
                    style: const TextStyle(
                      fontSize: 15.0,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14.0),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'PROGRESO',
                    style: AppTypography.badgeLabel.copyWith(fontSize: 8.5),
                  ),
                  Text(
                    '${tracker.progressPercentage.toStringAsFixed(0)} %',
                    style: const TextStyle(
                      fontSize: 15.0,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8.0),

          // Barra de progreso
          LinearProgressIndicator(
            value: (tracker.progressPercentage / 100.0).clamp(0.0, 1.0),
            minHeight: 4.0,
            borderRadius: BorderRadius.circular(2.0),
            color: isDark ? AppColors.cyanLuminous : AppColors.electricBlue,
            backgroundColor: isDark
                ? AppColors.cardNavy
                : AppColors.silver.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 10.0),

          // Botones Pausar / Finalizar
          Row(
            children: [
              if (tracker.isPaused)
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onResume,
                    icon: const Icon(Icons.play_arrow, size: 16.0),
                    label: const Text('Reanudar'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 9.0),
                    ),
                  ),
                )
              else
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onPause,
                    icon: const Icon(Icons.pause, size: 16.0),
                    label: const Text('Pausar'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 9.0),
                    ),
                  ),
                ),
              const SizedBox(width: 10.0),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => _confirmFinish(context),
                  icon: const Icon(Icons.stop, size: 16.0),
                  label: const Text('Finalizar'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 9.0),
                    backgroundColor: AppColors.error.withValues(alpha: 0.18),
                    foregroundColor: AppColors.error,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmFinish(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Finalizar navegación?'),
        content: const Text(
          'Se guardarán las métricas de la ruta en tu registro local de sesiones.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Continuar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
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

  String _formatDistance(double? meters) {
    if (meters == null || meters <= 0) return '';
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
    return '${meters.round()} m';
  }

  IconData _getManeuverIcon(ManeuverType type) {
    switch (type) {
      case ManeuverType.left:
      case ManeuverType.sharpLeft:
        return Icons.turn_left;
      case ManeuverType.right:
      case ManeuverType.sharpRight:
        return Icons.turn_right;
      case ManeuverType.slightLeft:
        return Icons.turn_slight_left;
      case ManeuverType.slightRight:
        return Icons.turn_slight_right;
      case ManeuverType.uTurn:
        return Icons.u_turn_left;
      case ManeuverType.roundabout:
        return Icons.roundabout_right;
      case ManeuverType.arrive:
        return Icons.flag;
      case ManeuverType.depart:
      case ManeuverType.straight:
      case ManeuverType.unknown:
        return Icons.straight;
    }
  }
}
