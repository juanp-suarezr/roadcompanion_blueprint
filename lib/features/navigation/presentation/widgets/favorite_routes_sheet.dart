import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../domain/entities/saved_favorite_route.dart';
import '../../domain/services/smart_navigation_memory_service.dart';

/// Modal para consultar, volver a calcular o eliminar rutas favoritas guardadas en la memoria local.
class FavoriteRoutesSheet extends StatefulWidget {
  final SmartNavigationMemoryService memoryService;
  final ValueChanged<SavedFavoriteRoute> onRouteSelected;

  const FavoriteRoutesSheet({
    super.key,
    required this.memoryService,
    required this.onRouteSelected,
  });

  static Future<SavedFavoriteRoute?> show(
    BuildContext context, {
    required SmartNavigationMemoryService memoryService,
  }) {
    return showModalBottomSheet<SavedFavoriteRoute>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FavoriteRoutesSheet(
        memoryService: memoryService,
        onRouteSelected: (route) => Navigator.of(ctx).pop(route),
      ),
    );
  }

  @override
  State<FavoriteRoutesSheet> createState() => _FavoriteRoutesSheetState();
}

class _FavoriteRoutesSheetState extends State<FavoriteRoutesSheet> {
  late List<SavedFavoriteRoute> _favorites;

  @override
  void initState() {
    super.initState();
    _favorites = widget.memoryService.favoriteRoutes;
  }

  Future<void> _deleteFavorite(String id) async {
    await widget.memoryService.deleteFavoriteRoute(id);
    setState(() {
      _favorites = widget.memoryService.favoriteRoutes;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.80,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
      decoration: BoxDecoration(
        color: isDark ? AppColors.nightBlue : AppColors.whiteSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24.0)),
        border: Border.all(
          color: isDark ? const Color(0xFF264660) : AppColors.silver,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tirador
          Center(
            child: Container(
              width: 36.0,
              height: 4.0,
              decoration: BoxDecoration(
                color: isDark ? AppColors.cardNavy : AppColors.silver,
                borderRadius: BorderRadius.circular(2.0),
              ),
            ),
          ),
          const SizedBox(height: 14.0),

          // Título
          Row(
            children: [
              const Icon(
                Icons.star_rounded,
                color: AppColors.cyanLuminous,
                size: 24.0,
              ),
              const SizedBox(width: 8.0),
              Text(
                'RUTAS FAVORITAS (${_favorites.length})',
                style: TextStyle(
                  fontSize: 15.0,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: isDark
                      ? AppColors.coldWhite
                      : AppColors.primaryTextLight,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 20.0),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 12.0),

          if (_favorites.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40.0),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.bookmark_border,
                      size: 40.0,
                      color: isDark
                          ? AppColors.secondaryText
                          : AppColors.secondaryTextLight,
                    ),
                    const SizedBox(height: 12.0),
                    Text(
                      'Aún no tienes rutas guardadas en tu memoria.\nGuarda una ruta con el botón ⭐ para acceder a ella con un toque.',
                      style: TextStyle(
                        fontSize: 13.0,
                        color: isDark
                            ? AppColors.secondaryText
                            : AppColors.secondaryTextLight,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _favorites.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 8.0),
                itemBuilder: (context, index) {
                  final fav = _favorites[index];
                  return Material(
                    color: isDark
                        ? AppColors.cardNavy
                        : AppColors.lightBackground,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.0),
                      side: BorderSide(
                        color: isDark
                            ? const Color(0xFF264660)
                            : AppColors.silver,
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14.0,
                        vertical: 6.0,
                      ),
                      leading: CircleAvatar(
                        backgroundColor: isDark
                            ? AppColors.surfaceNavy
                            : const Color(0xFFE2EDF7),
                        child: const Icon(
                          Icons.navigation,
                          size: 18.0,
                          color: AppColors.cyanLuminous,
                        ),
                      ),
                      title: Text(
                        fav.destinationTitle,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppColors.coldWhite
                              : AppColors.primaryTextLight,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        'Desde ${fav.originTitle} • ${fav.formattedDuration} (${fav.distanceKm.toStringAsFixed(1)} km)',
                        style: TextStyle(
                          fontSize: 12.0,
                          color: isDark
                              ? AppColors.secondaryText
                              : AppColors.secondaryTextLight,
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20.0),
                        color: AppColors.error,
                        onPressed: () => _deleteFavorite(fav.id),
                        tooltip: 'Eliminar de favoritos',
                      ),
                      onTap: () => widget.onRouteSelected(fav),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
