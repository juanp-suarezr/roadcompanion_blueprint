import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../../../domain/entities/coordinates.dart';
import '../entities/destination.dart';

/// Servicio especializado para consultar puntos de interés (POIs) en OpenStreetMap
/// mediante Overpass API con caché en memoria, límites de tasa y manejo defensivo de red.
///
/// Permite localizar establecimientos especializados (talleres de motocicletas, montallantas,
/// peluquerías, centros comerciales) utilizando etiquetas cartográficas nativas (`shop`, `amenity`).
class OsmPoiService {
  final http.Client _client;
  final String _overpassUrl;
  final Map<String, List<Destination>> _cache = {};

  OsmPoiService({
    http.Client? client,
    String overpassUrl = 'https://overpass-api.de/api/interpreter',
  }) : _client = client ?? http.Client(),
       _overpassUrl = overpassUrl;

  /// Consulta lugares de una categoría específica en una caja delimitadora geográfica (Bounding Box).
  Future<List<Destination>> fetchCategoryPoisInBbox({
    required String categoryKey,
    required double minLat,
    required double minLon,
    required double maxLat,
    required double maxLon,
    int limit = 30,
    bool rethrowErrors = false,
  }) async {
    final cacheKey =
        '${categoryKey}_${minLat.toStringAsFixed(3)}_${minLon.toStringAsFixed(3)}_${maxLat.toStringAsFixed(3)}_${maxLon.toStringAsFixed(3)}';

    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    final tagSelector = _resolveTagSelector(categoryKey);
    if (tagSelector == null) {
      return [];
    }

    final bbox = '$minLat,$minLon,$maxLat,$maxLon';
    final overpassQuery =
        '''
[out:json][timeout:6];
(
  $tagSelector($bbox);
);
out center $limit;
''';

    try {
      final uri = Uri.parse(
        '$_overpassUrl?data=${Uri.encodeComponent(overpassQuery)}',
      );
      final response = await _client
          .get(
            uri,
            headers: {
              'User-Agent':
                  'REstelarNavigationApp/1.0 (local motorcycle poi companion; contact: restelar@roadcompanion.app)',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 7));

      if (response.statusCode != 200) {
        if (rethrowErrors) {
          throw Exception(
            'Error en Overpass API (HTTP ${response.statusCode})',
          );
        }
        return [];
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final elements = data['elements'] as List<dynamic>? ?? [];

      final results = <Destination>[];
      for (final el in elements) {
        if (el is! Map<String, dynamic>) continue;
        final tags = el['tags'] as Map<String, dynamic>? ?? {};

        final latNum = (el['lat'] ?? el['center']?['lat']) as num?;
        final lonNum = (el['lon'] ?? el['center']?['lon']) as num?;
        if (latNum == null || lonNum == null) continue;

        final lat = latNum.toDouble();
        final lon = lonNum.toDouble();
        final coords = Coordinates(lat, lon);

        final id = 'osm_${el['type'] ?? 'node'}_${el['id']}';
        final rawName = tags['name']?.toString().trim() ?? '';
        final title = rawName.isNotEmpty
            ? rawName
            : _buildFallbackTitle(categoryKey, tags);

        final subtitle = _buildSubtitle(tags);

        results.add(
          Destination(
            id: id,
            title: title,
            subtitle: subtitle,
            coordinates: coords,
            category: categoryKey,
          ),
        );
      }

      _cache[cacheKey] = results;
      return results;
    } on TimeoutException {
      if (rethrowErrors) rethrow;
      return [];
    } on FormatException {
      if (rethrowErrors) {
        throw Exception(
          'Respuesta no válida o dañada del servidor cartográfico.',
        );
      }
      return [];
    } catch (_) {
      if (rethrowErrors) rethrow;
      return [];
    }
  }

  /// Consulta lugares de una categoría específica en una caja delimitadora alrededor de [center].
  Future<List<Destination>> fetchCategoryPois({
    required String categoryKey,
    required Coordinates center,
    required double deltaDegrees,
    int limit = 15,
    bool rethrowErrors = false,
  }) async {
    final minLat = center.latitude - deltaDegrees;
    final minLon = center.longitude - deltaDegrees;
    final maxLat = center.latitude + deltaDegrees;
    final maxLon = center.longitude + deltaDegrees;

    return fetchCategoryPoisInBbox(
      categoryKey: categoryKey,
      minLat: minLat,
      minLon: minLon,
      maxLat: maxLat,
      maxLon: maxLon,
      limit: limit,
      rethrowErrors: rethrowErrors,
    );
  }

  String? _resolveTagSelector(String categoryKey) {
    switch (categoryKey.toLowerCase()) {
      case 'fuel':
      case 'gasolina':
      case 'gasolinera':
        return 'nwr["amenity"="fuel"]';
      case 'motorcycle_repair':
      case 'motorcycle':
        return 'nwr["shop"="motorcycle"]; nwr["amenity"="motorcycle_repair"]; nwr["shop"="motorcycle_repair"]';
      case 'tyres':
      case 'montallantas':
        return 'nwr["shop"="tyres"]; nwr["service"="tyres"]';
      case 'restaurant':
      case 'restaurante':
      case 'cafe':
        return 'nwr["amenity"="restaurant"]; nwr["amenity"="cafe"]';
      case 'viewpoint':
      case 'mirador':
      case 'attraction':
        return 'nwr["tourism"="viewpoint"]; nwr["tourism"="attraction"]';
      case 'mall':
      case 'shopping_mall':
        return 'nwr["shop"="mall"]';
      case 'hairdresser':
      case 'barber':
        return 'nwr["shop"="hairdresser"]; nwr["shop"="beauty"]';
      case 'place_of_worship':
        return 'nwr["amenity"="place_of_worship"]';
      default:
        return null;
    }
  }

  String _buildFallbackTitle(String categoryKey, Map<String, dynamic> tags) {
    final street = tags['addr:street']?.toString() ?? '';
    final streetPart = street.isNotEmpty ? ' ($street)' : '';

    switch (categoryKey.toLowerCase()) {
      case 'fuel':
      case 'gasolina':
      case 'gasolinera':
        return 'Estación de Servicio / Gasolinera$streetPart';
      case 'motorcycle_repair':
      case 'motorcycle':
        return 'Taller de Motocicletas$streetPart';
      case 'tyres':
      case 'montallantas':
        return 'Montallantas / Vulcanizadora$streetPart';
      case 'restaurant':
      case 'restaurante':
      case 'cafe':
        return 'Restaurante / Cafetería$streetPart';
      case 'viewpoint':
      case 'mirador':
      case 'attraction':
        return 'Mirador / Punto Panorámico$streetPart';
      case 'mall':
        return 'Centro Comercial$streetPart';
      case 'hairdresser':
      case 'barber':
        return 'Barbería / Peluquería$streetPart';
      case 'place_of_worship':
        final religion = tags['religion']?.toString() ?? 'Iglesia';
        return '$religion$streetPart';
      default:
        return 'Establecimiento Local';
    }
  }

  String _buildSubtitle(Map<String, dynamic> tags) {
    final street = tags['addr:street']?.toString();
    final housenumber = tags['addr:housenumber']?.toString();
    final city =
        tags['addr:city']?.toString() ?? tags['addr:municipality']?.toString();

    final parts = <String>[];
    if (street != null && street.isNotEmpty) {
      if (housenumber != null && housenumber.isNotEmpty) {
        parts.add('$street # $housenumber');
      } else {
        parts.add(street);
      }
    }
    if (city != null && city.isNotEmpty) {
      parts.add(city);
    }

    if (parts.isNotEmpty) {
      return parts.join(', ');
    }
    return 'Lugar cercano identificado en OpenStreetMap';
  }

  void clearCache() => _cache.clear();
}
