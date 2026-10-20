import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/widgets/custom_road_art.dart';
import '../../../../core/widgets/storm_badge.dart';

/// Tarjeta principal de la pantalla de inicio «Listo para rodar».
class ReadyToRideCard extends StatelessWidget {
  final VoidCallback onExploreNavigation;

  const ReadyToRideCard({super.key, required this.onExploreNavigation});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Fondo artístico con carretera vectorial
          Positioned(
            right: 0,
            left: 0,
            bottom: 60,
            child: Opacity(
              opacity: isDark ? 0.35 : 0.20,
              child: const CustomRoadArt(height: 140.0),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Fila de estado y badge
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    StormBadge(
                      label: 'Listo para rodar',
                      icon: Icons.check_circle_outline,
                      variant: StormBadgeVariant.success,
                    ),
                    Text(
                      'ESTADO',
                      style: TextStyle(
                        fontSize: 11.0,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                        color: AppColors.secondaryTextLight,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16.0),

                // Título y mensaje de inspiración para el viaje
                Text(
                  'Tu próxima aventura\ncomienza aquí.',
                  style: AppTypography.sectionTitle.copyWith(
                    fontSize: 22.0,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 8.0),

                Text(
                  'Asistencia de ruta visual diseñada para acompañarte en cada kilómetro de carretera.',
                  style: TextStyle(
                    fontSize: 14.0,
                    color: isDark
                        ? AppColors.secondaryTextDark
                        : AppColors.secondaryTextLight,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 24.0),

                // Botón principal de navegación
                ElevatedButton.icon(
                  onPressed: onExploreNavigation,
                  icon: const Icon(Icons.navigation_outlined, size: 20.0),
                  label: const Text('Explorar navegación'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
