import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../../../domain/entities/coordinates.dart';

/// Resultado de la verificación de acceso cartográfico de un tramo vial.
class RoadSegmentAccessResult {
  final bool isConfirmedPrivate;
  final bool isUnconfirmed;
  final bool isConfirmedPublic;
  final String description;
  final String evidence;
  final Coordinates? barrierLocation;

  const RoadSegmentAccessResult({
    required this.isConfirmedPrivate,
    required this.isUnconfirmed,
    required this.isConfirmedPublic,
    required this.description,
    required this.evidence,
    this.barrierLocation,
  });

  static const publicDefault = RoadSegmentAccessResult(
    isConfirmedPrivate: false,
    isUnconfirmed: false,
    isConfirmedPublic: true,
    description: 'Vía de libre tránsito público',
    evidence: 'Cartografía pública OSM',
  );
}

/// Servicio para verificar accesos, portones y restricciones en datos viales de OpenStreetMap.
///
/// Incorpora caché en memoria para respetar políticas y límites de uso del proveedor,
/// evitando consultas indiscriminadas o repetitivas.
class OsmAccessService {
  final http.Client _client;
  final Map<String, RoadSegmentAccessResult> _cache = {};

  OsmAccessService({http.Client? client}) : _client = client ?? http.Client();

  /// Verifica si una coordenada o segmento sospechoso (ej. giro sin nombre hacia service)
  /// contiene una barrera física (portón/cerrojo) o restricción de acceso en OSM.
  Future<RoadSegmentAccessResult> verifySegmentAccess(
    Coordinates location,
  ) async {
    // Clave de caché redondeada a ~50 metros
    final cacheKey =
        '${location.latitude.toStringAsFixed(3)}_${location.longitude.toStringAsFixed(3)}';

    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    final delta = 0.001; // ~110 metros
    final bbox =
        '${location.longitude - delta},${location.latitude - delta},${location.longitude + delta},${location.latitude + delta}';
    final uri = Uri.parse(
      'https://api.openstreetmap.org/api/0.6/map.json?bbox=$bbox',
    );

    try {
      final response = await _client
          .get(
            uri,
            headers: {
              'User-Agent':
                  'REstelarNavigationApp/1.0 (access restriction auditor; contact: restelar@roadcompanion.app)',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode != 200) {
        // En caso de error o límite de tasa, indicar incertidumbre sin inventar
        final unconfirmed = RoadSegmentAccessResult(
          isConfirmedPrivate: false,
          isUnconfirmed: true,
          isConfirmedPublic: false,
          description: 'Información de acceso no verificable en este momento',
          evidence:
              'Servidor cartográfico no disponible (HTTP ${response.statusCode})',
        );
        _cache[cacheKey] = unconfirmed;
        return unconfirmed;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final elements = data['elements'] as List<dynamic>? ?? [];

      bool hasGate = false;
      Coordinates? gateCoord;
      String gateDesc = '';

      // Inspeccionar nodos de barrera
      for (final el in elements) {
        if (el is! Map<String, dynamic>) continue;
        final tags = el['tags'] as Map<String, dynamic>?;
        if (tags == null) continue;

        if (el['type'] == 'node') {
          final barrier = tags['barrier']?.toString().toLowerCase();
          final access = tags['access']?.toString().toLowerCase();

          if (barrier == 'gate' ||
              barrier == 'lift_gate' ||
              barrier == 'bollard' ||
              barrier == 'chain' ||
              access == 'private' ||
              access == 'no') {
            final lat = (el['lat'] as num?)?.toDouble();
            final lon = (el['lon'] as num?)?.toDouble();
            if (lat != null && lon != null) {
              final dist = location.distanceTo(Coordinates(lat, lon));
              if (dist <= 60.0) {
                hasGate = true;
                gateCoord = Coordinates(lat, lon);
                gateDesc =
                    'barrier=$barrier (portón o barrera física detectada en nodo ${el['id']})';
                break;
              }
            }
          }
        }
      }

      // Si no se encontró nodo barrera, inspeccionar vías
      if (!hasGate) {
        for (final el in elements) {
          if (el is! Map<String, dynamic>) continue;
          if (el['type'] == 'way') {
            final tags = el['tags'] as Map<String, dynamic>?;
            if (tags == null) continue;
            final access = tags['access']?.toString().toLowerCase();
            final highway = tags['highway']?.toString().toLowerCase();

            if (access == 'private' || access == 'no') {
              hasGate = true;
              gateDesc =
                  'Vía clasificada como privada (access=$access en vía ${el['id']})';
              break;
            } else if (highway == 'service' && access == null) {
              // Vía de servicio sin etiqueta de acceso explícita: no es confirmada privada, es incierta
              final result = RoadSegmentAccessResult(
                isConfirmedPrivate: false,
                isUnconfirmed: true,
                isConfirmedPublic: false,
                description:
                    'Vía de servicio con acceso no confirmado en la cartografía',
                evidence:
                    'OSM way ${el['id']} (highway=service sin tag access)',
              );
              _cache[cacheKey] = result;
              return result;
            }
          }
        }
      }

      final result = hasGate
          ? RoadSegmentAccessResult(
              isConfirmedPrivate: true,
              isUnconfirmed: false,
              isConfirmedPublic: false,
              description: gateDesc,
              evidence: 'Cartografía oficial OpenStreetMap',
              barrierLocation: gateCoord,
            )
          : RoadSegmentAccessResult.publicDefault;

      _cache[cacheKey] = result;
      return result;
    } catch (_) {
      // Manejo defensivo ante fallos de conexión: mantener estado de incertidumbre
      return const RoadSegmentAccessResult(
        isConfirmedPrivate: false,
        isUnconfirmed: true,
        isConfirmedPublic: false,
        description: 'Información de acceso no confirmada por conectividad',
        evidence: 'Excepción de red al verificar segmento',
      );
    }
  }

  void clearCache() => _cache.clear();
}
