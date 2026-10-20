import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../domain/entities/saved_route_metadata.dart';

/// Modal deslizante tipo BottomSheet para gestionar y seleccionar rutas GPX guardadas.
class SavedRoutesSheet extends StatelessWidget {
  final List<SavedRouteMetadata> savedRoutes;
  final String? activeRouteName;
  final ValueChanged<String> onSelectRoute;
  final ValueChanged<String> onDeleteRoute;
  final VoidCallback onImportNew;

  const SavedRoutesSheet({
    super.key,
    required this.savedRoutes,
    this.activeRouteName,
    required this.onSelectRoute,
    required this.onDeleteRoute,
    required this.onImportNew,
  });

  static Future<void> show(
    BuildContext context, {
    required List<SavedRouteMetadata> savedRoutes,
    String? activeRouteName,
    required ValueChanged<String> onSelectRoute,
    required ValueChanged<String> onDeleteRoute,
    required VoidCallback onImportNew,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SavedRoutesSheet(
        savedRoutes: savedRoutes,
        activeRouteName: activeRouteName,
        onSelectRoute: (id) {
          Navigator.of(ctx).pop();
          onSelectRoute(id);
        },
        onDeleteRoute: onDeleteRoute,
        onImportNew: () {
          Navigator.of(ctx).pop();
          onImportNew();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.whiteSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24.0)),
        border: Border.all(
          color: isDark
              ? AppColors.steelBlue.withValues(alpha: 0.35)
              : AppColors.silver,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tirador decorativo superior
          Center(
            child: Container(
              width: 40.0,
              height: 4.0,
              decoration: BoxDecoration(
                color: isDark ? AppColors.steelBlue : AppColors.silver,
                borderRadius: BorderRadius.circular(2.0),
              ),
            ),
          ),
          const SizedBox(height: 16.0),

          // Título y botón de importación
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'BIBLIOTECA DE RUTAS GPX',
                style: AppTypography.badgeLabel.copyWith(
                  color: isDark ? AppColors.accentBlue : AppColors.steelBlue,
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: onImportNew,
                icon: const Icon(Icons.file_upload_outlined, size: 16.0),
                label: const Text('Importar nuevo'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14.0),

          // Lista de rutas guardadas
          if (savedRoutes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36.0),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.folder_open_outlined,
                      size: 44.0,
                      color: isDark
                          ? AppColors.secondaryTextDark
                          : AppColors.secondaryTextLight,
                    ),
                    const SizedBox(height: 12.0),
                    Text(
                      'No tienes rutas GPX guardadas en el dispositivo.',
                      style: TextStyle(
                        fontSize: 13.0,
                        color: isDark
                            ? AppColors.secondaryTextDark
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
                itemCount: savedRoutes.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 8.0),
                itemBuilder: (ctx, index) {
                  final route = savedRoutes[index];
                  final isActive = route.name == activeRouteName;

                  return Container(
                    decoration: BoxDecoration(
                      color: isActive
                          ? (isDark
                                ? AppColors.steelBlue.withValues(alpha: 0.25)
                                : const Color(0xFFE9F2FA))
                          : (isDark
                                ? AppColors.darkSurfaceVariant
                                : AppColors.lightBackground),
                      borderRadius: BorderRadius.circular(12.0),
                      border: Border.all(
                        color: isActive
                            ? (isDark
                                  ? AppColors.accentBlue
                                  : AppColors.steelBlue)
                            : (isDark
                                  ? AppColors.steelBlue.withValues(alpha: 0.2)
                                  : AppColors.silver),
                        width: isActive ? 1.5 : 1.0,
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14.0,
                        vertical: 4.0,
                      ),
                      leading: CircleAvatar(
                        backgroundColor: isActive
                            ? (isDark
                                  ? AppColors.accentBlue
                                  : AppColors.steelBlue)
                            : (isDark
                                  ? AppColors.darkSurface
                                  : AppColors.whiteSurface),
                        child: Icon(
                          Icons.route_outlined,
                          size: 20.0,
                          color: isActive
                              ? (isDark ? AppColors.stormNavy : Colors.white)
                              : (isDark
                                    ? AppColors.accentBlue
                                    : AppColors.steelBlue),
                        ),
                      ),
                      title: Text(
                        route.name,
                        style: TextStyle(
                          fontSize: 14.0,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppColors.primaryTextDark
                              : AppColors.primaryTextLight,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${route.totalDistanceKm.toStringAsFixed(1)} km • ${route.totalPoints} puntos • ${route.segmentCount} tramo(s)',
                        style: TextStyle(
                          fontSize: 11.0,
                          color: isDark
                              ? AppColors.secondaryTextDark
                              : AppColors.secondaryTextLight,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isActive)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6.0,
                                vertical: 2.0,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.success.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4.0),
                              ),
                              child: const Text(
                                'ACTIVA',
                                style: TextStyle(
                                  fontSize: 9.0,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF2E7D32),
                                ),
                              ),
                            )
                          else
                            IconButton(
                              icon: const Icon(
                                Icons.arrow_forward_ios,
                                size: 14.0,
                              ),
                              tooltip: 'Cargar esta ruta',
                              onPressed: () => onSelectRoute(route.id),
                            ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              size: 18.0,
                              color: Color(0xFFE57373),
                            ),
                            tooltip: 'Eliminar del dispositivo',
                            onPressed: () => _confirmDelete(ctx, route),
                          ),
                        ],
                      ),
                      onTap: () => onSelectRoute(route.id),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, SavedRouteMetadata route) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar ruta guardada?'),
        content: Text(
          'Se eliminará "${route.name}" del almacenamiento local del dispositivo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              onDeleteRoute(route.id);
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}
