import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../../../../domain/entities/coordinates.dart';
import '../../domain/entities/destination.dart';
import '../../domain/services/geocoding_service.dart';

/// Implementación de [GeocodingService] utilizando la API pública de OpenStreetMap (Nominatim).
///
/// Cumple rigurosamente con la política de uso de Nominatim:
/// - Cabecera `User-Agent` descriptiva con identificación de aplicación.
/// - Límites razonables de resultados.
/// - Cliente HTTP inyectable para pruebas sin conexión a internet.
class NominatimGeocodingService implements GeocodingService {
  final http.Client _client;
  final String _userAgent;

  NominatimGeocodingService({
    http.Client? client,
    String userAgent =
        'REstelarNavigationApp/1.0 (contact: restelar@roadcompanion.app)',
  }) : _client = client ?? http.Client(),
       _userAgent = userAgent;

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

    final queryParams = {
      'q': cleanQuery,
      'format': 'jsonv2',
      'addressdetails': '1',
      'limit': limit.toString(),
      'accept-language': 'es',
    };

    if (proximityHint != null) {
      // Ponderar hacia el hemisferio/región del usuario (bounded=0 permite resultados globales sin descartar)
      queryParams['viewbox'] =
          '${proximityHint.longitude - 2.0},${proximityHint.latitude + 2.0},${proximityHint.longitude + 2.0},${proximityHint.latitude - 2.0}';
      queryParams['bounded'] = '0';
    }

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
      final results = <Destination>[];

      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;

        final latStr = item['lat'] as String?;
        final lonStr = item['lon'] as String?;
        if (latStr == null || lonStr == null) continue;

        final lat = double.tryParse(latStr);
        final lon = double.tryParse(lonStr);
        if (lat == null || lon == null) continue;

        final rawName = item['name'] as String? ?? '';
        final displayName = item['display_name'] as String? ?? '';

        final title = rawName.isNotEmpty
            ? rawName
            : displayName.split(',').first.trim();

        final subtitle = _buildSubtitle(item, displayName);

        final id =
            item['place_id']?.toString() ??
            '${lat.toStringAsFixed(4)}_${lon.toStringAsFixed(4)}';

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
    } on TimeoutException {
      throw const SocketException(
        'Tiempo de espera agotado al conectar con el servidor de búsqueda.',
      );
    }
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

  /// Construye un subtítulo legible destacando vía, municipio y departamento/región.
  String _buildSubtitle(Map<String, dynamic> item, String displayName) {
    final address = item['address'] as Map<String, dynamic>?;
    if (address != null) {
      final locality = address['city'] ??
          address['town'] ??
          address['village'] ??
          address['municipality'] ??
          address['county'] ??
          address['suburb'];
      final region =
          address['state'] ?? address['department'] ?? address['province'];
      final road =
          address['road'] ?? address['pedestrian'] ?? address['street'];

      final parts = <String>[];
      if (road != null && road.toString().trim().isNotEmpty) {
        parts.add(road.toString().trim());
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
