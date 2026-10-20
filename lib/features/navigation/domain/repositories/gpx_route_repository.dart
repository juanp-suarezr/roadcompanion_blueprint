import '../entities/imported_gpx_route.dart';
import '../entities/saved_route_metadata.dart';

/// Contrato para la persistencia y gestión de rutas GPX en almacenamiento local.
abstract class GpxRouteRepository {
  /// Obtiene la lista de metadatos de todas las rutas GPX guardadas localmente.
  Future<List<SavedRouteMetadata>> getSavedRoutes();

  /// Carga y parsea una ruta GPX completa a partir de su [id].
  Future<ImportedGpxRoute> loadRoute(String id);

  /// Guarda una nueva ruta GPX persistiendo su archivo XML y registrando sus metadatos.
  Future<SavedRouteMetadata> saveRoute({
    required String originalFileName,
    required String rawGpxContent,
    required ImportedGpxRoute parsedRoute,
  });

  /// Elimina una ruta guardada y su archivo físico asociado en disco.
  Future<void> deleteRoute(String id);
}
