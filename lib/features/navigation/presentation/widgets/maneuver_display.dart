import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../domain/entities/maneuver.dart';
import '../../../../domain/entities/maneuver_type.dart';

/// Componente de visualización de maniobra de alta legibilidad para conducción en moto.
class ManeuverDisplay extends StatelessWidget {
  final Maneuver maneuver;
  final double distanceMeters;

  const ManeuverDisplay({
    super.key,
    required this.maneuver,
    required this.distanceMeters,
  });

  IconData _iconForManeuver(ManeuverType type) {
    switch (type) {
      case ManeuverType.depart:
        return Icons.navigation;
      case ManeuverType.left:
      case ManeuverType.slightLeft:
      case ManeuverType.sharpLeft:
        return Icons.turn_left;
      case ManeuverType.right:
      case ManeuverType.slightRight:
      case ManeuverType.sharpRight:
        return Icons.turn_right;
      case ManeuverType.uTurn:
        return Icons.u_turn_left;
      case ManeuverType.straight:
        return Icons.arrow_upward;
      case ManeuverType.roundabout:
        return Icons.roundabout_left;
      case ManeuverType.arrive:
        return Icons.flag_circle;
      case ManeuverType.unknown:
        return Icons.straight;
    }
  }

  String _formatDistance(double meters) {
    if (meters < 1000.0) {
      return '${meters.round()}';
    } else {
      return (meters / 1000.0).toStringAsFixed(1);
    }
  }

  String _formatUnit(double meters) {
    return meters < 1000.0 ? 'm' : 'km';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final distanceStr = _formatDistance(distanceMeters);
    final unitStr = _formatUnit(distanceMeters);
    final iconData = _iconForManeuver(maneuver.type);

    return Card(
      elevation: 0,
      color: isDark ? AppColors.darkSurface : AppColors.whiteSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
        side: BorderSide(
          color: isDark ? AppColors.deepBlue : const Color(0xFFD7DFE8),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Icono sobredimensionado de maniobra
            Container(
              width: 64.0,
              height: 64.0,
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.darkSurfaceVariant
                    : AppColors.deepBlue,
                borderRadius: BorderRadius.circular(16.0),
                border: Border.all(
                  color: isDark ? AppColors.accentBlue : AppColors.steelBlue,
                  width: 1.5,
                ),
              ),
              child: Icon(
                iconData,
                size: 38.0,
                color: isDark ? AppColors.accentBlue : Colors.white,
              ),
            ),
            const SizedBox(width: 16.0),

            // Distancia y textos
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Distancia en números gigantes para vista rápida
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        distanceStr,
                        style: AppTypography.maneuverDistance.copyWith(
                          color: isDark
                              ? AppColors.primaryTextDark
                              : AppColors.primaryTextLight,
                        ),
                      ),
                      const SizedBox(width: 4.0),
                      Text(
                        unitStr,
                        style: AppTypography.maneuverUnit.copyWith(
                          color: isDark
                              ? AppColors.accentBlue
                              : AppColors.steelBlue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2.0),

                  // Nombre de vía
                  Text(
                    maneuver.roadName ?? 'Siguiente calzada',
                    style: AppTypography.roadName.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontSize: 18.0,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2.0),

                  // Instrucción textual
                  Text(
                    maneuver.instructionText,
                    style: AppTypography.instructionText.copyWith(
                      color: isDark
                          ? AppColors.secondaryTextDark
                          : AppColors.secondaryTextLight,
                      fontSize: 13.0,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
