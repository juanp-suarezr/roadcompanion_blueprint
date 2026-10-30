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
  final Duration _requestTimeout;

  NominatimGeocodingService({
    http.Client? client,
    String userAgent =
        'REstelarNavigationApp/1.0 (contact: restelar@roadcompanion.app)',
    OsmPoiService? osmPoiService,
    Duration requestTimeout = const Duration(seconds: 8),
  }) : _client = client ?? http.Client(),
       _userAgent = userAgent,
       _osmPoiService = osmPoiService ?? OsmPoiService(client: client),
       _requestTimeout = requestTimeout;

  OsmPoiService get osmPoiService => _osmPoiService;

  /// Expresión regular para detectar coordenadas decimales ingresadas directamente en la búsqueda
  /// (ej: "4.78389, -75.05948" o "4.78389 -75.05948").
  static final RegExp _latLngPattern = RegExp(
    r'^\s*([-+]?(?:[1-8]?\d(?:\.\d+)?|90(?:\.0+)?))(?:\s*,\s*|\s+)([-+]?(?:180(?:\.0+)?|(?:1[0-7]\d|[1-9]?\d)(?:\.\d+)?))\s*$',
  );

  /// Intenta parsear una consulta como coordenadas geográficas directas.
  static Destination? tryParseCoordinatesQuery(String query) {
    final match = _latLngPattern.firstMatch(query.trim());
    if (match != null) {
      final lat = double.tryParse(match.group(1)!);
      final lon = double.tryParse(match.group(2)!);
      if (lat != null &&
          lon != null &&
          lat >= -90.0 &&
          lat <= 90.0 &&
          lon >= -180.0 &&
          lon <= 180.0) {
        final latStr = lat.toStringAsFixed(5);
        final lonStr = lon.toStringAsFixed(5);
        return Destination(
          id: 'coord_${latStr}_$lonStr',
          title: 'Coordenadas: $latStr, $lonStr',
          subtitle: 'Ubicación geográfica directa',
          coordinates: Coordinates(lat, lon),
          category: 'coordinates',
        );
      }
    }
    return null;
  }

  @override
  Future<List<Destination>> search(
    String query, {
    Coordinates? proximityHint,
    int limit = 10,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      return [];
    }

    // 1. Detección inmediata de coordenadas decimales
    final directCoord = tryParseCoordinatesQuery(cleanQuery);
    if (directCoord != null) {
      // Opcionalmente intentar enriquecer con geocodificación inversa sin bloquear
      try {
        final reversed = await reverseGeocode(directCoord.coordinates);
        if (reversed != null && reversed.title.isNotEmpty) {
          return [
            Destination(
              id: directCoord.id,
              title: reversed.title,
              subtitle:
                  '${reversed.subtitle.isNotEmpty ? "${reversed.subtitle} • " : ""}Coordenadas: ${directCoord.coordinates.latitude.toStringAsFixed(5)}, ${directCoord.coordinates.longitude.toStringAsFixed(5)}',
              coordinates: directCoord.coordinates,
              category: reversed.category ?? 'coordinates',
            ),
          ];
        }
      } catch (_) {}
      return [directCoord];
    }

    if (cleanQuery.length < 2) {
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
          .timeout(_requestTimeout);

      if (response.statusCode == 429) {
        throw HttpException(
          'Límite de solicitudes excedido en el proveedor de búsqueda (HTTP 429). Reintenta en unos segundos.',
          uri: uri,
        );
      }

      if (response.statusCode != 200) {
        throw HttpException(
          'El proveedor de búsqueda respondió con código HTTP ${response.statusCode}',
          uri: uri,
        );
      }

      final List<dynamic> list = jsonDecode(response.body) as List<dynamic>;
      var results = _deduplicateDestinations(_parseDestinationList(list));

      // Fallback 1: Si la consulta original no arrojó resultados y contiene
      // abreviaturas viales colombianas (Cra, Cl, Av, #) o prefijos "Barrio"/"Vereda",
      // reintentar con la consulta normalizada.
      if (results.isEmpty) {
        final normalizedFallback = normalizeColombianQuery(cleanQuery);
        if (normalizedFallback.length >= 2 &&
            normalizedFallback.toLowerCase() != cleanQuery.toLowerCase()) {
          final fallbackParams = Map<String, String>.from(queryParams)
            ..['q'] = normalizedFallback;
          final fallbackUri = Uri.https(
            'nominatim.openstreetmap.org',
            '/search',
            fallbackParams,
          );
          try {
            final fallbackResp = await _client
                .get(
                  fallbackUri,
                  headers: {
                    'User-Agent': _userAgent,
                    'Accept': 'application/json',
                  },
                )
                .timeout(const Duration(seconds: 8));
            if (fallbackResp.statusCode == 200) {
              final List<dynamic> fallbackList =
                  jsonDecode(fallbackResp.body) as List<dynamic>;
              results = _deduplicateDestinations(
                _parseDestinationList(fallbackList),
              );
            }
          } catch (_) {}
        }
      }

      // Fallback 2: Si Nominatim aún no arrojó resultados (típico en veredas, miradores,
      // picos o topónimos rurales de Colombia), consultar el motor Photon (Komoot OSM).
      if (results.isEmpty) {
        results = await _queryPhotonFallback(
          cleanQuery,
          limit: limit,
          proximityHint: proximityHint,
        );
      }

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

  /// Normaliza abreviaturas de nomenclatura vial colombiana y prefijos de barrio/vereda
  /// para mejorar coincidencias en OpenStreetMap Nominatim cuando la búsqueda literal no arroja resultados.
  static String normalizeColombianQuery(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return s;

    // Expandir abreviaturas viales al inicio o tras coma/espacio
    s = s.replaceAllMapped(
      RegExp(r'\b(cra|kr|kra)\.?\s*(\d+[a-zA-Z]?)', caseSensitive: false),
      (m) => 'Carrera ${m.group(2)}',
    );
    s = s.replaceAllMapped(
      RegExp(r'\b(cll|cl)\.?\s*(\d+[a-zA-Z]?)', caseSensitive: false),
      (m) => 'Calle ${m.group(2)}',
    );
    s = s.replaceAllMapped(
      RegExp(r'\b(av|avda)\.?\s+', caseSensitive: false),
      (_) => 'Avenida ',
    );
    s = s.replaceAllMapped(
      RegExp(r'\b(dg|diag)\.?\s*(\d+[a-zA-Z]?)', caseSensitive: false),
      (m) => 'Diagonal ${m.group(2)}',
    );
    s = s.replaceAllMapped(
      RegExp(r'\b(tv|tr|transv)\.?\s*(\d+[a-zA-Z]?)', caseSensitive: false),
      (m) => 'Transversal ${m.group(2)}',
    );

    // Simplificar placas domiciliarias "# 45-12" o "No. 45-12" que Nominatim no indexa
    s = s.replaceAll(
      RegExp(
        r'(?:\s*(?:#|no\.?|n°|nro\.?)\s*\d+[a-zA-Z]?(?:\s*-\s*\d+)?)'
        r'|(?:\s+\d+\s*-\s*\d+)',
        caseSensitive: false,
      ),
      '',
    );

    // Remover prefijos genéricos "Barrio " o "Urbanización " si impiden hallar el topónimo en OSM
    s = s.replaceFirst(
      RegExp(r'^(barrio|urbanizaci[oó]n|urb\.?)\s+', caseSensitive: false),
      '',
    );

    // Limpiar espacios múltiples y comas sueltas
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    s = s.replaceAll(RegExp(r'^,\s*|,\s*$'), '').trim();
    return s;
  }

  List<Destination> _deduplicateDestinations(List<Destination> items) {
    final deduplicated = <Destination>[];
    final seenIds = <String>{};
    for (final dest in items) {
      if (!seenIds.add(dest.id)) continue;
      final isSpatialDuplicate = deduplicated.any(
        (existing) =>
            existing.title.toLowerCase() == dest.title.toLowerCase() &&
            existing.coordinates.distanceTo(dest.coordinates) < 25.0,
      );
      if (!isSpatialDuplicate) {
        deduplicated.add(dest);
      }
    }
    return deduplicated;
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

  /// Consulta el motor Photon (Komoot OSM) como fallback para topónimos rurales, veredas y accidentes geográficos.
  Future<List<Destination>> _queryPhotonFallback(
    String query, {
    int limit = 10,
    Coordinates? proximityHint,
  }) async {
    try {
      final queryParams = <String, String>{
        'q': query,
        'limit': limit.toString(),
        'lang': 'es',
      };
      if (proximityHint != null) {
        queryParams['lat'] = proximityHint.latitude.toString();
        queryParams['lon'] = proximityHint.longitude.toString();
      }

      final uri = Uri.https('photon.komoot.io', '/api/', queryParams);
      final response = await _client
          .get(
            uri,
            headers: {'User-Agent': _userAgent, 'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 6));

      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final features = data['features'] as List<dynamic>? ?? [];
      final results = <Destination>[];

      for (final f in features) {
        final feature = f as Map<String, dynamic>;
        final props = feature['properties'] as Map<String, dynamic>? ?? {};
        final geom = feature['geometry'] as Map<String, dynamic>? ?? {};
        final coords = geom['coordinates'] as List<dynamic>? ?? [];

        if (coords.length < 2) continue;
        final lon = (coords[0] as num).toDouble();
        final lat = (coords[1] as num).toDouble();

        // Filtrar prioritariamente por Colombia si no se especifica país
        final countryCode = (props['countrycode'] as String?)?.toUpperCase();
        if (countryCode != null && countryCode != 'CO') continue;

        final name = (props['name'] as String?)?.trim() ?? '';
        if (name.isEmpty) continue;

        final city =
            props['city'] ??
            props['town'] ??
            props['district'] ??
            props['county'];
        final state = props['state'] ?? '';
        final country = props['country'] ?? 'Colombia';

        final subtitleParts = <String>[];
        if (city != null && city.toString().trim().isNotEmpty) {
          subtitleParts.add(city.toString().trim());
        }
        if (state.toString().trim().isNotEmpty) {
          subtitleParts.add(state.toString().trim());
        }
        if (subtitleParts.isEmpty) {
          subtitleParts.add(country.toString().trim());
        }

        final osmId = props['osm_id']?.toString() ?? 'photon_${lat}_$lon';
        final osmValue = props['osm_value'] as String?;

        results.add(
          Destination(
            id: osmId,
            title: name,
            subtitle: subtitleParts.join(', '),
            coordinates: Coordinates(lat, lon),
            category: osmValue,
          ),
        );
      }

      return _deduplicateDestinations(results);
    } catch (_) {
      return [];
    }
  }
}
