import 'dart:math' as math;
import '../../../../domain/entities/coordinates.dart';
import '../../../../domain/services/route_progress_calculator.dart';
import '../../../navigation/domain/entities/destination.dart';
import '../../../navigation/domain/services/osm_poi_service.dart';
import '../entities/route_poi.dart';
import '../entities/trip_stop_type.dart';

/// Servicio de dominio para descubrir y proyectar puntos de interés (POIs) a lo largo
/// del corredor vial de una ruta calculada en REstelar.
///
/// Responsabilidades:
/// - Acotar las consultas geográficas al corredor vial alrededor de la ruta (`corridorRadiusMeters`).
/// - Muestrear la geometría de la ruta para evitar sobrecargar servidores públicos de Overpass.
/// - Proyectar cada POI con [RouteProgressCalculator] para obtener su distancia perpendicular
///   (cross-track) exacta a la calzada y su kilometraje de avance desde el origen.
/// - Descartar puntos fuera del corredor y filtrar duplicados espaciales.
/// - Cachear resultados para evitar peticiones repetidas.
class RoutePoiExplorerService {
  final OsmPoiService _osmPoiService;
  final RouteProgressCalculator _progressCalculator;
  final Map<String, List<RoutePoi>> _cache = {};

  RoutePoiExplorerService({
    OsmPoiService? osmPoiService,
    RouteProgressCalculator progressCalculator =
        const RouteProgressCalculator(),
  }) : _osmPoiService = osmPoiService ?? OsmPoiService(),
       _progressCalculator = progressCalculator;

  OsmPoiService get osmPoiService => _osmPoiService;

  /// Limpia la caché interna en memoria.
  void clearCache() {
    _cache.clear();
    _osmPoiService.clearCache();
  }

  /// Busca puntos de interés dentro del corredor vial de [routeGeometry].
  ///
  /// Parámetros:
  /// - [routeGeometry]: Vértices ordenados de la calzada calculada (mínimo 2 puntos).
  /// - [category]: Categoría de interés (`fuel`, `motorcycle_repair`, `restaurant`, `viewpoint`, `hairdresser`).
  /// - [corridorRadiusMeters]: Ancho del corredor a ambos lados de la ruta (entre 200m y 10000m, defecto 2000m).
  /// - [maxResults]: Límite de resultados a retornar (defecto 25).
  Future<List<RoutePoi>> findPoisAlongRoute({
    required List<Coordinates> routeGeometry,
    required String category,
    double corridorRadiusMeters = 2000.0,
    int maxResults = 25,
    bool rethrowErrors = false,
  }) async {
    if (routeGeometry.length < 2) {
      return [];
    }

    final clampedRadius = corridorRadiusMeters.clamp(200.0, 10000.0);

    // 1. Verificación de caché
    final cacheKey =
        '${category}_${clampedRadius.round()}_${routeGeometry.first.latitude.toStringAsFixed(3)}_${routeGeometry.first.longitude.toStringAsFixed(3)}_${routeGeometry.last.latitude.toStringAsFixed(3)}_${routeGeometry.last.longitude.toStringAsFixed(3)}_${routeGeometry.length}';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    // 2. Calcular caja envolvente (Bounding Box) de la ruta
    double minLat = routeGeometry.first.latitude;
    double maxLat = routeGeometry.first.latitude;
    double minLon = routeGeometry.first.longitude;
    double maxLon = routeGeometry.first.longitude;

    for (final coord in routeGeometry) {
      if (coord.latitude < minLat) minLat = coord.latitude;
      if (coord.latitude > maxLat) maxLat = coord.latitude;
      if (coord.longitude < minLon) minLon = coord.longitude;
      if (coord.longitude > maxLon) maxLon = coord.longitude;
    }

    final midLatRad = ((minLat + maxLat) / 2.0) * math.pi / 180.0;
    final deltaLat = (clampedRadius * 1.25) / 111320.0;
    final deltaLon =
        (clampedRadius * 1.25) /
        (111320.0 * math.cos(midLatRad).abs().clamp(0.1, 1.0));

    final rawDestinations = <Destination>[];
    final seenDestIds = <String>{};

    final latSpan = maxLat - minLat;
    final lonSpan = maxLon - minLon;

    Object? queryError;
    // Si la ruta abarca una extensión compacta (<= ~20 km de caja), una sola consulta Bbox es óptima
    if (latSpan <= 0.20 && lonSpan <= 0.20) {
      try {
        final results = await _osmPoiService.fetchCategoryPoisInBbox(
          categoryKey: category,
          minLat: minLat - deltaLat,
          minLon: minLon - deltaLon,
          maxLat: maxLat + deltaLat,
          maxLon: maxLon + deltaLon,
          limit: maxResults * 2,
          rethrowErrors: true,
        );
        for (final d in results) {
          if (seenDestIds.add(d.id)) {
            rawDestinations.add(d);
          }
        }
      } catch (e) {
        queryError = e;
      }
    } else {
      // Para recorridos más largos, muestrear ventanas a lo largo de la ruta
      // limitando a máximo 5 consultas para proteger los servidores públicos
      final sampleCenters = _sampleRouteCenters(
        routeGeometry,
        sampleIntervalMeters: math.max(clampedRadius * 3, 15000.0),
        maxSamples: 5,
      );

      for (final center in sampleCenters) {
        try {
          final results = await _osmPoiService.fetchCategoryPois(
            categoryKey: category,
            center: center,
            deltaDegrees: deltaLat,
            limit: 15,
            rethrowErrors: true,
          );
          for (final d in results) {
            if (seenDestIds.add(d.id)) {
              rawDestinations.add(d);
            }
          }
        } catch (e) {
          queryError = e;
        }
      }
    }

    // Si ocurrió un error y no se obtuvo ningún resultado, propagar la excepción si se solicitó
    if (rawDestinations.isEmpty && queryError != null && rethrowErrors) {
      throw queryError;
    }

    // 3. Proyectar ortogonalmente cada POI sobre la calzada con RouteProgressCalculator
    final routePois = <RoutePoi>[];
    for (final dest in rawDestinations) {
      try {
        final progress = _progressCalculator.calculate(
          geometry: routeGeometry,
          currentPosition: dest.coordinates,
        );

        // Descartar si excede el radio del corredor configurado
        if (progress.distanceToRouteMeters <= clampedRadius) {
          final isDuplicate = routePois.any(
            (existing) =>
                existing.id == dest.id ||
                existing.coordinates.distanceTo(dest.coordinates) < 15.0 ||
                (existing.name.toLowerCase() == dest.title.toLowerCase() &&
                    existing.coordinates.distanceTo(dest.coordinates) < 50.0),
          );

          if (!isDuplicate) {
            final type = _mapCategoryToTripStopType(category, dest.title);
            final hasIncomplete =
                dest.title.startsWith('Establecimiento') ||
                dest.title.startsWith('Taller de Motocicletas (') ||
                dest.title == 'Taller de Motocicletas' ||
                dest.title == 'Estación de Servicio / Gasolinera' ||
                dest.title == 'Restaurante / Cafetería' ||
                dest.title == 'Mirador / Punto Panorámico' ||
                dest.subtitle.contains('Lugar cercano');

            routePois.add(
              RoutePoi(
                id: dest.id,
                name: dest.title,
                category: category,
                type: type,
                coordinates: dest.coordinates,
                distanceToRouteMeters: progress.distanceToRouteMeters,
                distanceAlongRouteMeters: progress.distanceTraveledMeters,
                estimatedDetourMeters: progress.distanceToRouteMeters * 2.0,
                subtitle: dest.subtitle,
                hasIncompleteData: hasIncomplete,
              ),
            );
          }
        }
      } catch (_) {
        // Ignorar puntos que no puedan proyectarse
      }
    }

    // 4. Ordenar cronológicamente por avance vial desde el origen (orden de encuentro del viaje)
    routePois.sort(
      (a, b) =>
          a.distanceAlongRouteMeters.compareTo(b.distanceAlongRouteMeters),
    );

    final finalResults = routePois.take(maxResults).toList();
    _cache[cacheKey] = finalResults;
    return finalResults;
  }

  List<Coordinates> _sampleRouteCenters(
    List<Coordinates> geometry, {
    required double sampleIntervalMeters,
    required int maxSamples,
  }) {
    if (geometry.isEmpty) return [];
    if (geometry.length <= 2) return [geometry.first, geometry.last];

    final centers = <Coordinates>[geometry.first];
    double accumulated = 0.0;

    for (int i = 1; i < geometry.length - 1; i++) {
      accumulated += geometry[i - 1].distanceTo(geometry[i]);
      if (accumulated >= sampleIntervalMeters) {
        centers.add(geometry[i]);
        accumulated = 0.0;
        if (centers.length >= maxSamples) break;
      }
    }

    if (centers.length < maxSamples &&
        geometry.last.distanceTo(centers.last) > sampleIntervalMeters / 2) {
      centers.add(geometry.last);
    }
    return centers;
  }

  TripStopType _mapCategoryToTripStopType(String category, String title) {
    final lower = category.toLowerCase();
    final lowerTitle = title.toLowerCase();

    if (lower.contains('fuel') || lowerTitle.contains('gasolin')) {
      return TripStopType.fuel;
    }
    if (lower.contains('repair') ||
        lower.contains('moto') ||
        lower.contains('tyres') ||
        lowerTitle.contains('taller') ||
        lowerTitle.contains('llanta')) {
      return TripStopType.motorcycleWorkshop;
    }
    if (lower.contains('restaurant') ||
        lower.contains('cafe') ||
        lowerTitle.contains('restaurante') ||
        lowerTitle.contains('café')) {
      return TripStopType.restaurant;
    }
    if (lower.contains('viewpoint') ||
        lower.contains('attraction') ||
        lowerTitle.contains('mirador')) {
      return TripStopType.viewpoint;
    }
    if (lower.contains('hairdresser') ||
        lower.contains('barber') ||
        lowerTitle.contains('barber') ||
        lowerTitle.contains('peluquer')) {
      return TripStopType.hairdresser;
    }
    return TripStopType.other;
  }
}
