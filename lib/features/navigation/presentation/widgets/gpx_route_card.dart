import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/widgets/storm_badge.dart';
import '../../domain/entities/imported_gpx_route.dart';

/// Tarjeta descriptiva de una ruta GPX importada.
///
/// Presenta el nombre del recorrido, métricas geográficas calculadas, elevación
/// y opciones claras para retirar la ruta o importar un archivo distinto.
class GpxRouteCard extends StatelessWidget {
  final ImportedGpxRoute route;
  final VoidCallback onClearRoute;
  final VoidCallback onImportAnother;

  const GpxRouteCard({
    super.key,
    required this.route,
    required this.onClearRoute,
    required this.onImportAnother,
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
              ? AppColors.accentBlue.withValues(alpha: 0.35)
              : AppColors.steelBlue.withValues(alpha: 0.25),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Cabecera con badge y nombre
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const StormBadge(
                      label: 'GPX IMPORTADO',
                      icon: Icons.check_circle_outline,
                      variant: StormBadgeVariant.success,
                    ),
                    const SizedBox(height: 8.0),
                    Text(
                      route.name,
                      style: AppTypography.sectionTitle.copyWith(
                        fontSize: 20.0,
                        color: isDark
                            ? AppColors.primaryTextDark
                            : AppColors.primaryTextLight,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Retirar ruta y volver a demo',
                icon: const Icon(Icons.close),
                onPressed: onClearRoute,
              ),
            ],
          ),
          const SizedBox(height: 14.0),

          // 2. Métricas del trazado en tarjetas compactas
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  context,
                  label: 'DISTANCIA GEOGRÁFICA',
                  value: '${route.totalDistanceKm.toStringAsFixed(1)} km',
                  subtitle: 'Haversine intra-segmento',
                  icon: Icons.straighten,
                ),
              ),
              const SizedBox(width: 10.0),
              Expanded(
                child: _buildMetricTile(
                  context,
                  label: 'PUNTOS DE RUTA',
                  value: '${route.totalPoints}',
                  subtitle: '${route.segments.length} segmento(s)',
                  icon: Icons.scatter_plot,
                ),
              ),
            ],
          ),

          if (route.minElevation != null && route.maxElevation != null) ...[
            const SizedBox(height: 10.0),
            _buildMetricTile(
              context,
              label: 'RANGO DE ELEVACIÓN',
              value:
                  '${route.minElevation!.toStringAsFixed(0)} m  →  ${route.maxElevation!.toStringAsFixed(0)} m',
              subtitle: 'Altitud registrada en el archivo',
              icon: Icons.terrain,
            ),
          ],

          const SizedBox(height: 14.0),

          // 3. Nota honesta sobre ausencia de maniobras viales inventadas
          Container(
            padding: const EdgeInsets.all(10.0),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.stormNavy.withValues(alpha: 0.7)
                  : const Color(0xFFF0F4F8),
              borderRadius: BorderRadius.circular(8.0),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16.0,
                  color: isDark ? AppColors.accentBlue : AppColors.steelBlue,
                ),
                const SizedBox(width: 8.0),
                Expanded(
                  child: Text(
                    'Los archivos GPX describen la geometría pura del recorrido. No se inventan indicaciones de giro ni maniobras viales sin un motor de navegación.',
                    style: TextStyle(
                      fontSize: 11.0,
                      height: 1.35,
                      color: isDark
                          ? AppColors.secondaryTextDark
                          : AppColors.secondaryTextLight,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14.0),

          // 4. Botones de acción
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onClearRoute,
                  icon: const Icon(Icons.arrow_back, size: 18.0),
                  label: const Text('Volver a demo'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    foregroundColor: isDark
                        ? AppColors.primaryTextDark
                        : AppColors.deepBlue,
                  ),
                ),
              ),
              const SizedBox(width: 10.0),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onImportAnother,
                  icon: const Icon(Icons.file_upload_outlined, size: 18.0),
                  label: const Text('Cambiar GPX'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile(
    BuildContext context, {
    required String label,
    required String value,
    required String subtitle,
    required IconData icon,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(10.0),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceVariant.withValues(alpha: 0.5)
            : const Color(0xFFEAF1F7),
        borderRadius: BorderRadius.circular(10.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 14.0,
                color: isDark ? AppColors.accentBlue : AppColors.steelBlue,
              ),
              const SizedBox(width: 6.0),
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.badgeLabel.copyWith(
                    fontSize: 9.0,
                    color: isDark
                        ? AppColors.secondaryTextDark
                        : AppColors.secondaryTextLight,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4.0),
          Text(
            value,
            style: TextStyle(
              fontSize: 15.0,
              fontWeight: FontWeight.w700,
              color: isDark
                  ? AppColors.primaryTextDark
                  : AppColors.primaryTextLight,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10.0,
              color: isDark
                  ? AppColors.secondaryTextDark
                  : AppColors.secondaryTextLight,
            ),
          ),
        ],
      ),
    );
  }
}
