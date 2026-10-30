import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../domain/entities/saved_favorite_place.dart';
import '../../domain/services/smart_navigation_memory_service.dart';
import 'edit_favorite_place_dialog.dart';

/// Modal para listar, gestionar y seleccionar lugares favoritos puntuales
/// (Casa, Trabajo, Finca, Mirador, Vereda).
class FavoritePlacesSheet extends StatefulWidget {
  final SmartNavigationMemoryService memoryService;
  final ValueChanged<SavedFavoritePlace> onPlaceSelected;

  const FavoritePlacesSheet({
    super.key,
    required this.memoryService,
    required this.onPlaceSelected,
  });

  static Future<SavedFavoritePlace?> show(
    BuildContext context, {
    required SmartNavigationMemoryService memoryService,
  }) {
    return showModalBottomSheet<SavedFavoritePlace>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FavoritePlacesSheet(
        memoryService: memoryService,
        onPlaceSelected: (place) => Navigator.of(ctx).pop(place),
      ),
    );
  }

  @override
  State<FavoritePlacesSheet> createState() => _FavoritePlacesSheetState();
}

class _FavoritePlacesSheetState extends State<FavoritePlacesSheet> {
  IconData _getCategoryIcon(FavoritePlaceCategory cat) {
    switch (cat) {
      case FavoritePlaceCategory.home:
        return Icons.home_rounded;
      case FavoritePlaceCategory.work:
        return Icons.work_rounded;
      case FavoritePlaceCategory.family:
        return Icons.favorite_rounded;
      case FavoritePlaceCategory.farm:
        return Icons.agriculture_rounded;
      case FavoritePlaceCategory.viewpoint:
        return Icons.landscape_rounded;
      case FavoritePlaceCategory.gasStation:
        return Icons.local_gas_station_rounded;
      case FavoritePlaceCategory.custom:
        return Icons.place_rounded;
    }
  }

  Future<void> _handleEdit(SavedFavoritePlace place) async {
    final updated = await EditFavoritePlaceDialog.show(
      context,
      initialPlace: place,
      coordinates: place.coordinates,
      initialName: place.name,
      initialAddress: place.address,
    );
    if (updated != null) {
      await widget.memoryService.saveFavoritePlace(updated);
      if (mounted) setState(() {});
    }
  }

  Future<void> _handleDelete(SavedFavoritePlace place) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar favorito'),
        content: Text('¿Deseas eliminar "${place.name}" de tus favoritos?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.memoryService.deleteFavoritePlace(place.id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final places = widget.memoryService.favoritePlaces;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.nightBlue : AppColors.whiteSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24.0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12.0),
          Container(
            width: 40.0,
            height: 4.0,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2.0),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 20.0,
              vertical: 14.0,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.star_rounded,
                  color: AppColors.cyanLuminous,
                  size: 26.0,
                ),
                const SizedBox(width: 10.0),
                Expanded(
                  child: Text(
                    'Lugares Favoritos',
                    style: AppTypography.sectionTitle.copyWith(
                      color: isDark
                          ? AppColors.coldWhite
                          : AppColors.primaryTextLight,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1.0),
          if (places.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                children: [
                  Icon(
                    Icons.star_border_rounded,
                    size: 48.0,
                    color: isDark
                        ? AppColors.secondaryTextDark
                        : AppColors.secondaryTextLight,
                  ),
                  const SizedBox(height: 12.0),
                  Text(
                    'Aún no has guardado lugares favoritos.',
                    style: TextStyle(
                      fontSize: 14.0,
                      color: isDark
                          ? AppColors.coldWhite
                          : AppColors.primaryTextLight,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6.0),
                  Text(
                    'Puedes tocar cualquier punto en el mapa o tu ubicación actual para guardar tu casa, finca o sitios rurales.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.0,
                      color: isDark
                          ? AppColors.secondaryTextDark
                          : AppColors.secondaryTextLight,
                    ),
                  ),
                ],
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                itemCount: places.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1.0, indent: 64.0),
                itemBuilder: (ctx, index) {
                  final place = places[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isDark
                          ? AppColors.cardNavy
                          : const Color(0xFFE2E8F0),
                      foregroundColor: AppColors.cyanLuminous,
                      child: Icon(_getCategoryIcon(place.category), size: 22.0),
                    ),
                    title: Text(
                      place.name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppColors.coldWhite
                            : AppColors.primaryTextLight,
                      ),
                    ),
                    subtitle: Text(
                      place.notes ??
                          (place.address ??
                              '${place.coordinates.latitude.toStringAsFixed(4)}, ${place.coordinates.longitude.toStringAsFixed(4)}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.0,
                        color: isDark
                            ? AppColors.secondaryTextDark
                            : AppColors.secondaryTextLight,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20.0),
                          tooltip: 'Editar',
                          onPressed: () => _handleEdit(place),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 20.0,
                          ),
                          tooltip: 'Eliminar',
                          onPressed: () => _handleDelete(place),
                        ),
                      ],
                    ),
                    onTap: () => widget.onPlaceSelected(place),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
