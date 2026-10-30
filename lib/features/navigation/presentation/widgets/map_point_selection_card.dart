import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../domain/entities/destination.dart';

/// Tarjeta inferior de acción para un punto seleccionado directamente en el mapa.
class MapPointSelectionCard extends StatelessWidget {
  final Destination destination;
  final bool isReverseGeocoding;
  final VoidCallback onStartNavigation;
  final VoidCallback onSaveFavorite;
  final VoidCallback onClose;

  const MapPointSelectionCard({
    super.key,
    required this.destination,
    this.isReverseGeocoding = false,
    required this.onStartNavigation,
    required this.onSaveFavorite,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: isDark ? AppColors.nightBlue : AppColors.whiteSurface,
      elevation: 12.0,
      shadowColor: Colors.black87,
      borderRadius: BorderRadius.circular(20.0),
      child: Container(
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20.0),
          border: Border.all(
            color: isDark ? const Color(0xFF264660) : AppColors.silver,
            width: 1.2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.cardNavy
                        : const Color(0xFFE2E8F0),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.location_on_rounded,
                    color: AppColors.cyanLuminous,
                    size: 24.0,
                  ),
                ),
                const SizedBox(width: 12.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              destination.title,
                              style: AppTypography.sectionTitle.copyWith(
                                color: isDark
                                    ? AppColors.coldWhite
                                    : AppColors.primaryTextLight,
                                fontWeight: FontWeight.bold,
                                fontSize: 16.0,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isReverseGeocoding) ...[
                            const SizedBox(width: 8.0),
                            const SizedBox(
                              width: 14.0,
                              height: 14.0,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.0,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4.0),
                      Text(
                        destination.subtitle.isNotEmpty
                            ? destination.subtitle
                            : 'Coordenadas: ${destination.coordinates.latitude.toStringAsFixed(5)}, ${destination.coordinates.longitude.toStringAsFixed(5)}',
                        style: TextStyle(
                          fontSize: 12.0,
                          color: isDark
                              ? AppColors.secondaryTextDark
                              : AppColors.secondaryTextLight,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4.0),
                      Text(
                        '${destination.coordinates.latitude.toStringAsFixed(5)}, ${destination.coordinates.longitude.toStringAsFixed(5)}',
                        style: const TextStyle(
                          fontSize: 11.0,
                          fontFamily: 'monospace',
                          color: AppColors.cyanLuminous,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20.0),
                  onPressed: onClose,
                  tooltip: 'Cerrar',
                ),
              ],
            ),
            const SizedBox(height: 16.0),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onSaveFavorite,
                    icon: const Icon(Icons.star_outline_rounded, size: 18.0),
                    label: const Text('Favorito'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark
                          ? AppColors.coldWhite
                          : AppColors.primaryTextLight,
                      side: BorderSide(
                        color: isDark
                            ? const Color(0xFF335577)
                            : Colors.grey.shade400,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12.0),
                    ),
                  ),
                ),
                const SizedBox(width: 10.0),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: onStartNavigation,
                    icon: const Icon(Icons.navigation_rounded, size: 18.0),
                    label: const Text('Calcular Ruta'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.cyanLuminous,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12.0),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
