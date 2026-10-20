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
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;

  const ActiveTurnByTurnHud({
    super.key,
    required this.tracker,
    this.currentManeuver,
    this.distanceToManeuverMeters,
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
            top: 14.0,
            left: 16.0,
            right: 16.0,
            child: _buildManeuverCard(isDark),
          ),

        // 2. Panel Inferior de Telemetría y Controles Flotantes
        Positioned(
          bottom: 16.0,
          left: 16.0,
          right: 16.0,
          child: _buildBottomTelemetry(context, isDark),
        ),
      ],
    );
  }

  Widget _buildManeuverCard(bool isDark) {
    final distanceText = _formatDistance(distanceToManeuverMeters);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: BoxDecoration(
        color: (isDark ? AppColors.surfaceNavy : AppColors.whiteSurface)
            .withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: isDark ? const Color(0xFF264660) : AppColors.silver,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 14.0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Icono grande de maniobra
          Container(
            width: 52.0,
            height: 52.0,
            decoration: BoxDecoration(
              color: isDark ? AppColors.nightBlue : const Color(0xFFE2EDF7),
              borderRadius: BorderRadius.circular(12.0),
            ),
            child: Icon(
              _getManeuverIcon(currentManeuver!.type),
              size: 32.0,
              color: isDark ? AppColors.cyanLuminous : AppColors.surfaceNavy,
            ),
          ),
          const SizedBox(width: 14.0),

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
                      fontSize: 16.0,
                      fontWeight: FontWeight.w900,
                      color: isDark
                          ? AppColors.cyanLuminous
                          : AppColors.surfaceNavy,
                    ),
                  ),
                Text(
                  currentManeuver!.instruction,
                  style: TextStyle(
                    fontSize: 13.5,
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
        ],
      ),
    );
  }

  Widget _buildBottomTelemetry(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: (isDark ? AppColors.nightBlue : AppColors.whiteSurface)
            .withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(18.0),
        border: Border.all(
          color: isDark ? const Color(0xFF264660) : AppColors.silver,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 16.0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                  fontSize: 38.0,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 4.0),
              Text(
                'km/h',
                style: TextStyle(
                  fontSize: 14.0,
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
                    style: AppTypography.badgeLabel.copyWith(fontSize: 9.0),
                  ),
                  Text(
                    '${(tracker.remainingDistanceMeters / 1000).toStringAsFixed(1)} km',
                    style: const TextStyle(
                      fontSize: 16.0,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16.0),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'PROGRESO',
                    style: AppTypography.badgeLabel.copyWith(fontSize: 9.0),
                  ),
                  Text(
                    '${tracker.progressPercentage.toStringAsFixed(0)} %',
                    style: const TextStyle(
                      fontSize: 16.0,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12.0),

          // Barra de progreso
          LinearProgressIndicator(
            value: (tracker.progressPercentage / 100.0).clamp(0.0, 1.0),
            minHeight: 5.0,
            borderRadius: BorderRadius.circular(3.0),
            color: isDark ? AppColors.cyanLuminous : AppColors.electricBlue,
            backgroundColor: isDark
                ? AppColors.cardNavy
                : AppColors.silver.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12.0),

          // Botones Pausar / Finalizar
          Row(
            children: [
              if (tracker.isPaused)
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onResume,
                    icon: const Icon(Icons.play_arrow, size: 18.0),
                    label: const Text('Reanudar'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12.0),
                    ),
                  ),
                )
              else
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onPause,
                    icon: const Icon(Icons.pause, size: 18.0),
                    label: const Text('Pausar'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12.0),
                    ),
                  ),
                ),
              const SizedBox(width: 10.0),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => _confirmFinish(context),
                  icon: const Icon(Icons.stop, size: 18.0),
                  label: const Text('Finalizar'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
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
      case ManeuverType.turnLeft:
      case ManeuverType.turnSharpLeft:
        return Icons.turn_left;
      case ManeuverType.turnRight:
      case ManeuverType.turnSharpRight:
        return Icons.turn_right;
      case ManeuverType.turnSlightLeft:
        return Icons.turn_slight_left;
      case ManeuverType.turnSlightRight:
        return Icons.turn_slight_right;
      case ManeuverType.uTurn:
        return Icons.u_turn_left;
      case ManeuverType.roundaboutEnter:
      case ManeuverType.roundaboutExit:
        return Icons.roundabout_right;
      case ManeuverType.forkLeft:
        return Icons.fork_left;
      case ManeuverType.forkRight:
        return Icons.fork_right;
      case ManeuverType.merge:
        return Icons.merge;
      case ManeuverType.arrive:
        return Icons.flag;
      case ManeuverType.depart:
      case ManeuverType.continueStraight:
      case ManeuverType.unknown:
        return Icons.straight;
    }
  }
}
