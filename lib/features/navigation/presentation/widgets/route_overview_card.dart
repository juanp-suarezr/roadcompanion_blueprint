import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../domain/entities/calculated_route.dart';
import '../../domain/entities/destination.dart';

/// Tarjeta flotante que presenta el resumen de una ruta vial calculada antes de iniciar la navegación.
class RouteOverviewCard extends StatelessWidget {
  final Destination destination;
  final CalculatedRoute route;
  final VoidCallback onStartNavigation;
  final VoidCallback onCancel;

  const RouteOverviewCard({
    super.key,
    required this.destination,
    required this.route,
    required this.onStartNavigation,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(18.0),
      decoration: BoxDecoration(
        color: isDark ? AppColors.nightBlue : AppColors.whiteSurface,
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
          // Fila de encabezado con nombre del destino y botón cerrar
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.location_on,
                  color: AppColors.error,
                  size: 20.0,
                ),
              ),
              const SizedBox(width: 12.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      destination.title,
                      style: TextStyle(
                        fontSize: 16.0,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? AppColors.coldWhite
                            : AppColors.primaryTextLight,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      route.summary,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark
                            ? AppColors.secondaryText
                            : AppColors.secondaryTextLight,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20.0),
                onPressed: onCancel,
                tooltip: 'Cancelar ruta',
              ),
            ],
          ),
          const SizedBox(height: 14.0),

          // Métricas de distancia y tiempo estimado
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 14.0,
              vertical: 10.0,
            ),
            decoration: BoxDecoration(
              color: isDark ? AppColors.cardNavy : AppColors.lightBackground,
              borderRadius: BorderRadius.circular(12.0),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMetric(
                  label: 'TIEMPO ESTIMADO',
                  value: route.formattedDuration,
                  color: isDark
                      ? AppColors.cyanLuminous
                      : AppColors.surfaceNavy,
                ),
                Container(
                  width: 1.0,
                  height: 30.0,
                  color: isDark ? const Color(0xFF264660) : AppColors.silver,
                ),
                _buildMetric(
                  label: 'DISTANCIA VIAL',
                  value: '${route.totalDistanceKm.toStringAsFixed(1)} km',
                  color: isDark
                      ? AppColors.coldWhite
                      : AppColors.primaryTextLight,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16.0),

          // Botón principal grande para iniciar navegación
          FilledButton.icon(
            onPressed: onStartNavigation,
            icon: const Icon(Icons.navigation, size: 20.0),
            label: const Text(
              'INICIAR NAVEGACIÓN',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8),
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              backgroundColor: isDark
                  ? AppColors.cyanLuminous
                  : AppColors.surfaceNavy,
              foregroundColor: isDark ? AppColors.nightBlue : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetric({
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Text(label, style: AppTypography.badgeLabel.copyWith(fontSize: 9.0)),
        const SizedBox(height: 2.0),
        Text(
          value,
          style: TextStyle(
            fontSize: 16.0,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}
