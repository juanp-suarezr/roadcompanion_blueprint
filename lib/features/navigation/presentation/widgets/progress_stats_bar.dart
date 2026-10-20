import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../domain/entities/route_progress.dart';

/// Barra de métricas y odometría de ruta para la pantalla de navegación.
class ProgressStatsBar extends StatelessWidget {
  final RouteProgress progress;
  final double totalDistanceMeters;

  const ProgressStatsBar({
    super.key,
    required this.progress,
    required this.totalDistanceMeters,
  });

  String _formatKm(double meters) {
    return '${(meters / 1000.0).toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final traveledStr = _formatKm(progress.distanceTraveledMeters);
    final remainingStr = _formatKm(progress.remainingDistanceMeters);
    final totalStr = _formatKm(totalDistanceMeters);
    final percentage = progress.progressPercentage.toStringAsFixed(0);

    return Card(
      elevation: 0,
      color: isDark ? AppColors.darkSurface : AppColors.whiteSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
        side: BorderSide(
          color: isDark ? const Color(0xFF263A48) : const Color(0xFFD7DFE8),
          width: 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Fila superior: Porcentaje y Distancia restante
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PROGRESO',
                      style: TextStyle(
                        fontSize: 11.0,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                        color: AppColors.secondaryTextLight,
                      ),
                    ),
                    const SizedBox(height: 2.0),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          percentage,
                          style: AppTypography.progressPercentage.copyWith(
                            color: isDark
                                ? AppColors.accentBlue
                                : AppColors.deepBlue,
                          ),
                        ),
                        const SizedBox(width: 4.0),
                        Text(
                          '%',
                          style: TextStyle(
                            fontSize: 18.0,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? AppColors.accentBlue
                                : AppColors.deepBlue,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'RESTANTE',
                      style: TextStyle(
                        fontSize: 11.0,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                        color: AppColors.secondaryTextLight,
                      ),
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      remainingStr,
                      style: TextStyle(
                        fontSize: 22.0,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12.0),

            // Barra de progreso lineal temática
            ClipRRect(
              borderRadius: BorderRadius.circular(6.0),
              child: LinearProgressIndicator(
                value: (progress.progressPercentage / 100.0).clamp(0.0, 1.0),
                minHeight: 8.0,
                backgroundColor: isDark
                    ? const Color(0xFF1B2C38)
                    : const Color(0xFFE2E9F0),
                valueColor: AlwaysStoppedAnimation<Color>(
                  isDark ? AppColors.accentBlue : AppColors.deepBlue,
                ),
              ),
            ),
            const SizedBox(height: 12.0),

            // Fila inferior: Recorrida vs Total
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStatItem(
                  label: 'RECORRIDA',
                  value: traveledStr,
                  isDark: isDark,
                  alignEnd: false,
                ),
                Container(
                  width: 1.0,
                  height: 20.0,
                  color: isDark
                      ? const Color(0xFF2E4659)
                      : const Color(0xFFE2E8F0),
                ),
                _buildStatItem(
                  label: 'DISTANCIA TOTAL',
                  value: totalStr,
                  isDark: isDark,
                  alignEnd: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required String label,
    required String value,
    required bool isDark,
    required bool alignEnd,
  }) {
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10.0,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: AppColors.secondaryTextLight,
          ),
        ),
        const SizedBox(height: 2.0),
        Text(
          value,
          style: TextStyle(
            fontSize: 14.0,
            fontWeight: FontWeight.w700,
            color: isDark ? AppColors.silver : AppColors.primaryTextLight,
          ),
        ),
      ],
    );
  }
}
