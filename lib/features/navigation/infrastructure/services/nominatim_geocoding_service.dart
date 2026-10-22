import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../../../../domain/entities/coordinates.dart';
import '../../domain/entities/destination.dart';
import '../../domain/services/geocoding_service.dart';
import '../../domain/services/navigation_diagnostic_logger.dart';
import '../../domain/services/osm_poi_service.dart';

/// Implementación de [GeocodingService] utilizando la API de OpenStreetMap (Nominatim).
///
/// Implementa dos flujos de búsqueda diferenciados según las directrices viales de REstelar:
/// 1. Búsqueda local especializada por categoría (ej. gasolineras `amenity=fuel`):
///    - Acotada estrictamente a la región del usuario (`bounded=1`) para impedir resultados de otros países.
///    - Expansión progresiva de radio (~5 km -> ~15 km -> ~30 km) si no se alcanzan suficientes resultados.
///    - Ordenamiento por distancia geodésica real y eliminación de duplicados.
/// 2. Búsqueda geográfica de destinos concretos (ej. "Guadalupe", "Pereira", "Armenia"):
///    - Conserva contexto regional/nacional sin restringir ciudades legítimamente lejanas (`bounded=0`).
///    - Construye subtítulos enriquecidos para desambiguar homónimos (municipio y departamento).
class NominatimGeocodingService implements GeocodingService {
  final http.Client _client;
  final String _userAgent;
  final OsmPoiService _osmPoiService;

  NominatimGeocodingService({
    http.Client? client,
    String userAgent =
        'REstelarNavigationApp/1.0 (contact: restelar@roadcompanion.app)',
    OsmPoiService? osmPoiService,
  }) : _client = client ?? http.Client(),
       _userAgent = userAgent,
       _osmPoiService = osmPoiService ?? OsmPoiService(client: client);

  OsmPoiService get osmPoiService => _osmPoiService;

  @override
  Future<List<Destination>> search(
    String query, {
    Coordinates? proximityHint,
    int limit = 10,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty || cleanQuery.length < 2) {
      return [];
    }

    final queryParams = <String, String>{
      'q': cleanQuery,
      'format': 'jsonv2',
      'addressdetails': '1',
      'limit': limit.toString(),
      'accept-language': 'es',
    };

    // Si la consulta no especifica un país externo explícito, contextualizar prioritariamente en Colombia
    final lower = cleanQuery.toLowerCase();
    final hasExplicitCountry =
        lower.contains('ecuador') ||
        lower.contains('venezuela') ||
        lower.contains('peru') ||
        lower.contains('perú') ||
        lower.contains('panama') ||
        lower.contains('panamá') ||
        lower.contains('españa') ||
        lower.contains('mexico') ||
        lower.contains('méxico');

    if (!hasExplicitCountry) {
      queryParams['countrycodes'] = 'co';
    }

    if (proximityHint != null) {
      // Ponderación regional suave sin descartar destinos lejanos (bounded=0)
      queryParams['viewbox'] =
          '${proximityHint.longitude - 2.5},${proximityHint.latitude + 2.5},${proximityHint.longitude + 2.5},${proximityHint.latitude - 2.5}';
      queryParams['bounded'] = '0';
    }

    NavigationDiagnosticLogger.logSearchStart(
      originalQuery: query,
      normalizedQuery: cleanQuery,
      isCategory: false,
      userLocation: proximityHint,
      provider: 'Nominatim (nominatim.openstreetmap.org/search)',
      parameters: queryParams,
    );

    final uri = Uri.https(
      'nominatim.openstreetmap.org',
      '/search',
      queryParams,
    );

    try {
      final response = await _client
          .get(
            uri,
            headers: {'User-Agent': _userAgent, 'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        throw HttpException(
          'El proveedor de búsqueda respondió con código HTTP ${response.statusCode}',
          uri: uri,
        );
      }

      final List<dynamic> list = jsonDecode(response.body) as List<dynamic>;
      final results = _parseDestinationList(list);

      NavigationDiagnosticLogger.logSearchResults(
        query: cleanQuery,
        rawResultsCount: list.length,
        results: results,
        userLocation: proximityHint,
      );

      return results;
    } on TimeoutException {
      throw const SocketException(
        'Tiempo de espera agotado al conectar con el servidor de búsqueda.',
      );
    }
  }

  @override
  Future<List<Destination>> searchNearbyCategory({
    required String category,
    required Coordinates center,
    int limit = 15,
  }) async {
    final cleanCategory = category.trim().toLowerCase();

    // Radios progresivos en grados (~5 km, ~15 km, ~30 km)
    const progressiveDeltas = [0.045, 0.135, 0.270];

    final accumulatedResults = <Destination>[];
    final seenIds = <String>{};

    for (int step = 0; step < progressiveDeltas.length; step++) {
      final delta = progressiveDeltas[step];
      final maxAllowedMeters = (delta * 125000.0);

      // 1. Intentar consulta de POIs enriquecidos en Overpass (talleres de motos, montallantas, centros comerciales, barberías)
      if (cleanCategory == 'motorcycle_repair' ||
          cleanCategory == 'tyres' ||
          cleanCategory == 'mall' ||
          cleanCategory == 'hairdresser') {
        try {
          final overpassPois = await _osmPoiService.fetchCategoryPois(
            categoryKey: cleanCategory,
            center: center,
            deltaDegrees: delta,
            limit: limit,
          );
          for (final dest in overpassPois) {
            final distanceMeters = center.distanceTo(dest.coordinates);
            if (distanceMeters <= maxAllowedMeters && seenIds.add(dest.id)) {
              final isDuplicate = accumulatedResults.any(
                (existing) =>
                    existing.title.toLowerCase() == dest.title.toLowerCase() &&
                    existing.coordinates.distanceTo(dest.coordinates) < 25.0,
              );
              if (!isDuplicate) {
                accumulatedResults.add(dest);
              }
            }
          }
        } catch (_) {
          // Continúa con Nominatim si Overpass no está disponible
        }
      }

      // Si Overpass ya cubrió el límite solicitado en este radio, finalizamos
      if (accumulatedResults.length >= limit) {
        break;
      }

      // 2. Consulta en Nominatim acotada estrictamente a la caja local del usuario
      final minLon = (center.longitude - delta).toStringAsFixed(6);
      final maxLat = (center.latitude + delta).toStringAsFixed(6);
      final maxLon = (center.longitude + delta).toStringAsFixed(6);
      final minLat = (center.latitude - delta).toStringAsFixed(6);

      final queryParams = <String, String>{
        'format': 'jsonv2',
        'addressdetails': '1',
        'limit': limit.toString(),
        'accept-language': 'es',
        'viewbox': '$minLon,$maxLat,$maxLon,$minLat',
        // bounded=1 es mandatorio: restringe la búsqueda estrictamente a la caja local del usuario
        'bounded': '1',
      };

      // Asignar parámetro de categoría según estándar OSM/Nominatim
      _applyCategoryFilter(queryParams, cleanCategory);

      NavigationDiagnosticLogger.logSearchStart(
        originalQuery: category,
        normalizedQuery: cleanCategory,
        isCategory: true,
        userLocation: center,
        provider:
            'Nominatim Nearby Category (radio paso ${step + 1}: ~${(delta * 111).round()} km)',
        parameters: queryParams,
      );

      final uri = Uri.https(
        'nominatim.openstreetmap.org',
        '/search',
        queryParams,
      );

      try {
        final response = await _client
            .get(
              uri,
              headers: {'User-Agent': _userAgent, 'Accept': 'application/json'},
            )
            .timeout(const Duration(seconds: 8));

        if (response.statusCode != 200) {
          throw HttpException(
            'Error al consultar categoría en Nominatim (HTTP ${response.statusCode})',
            uri: uri,
          );
        }

        final List<dynamic> list = jsonDecode(response.body) as List<dynamic>;
        final parsed = _parseDestinationList(list);

        for (final dest in parsed) {
          final distanceMeters = center.distanceTo(dest.coordinates);
          if (distanceMeters > maxAllowedMeters) {
            continue; // Fuera del radio geográfico permitido
          }

          if (seenIds.add(dest.id)) {
            // Comprobar además duplicados por proximidad (< 25 m) y mismo nombre
            final isDuplicateSpatial = accumulatedResults.any(
              (existing) =>
                  existing.title.toLowerCase() == dest.title.toLowerCase() &&
                  existing.coordinates.distanceTo(dest.coordinates) < 25.0,
            );

            if (!isDuplicateSpatial) {
              accumulatedResults.add(dest);
            }
          }
        }

        // Si ya obtuvimos al menos 3 resultados relevantes, no es necesario expandir más
        if (accumulatedResults.length >= 3 ||
            step == progressiveDeltas.length - 1) {
          break;
        }
      } on TimeoutException {
        if (accumulatedResults.isNotEmpty) break;
        throw const SocketException(
          'Tiempo de espera agotado al consultar lugares cercanos.',
        );
      }
    }

    // Ordenar ascendentemente por distancia real desde el usuario
    accumulatedResults.sort((a, b) {
      final distA = center.distanceTo(a.coordinates);
      final distB = center.distanceTo(b.coordinates);
      return distA.compareTo(distB);
    });

    NavigationDiagnosticLogger.logSearchResults(
      query: cleanCategory,
      rawResultsCount: accumulatedResults.length,
      results: accumulatedResults,
      userLocation: center,
    );

    return accumulatedResults.take(limit).toList();
  }

  void _applyCategoryFilter(
    Map<String, String> queryParams,
    String cleanCategory,
  ) {
    if (cleanCategory == 'fuel' ||
        cleanCategory.contains('gasolin') ||
        cleanCategory.contains('combustible') ||
        cleanCategory.contains('estacion de servicio') ||
        cleanCategory.contains('estaciones de servicio') ||
        cleanCategory.contains('bomba') ||
        cleanCategory.contains('eds')) {
      queryParams['amenity'] = 'fuel';
    } else if (cleanCategory == 'place_of_worship' ||
        cleanCategory.contains('iglesia') ||
        cleanCategory.contains('parroquia') ||
        cleanCategory.contains('capilla') ||
        cleanCategory.contains('catedral') ||
        cleanCategory.contains('templo') ||
        cleanCategory.contains('culto') ||
        cleanCategory.contains('basilica') ||
        cleanCategory.contains('basílica')) {
      queryParams['amenity'] = 'place_of_worship';
    } else if (cleanCategory == 'mall' ||
        cleanCategory.contains('centro comercial') ||
        cleanCategory.contains('centros comerciales') ||
        cleanCategory.contains('plaza comercial')) {
      queryParams['q'] = 'centro comercial';
    } else if (cleanCategory == 'motorcycle_repair' ||
        cleanCategory.contains('taller') ||
        cleanCategory.contains('moto') ||
        cleanCategory.contains('mecanic') ||
        cleanCategory.contains('mecánic') ||
        cleanCategory.contains('repuestos')) {
      queryParams['amenity'] = 'car_repair';
    } else if (cleanCategory == 'tyres' ||
        cleanCategory.contains('montallantas') ||
        cleanCategory.contains('vulcanizadora') ||
        cleanCategory.contains('llanteria') ||
        cleanCategory.contains('llantería') ||
        cleanCategory.contains('llantas')) {
      queryParams['q'] = 'montallantas';
    } else if (cleanCategory == 'hairdresser' ||
        cleanCategory.contains('peluqueria') ||
        cleanCategory.contains('peluquería') ||
        cleanCategory.contains('barberia') ||
        cleanCategory.contains('barbería') ||
        cleanCategory.contains('barber')) {
      queryParams['q'] = 'peluqueria';
    } else if (cleanCategory.contains('restaurant') ||
        cleanCategory.contains('restaurante') ||
        cleanCategory.contains('comida') ||
        cleanCategory.contains('almuerzo')) {
      queryParams['amenity'] = 'restaurant';
    } else if (cleanCategory.contains('cafe') ||
        cleanCategory.contains('café') ||
        cleanCategory.contains('cafeteria')) {
      queryParams['amenity'] = 'cafe';
    } else if (cleanCategory.contains('hotel') ||
        cleanCategory.contains('hospedaje') ||
        cleanCategory.contains('hostal')) {
      queryParams['tourism'] = 'hotel';
    } else if (cleanCategory.contains('hospital') ||
        cleanCategory.contains('clinica') ||
        cleanCategory.contains('clínica')) {
      queryParams['amenity'] = 'hospital';
    } else if (cleanCategory.contains('farmacia') ||
        cleanCategory.contains('drogueria') ||
        cleanCategory.contains('droguería')) {
      queryParams['amenity'] = 'pharmacy';
    } else {
      queryParams['q'] = cleanCategory;
    }
  }

  List<Destination> _parseDestinationList(List<dynamic> list) {
    final results = <Destination>[];

    for (final item in list) {
      if (item is! Map<String, dynamic>) continue;

      final latStr = item['lat'] as String?;
      final lonStr = item['lon'] as String?;
      if (latStr == null || lonStr == null) continue;

      final lat = double.tryParse(latStr);
      final lon = double.tryParse(lonStr);
      if (lat == null || lon == null) continue;

      final rawName = (item['name'] as String? ?? '').trim();
      final displayName = (item['display_name'] as String? ?? '').trim();

      // Si no tiene nombre comercial propio pero es de una categoría conocida,
      // asignarle un título legible basado en la categoría o la vía
      String title = rawName;
      if (title.isEmpty) {
        final address = item['address'] as Map<String, dynamic>?;
        final road = address?['road'] as String?;
        final type = item['type'] as String? ?? '';
        if (type == 'fuel') {
          title = road != null
              ? 'Estación de Servicio ($road)'
              : 'Estación de Servicio';
        } else if (type == 'place_of_worship') {
          title = road != null
              ? 'Lugar de Culto ($road)'
              : 'Iglesia / Lugar de Culto';
        } else if (type == 'mall') {
          title = road != null
              ? 'Centro Comercial ($road)'
              : 'Centro Comercial';
        } else if (type == 'motorcycle' || type == 'car_repair') {
          title = road != null
              ? 'Taller de Motocicletas ($road)'
              : 'Taller de Motocicletas';
        } else if (type == 'tyres') {
          title = road != null
              ? 'Montallantas ($road)'
              : 'Montallantas / Vulcanizadora';
        } else if (type == 'hairdresser') {
          title = road != null
              ? 'Peluquería / Barbería ($road)'
              : 'Peluquería / Barbería';
        } else {
          title = displayName.split(',').first.trim();
        }
      }

      final subtitle = _buildSubtitle(item, displayName);

      final id =
          item['place_id']?.toString() ??
          '${lat.toStringAsFixed(5)}_${lon.toStringAsFixed(5)}';

      results.add(
        Destination(
          id: id,
          title: title,
          subtitle: subtitle,
          coordinates: Coordinates(lat, lon),
          category: item['type'] as String?,
        ),
      );
    }

    return results;
  }

  @override
  Future<Destination?> reverseGeocode(Coordinates coordinates) async {
    final queryParams = {
      'lat': coordinates.latitude.toString(),
      'lon': coordinates.longitude.toString(),
      'format': 'jsonv2',
      'addressdetails': '1',
      'accept-language': 'es',
    };

    final uri = Uri.https(
      'nominatim.openstreetmap.org',
      '/reverse',
      queryParams,
    );

    try {
      final response = await _client
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final name = data['name'] as String? ?? '';
      final displayName = data['display_name'] as String? ?? '';

      final subtitle = _buildSubtitle(data, displayName);

      return Destination(
        id: data['place_id']?.toString() ?? 'rev_${coordinates.latitude}',
        title: name.isNotEmpty ? name : displayName.split(',').first.trim(),
        subtitle: subtitle,
        coordinates: coordinates,
        category: data['type'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  /// Construye un subtítulo legible destacando vía, barrio/vereda, municipio y departamento.
  ///
  /// Esencial para desambiguar homónimos geográficos (ej. "Guadalupe, Dosquebradas, Risaralda"
  /// vs "Guadalupe, Huila" vs "Guadalupe, Santander" vs "Guadalupe, Antioquia").
  String _buildSubtitle(Map<String, dynamic> item, String displayName) {
    final address = item['address'] as Map<String, dynamic>?;
    if (address != null) {
      final road =
          address['road'] ?? address['pedestrian'] ?? address['street'];
      final neighbourhood =
          address['suburb'] ??
          address['neighbourhood'] ??
          address['quarter'] ??
          address['hamlet'] ??
          address['village'];
      final locality =
          address['city'] ??
          address['town'] ??
          address['municipality'] ??
          address['county'];
      final region =
          address['state'] ?? address['department'] ?? address['province'];

      final parts = <String>[];
      if (road != null && road.toString().trim().isNotEmpty) {
        parts.add(road.toString().trim());
      }
      if (neighbourhood != null &&
          neighbourhood.toString().trim().isNotEmpty &&
          neighbourhood.toString().trim() != locality?.toString().trim()) {
        parts.add(neighbourhood.toString().trim());
      }
      if (locality != null && locality.toString().trim().isNotEmpty) {
        parts.add(locality.toString().trim());
      }
      if (region != null &&
          region.toString().trim().isNotEmpty &&
          region.toString().trim() != locality?.toString().trim()) {
        parts.add(region.toString().trim());
      }

      if (parts.isNotEmpty) {
        return parts.join(', ');
      }
    }

    // Fallback cuando addressdetails no provee estructura detallada
    final subtitleParts = displayName.split(',');
    if (subtitleParts.length > 1) {
      return subtitleParts.sublist(1).take(3).map((e) => e.trim()).join(', ');
    }
    return displayName;
  }
}
