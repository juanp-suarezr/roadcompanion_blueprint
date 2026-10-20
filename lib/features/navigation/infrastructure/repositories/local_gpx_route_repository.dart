import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

import '../../domain/entities/imported_gpx_route.dart';
import '../../domain/entities/saved_route_metadata.dart';
import '../../domain/repositories/gpx_route_repository.dart';
import '../parsers/gpx_parser.dart';

/// Implementación local persistente de [GpxRouteRepository] en el almacenamiento privado de la app.
///
/// Guarda los archivos `.gpx` originales en el subdirectorio `gpx_routes/` y mantiene
/// un índice JSON liviano (`routes_index.json`) para listar rutas sin recargar polilíneas pesadas.
class LocalGpxRouteRepository implements GpxRouteRepository {
  final Future<Directory> Function()? _directoryProvider;
  final GpxParser _parser;

  Directory? _cachedRoutesDir;

  LocalGpxRouteRepository({
    Future<Directory> Function()? directoryProvider,
    GpxParser parser = const GpxParser(),
  }) : _directoryProvider = directoryProvider,
       _parser = parser;

  Future<Directory> _getRoutesDirectory() async {
    if (_cachedRoutesDir != null) return _cachedRoutesDir!;
    final baseDir = _directoryProvider != null
        ? await _directoryProvider()
        : await getApplicationDocumentsDirectory();

    final routesDir = Directory('${baseDir.path}/gpx_routes');
    if (!await routesDir.exists()) {
      await routesDir.create(recursive: true);
    }
    _cachedRoutesDir = routesDir;
    return routesDir;
  }

  File _getIndexFile(Directory routesDir) {
    return File('${routesDir.path}/routes_index.json');
  }

  @override
  Future<List<SavedRouteMetadata>> getSavedRoutes() async {
    final routesDir = await _getRoutesDirectory();
    final indexFile = _getIndexFile(routesDir);

    if (!await indexFile.exists()) {
      return [];
    }

    try {
      final jsonStr = await indexFile.readAsString();
      final list = jsonDecode(jsonStr) as List<dynamic>;

      final validRoutes = <SavedRouteMetadata>[];
      bool indexNeedsUpdate = false;

      for (final item in list) {
        final meta = SavedRouteMetadata.fromJson(item as Map<String, dynamic>);
        final gpxFile = File('${routesDir.path}/${meta.id}.gpx');

        // Verificar si el archivo físico sigue existiendo
        if (await gpxFile.exists()) {
          validRoutes.add(meta);
        } else {
          indexNeedsUpdate = true;
        }
      }

      if (indexNeedsUpdate) {
        await _saveIndex(routesDir, validRoutes);
      }

      // Ordenar por fecha de importación más reciente primero
      validRoutes.sort((a, b) => b.importedAt.compareTo(a.importedAt));
      return validRoutes;
    } catch (_) {
      return [];
    }
  }

  @override
  Future<ImportedGpxRoute> loadRoute(String id) async {
    final routesDir = await _getRoutesDirectory();
    final gpxFile = File('${routesDir.path}/$id.gpx');

    if (!await gpxFile.exists()) {
      // Limpiar índice si el archivo fue eliminado externamente
      final routes = await getSavedRoutes();
      final updated = routes.where((r) => r.id != id).toList();
      await _saveIndex(routesDir, updated);
      throw FileSystemException(
        'El archivo GPX asociado a la ruta "$id" no existe en el almacenamiento local.',
        gpxFile.path,
      );
    }

    final content = await gpxFile.readAsString();
    return _parser.parse(content, fallbackName: 'Ruta $id');
  }

  @override
  Future<SavedRouteMetadata> saveRoute({
    required String originalFileName,
    required String rawGpxContent,
    required ImportedGpxRoute parsedRoute,
  }) async {
    final routesDir = await _getRoutesDirectory();
    final existingRoutes = await getSavedRoutes();

    // Comprobar si ya existe una ruta con idéntico nombre y cantidad de puntos
    final existingIndex = existingRoutes.indexWhere(
      (r) =>
          r.name == parsedRoute.name &&
          r.totalPoints == parsedRoute.totalPoints,
    );

    final String id;
    if (existingIndex >= 0) {
      id = existingRoutes[existingIndex].id;
    } else {
      id = 'gpx_${DateTime.now().millisecondsSinceEpoch}';
    }

    final gpxFile = File('${routesDir.path}/$id.gpx');
    await gpxFile.writeAsString(rawGpxContent);

    final metadata = SavedRouteMetadata(
      id: id,
      name: parsedRoute.name,
      fileName: originalFileName,
      totalDistanceMeters: parsedRoute.totalGeographicDistanceMeters,
      totalPoints: parsedRoute.totalPoints,
      segmentCount: parsedRoute.segments.length,
      minElevation: parsedRoute.minElevation,
      maxElevation: parsedRoute.maxElevation,
      importedAt: DateTime.now(),
    );

    final updatedRoutes = List<SavedRouteMetadata>.from(existingRoutes);
    if (existingIndex >= 0) {
      updatedRoutes[existingIndex] = metadata;
    } else {
      updatedRoutes.insert(0, metadata);
    }

    await _saveIndex(routesDir, updatedRoutes);
    return metadata;
  }

  @override
  Future<void> deleteRoute(String id) async {
    final routesDir = await _getRoutesDirectory();
    final gpxFile = File('${routesDir.path}/$id.gpx');

    if (await gpxFile.exists()) {
      await gpxFile.delete();
    }

    final existingRoutes = await getSavedRoutes();
    final updated = existingRoutes.where((r) => r.id != id).toList();
    await _saveIndex(routesDir, updated);
  }

  Future<void> _saveIndex(
    Directory routesDir,
    List<SavedRouteMetadata> routes,
  ) async {
    final indexFile = _getIndexFile(routesDir);
    final jsonList = routes.map((r) => r.toJson()).toList();
    await indexFile.writeAsString(jsonEncode(jsonList));
  }
}
