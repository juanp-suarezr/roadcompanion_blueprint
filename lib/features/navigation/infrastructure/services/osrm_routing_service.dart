import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../../../../domain/entities/coordinates.dart';
import '../../../../domain/entities/maneuver.dart';
import '../../../../domain/entities/maneuver_type.dart';
import '../../../../domain/entities/route_plan.dart';
import '../../domain/entities/calculated_route.dart';
import '../../domain/services/routing_service.dart';

/// Excepción lanzada cuando el motor de enrutamiento no encuentra un camino viable.
class NoRouteFoundException implements Exception {
  final String message;
  const NoRouteFoundException([
    this.message =
        'No se encontró una ruta vial entre los puntos indicados.',
  ]);

  @override
  String toString() => message;
}

/// Implementación de [RoutingService] mediante el motor Open Source Routing Machine (OSRM).
///
/// Consulta el perfil de conducción y transforma la geometría GeoJSON y los pasos
/// en las entidades [RoutePlan] y [Maneuver] del dominio de ESTELA.
class OsrmRoutingService implements RoutingService {
  final http.Client _client;
  final String _baseUrl;

  OsrmRoutingService({
    http.Client? client,
    String baseUrl = 'https://router.project-osrm.org',
  })  : _client = client ?? http.Client(),
        _baseUrl = baseUrl;

  @override
  Future<CalculatedRoute> calculateRoute({
    required Coordinates origin,
    required Coordinates destination,
  }) async {
    final coordsSegment =
        '${origin.longitude.toStringAsFixed(6)},${origin.latitude.toStringAsFixed(6)};'
        '${destination.longitude.toStringAsFixed(6)},${destination.latitude.toStringAsFixed(6)}';

    final uri = Uri.parse(
      '$_baseUrl/route/v1/driving/$coordsSegment?overview=full&geometries=geojson&steps=true',
    );

    try {
      final response = await _client.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'EstelaNavigationApp/1.0 (motorcycle route companion)',
        },
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        throw HttpException(
          'Error del motor de rutas (HTTP ${response.statusCode})',
          uri: uri,
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final code = data['code'] as String?;

      if (code != 'Ok') {
        final message = data['message'] as String? ?? 'Ruta no disponible';
        throw NoRouteFoundException('El motor OSRM reportó: $message');
      }

      final routes = data['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) {
        throw const NoRouteFoundException();
      }

      final firstRoute = routes.first as Map<String, dynamic>;
      final distanceMeters =
          (firstRoute['distance'] as num?)?.toDouble() ?? 0.0;
      final durationSeconds =
          (firstRoute['duration'] as num?)?.toDouble() ?? 0.0;

      // 1. Extraer geometría GeoJSON [lon, lat] -> Coordinates(lat, lon)
      final geometryMap = firstRoute['geometry'] as Map<String, dynamic>?;
      final rawCoords = geometryMap?['coordinates'] as List<dynamic>?;

      final geometry = <Coordinates>[];
      if (rawCoords != null) {
        for (final pair in rawCoords) {
          if (pair is List && pair.length >= 2) {
            final lon = (pair[0] as num).toDouble();
            final lat = (pair[1] as num).toDouble();
            geometry.add(Coordinates(lat, lon));
          }
        }
      }

      // Asegurar al menos 2 puntos válidos
      if (geometry.length < 2) {
        geometry.clear();
        geometry.add(origin);
        geometry.add(destination);
      }

      // 2. Extraer maniobras de los pasos (steps)
      final maneuvers = <Maneuver>[];
      final legs = firstRoute['legs'] as List<dynamic>?;
      String summary = '';

      if (legs != null && legs.isNotEmpty) {
        final firstLeg = legs.first as Map<String, dynamic>;
        summary = firstLeg['summary'] as String? ?? '';
        final steps = firstLeg['steps'] as List<dynamic>?;

        if (steps != null) {
          for (final step in steps) {
            if (step is! Map<String, dynamic>) continue;
            final maneuver = _parseStep(step, fallbackLocation: destination);
            if (maneuver != null) {
              maneuvers.add(maneuver);
            }
          }
        }
      }

      // Si no hay maniobras devueltas, crear salida y llegada mínimas válidas
      if (maneuvers.isEmpty) {
        maneuvers.add(
          Maneuver(
            instructionText: 'Inicia el recorrido hacia el destino',
            type: ManeuverType.depart,
            location: origin,
            distanceMeters: distanceMeters,
          ),
        );
        maneuvers.add(
          Maneuver(
            instructionText: 'Llegada al destino',
            type: ManeuverType.arrive,
            location: destination,
            distanceMeters: 0.0,
          ),
        );
      }

      final routePlan = RoutePlan(
        origin: origin,
        destination: destination,
        geometry: geometry,
        totalDistanceMeters: distanceMeters,
        estimatedDuration: Duration(seconds: durationSeconds.round()),
        maneuvers: maneuvers,
      );

      return CalculatedRoute(
        routePlan: routePlan,
        summary: summary.isNotEmpty ? summary : 'Ruta por calzada principal',
      );
    } on TimeoutException {
      throw const SocketException(
        'Tiempo de espera agotado al calcular la ruta.',
      );
    }
  }

  Maneuver? _parseStep(
    Map<String, dynamic> step, {
    required Coordinates fallbackLocation,
  }) {
    final stepManeuver = step['maneuver'] as Map<String, dynamic>?;
    if (stepManeuver == null) return null;

    final typeStr = stepManeuver['type'] as String? ?? '';
    final modifierStr = stepManeuver['modifier'] as String? ?? '';
    final roadName = step['name'] as String?;
    final distanceMeters = (step['distance'] as num?)?.toDouble() ?? 0.0;

    Coordinates stepLoc = fallbackLocation;
    final locList = stepManeuver['location'] as List<dynamic>?;
    if (locList != null && locList.length >= 2) {
      final lon = (locList[0] as num).toDouble();
      final lat = (locList[1] as num).toDouble();
      stepLoc = Coordinates(lat, lon);
    }

    final maneuverType = _mapManeuverType(typeStr, modifierStr);
    final instruction = _buildSpanishInstruction(maneuverType, roadName);

    return Maneuver(
      instructionText: instruction,
      type: maneuverType,
      location: stepLoc,
      roadName: (roadName != null && roadName.trim().isNotEmpty)
          ? roadName.trim()
          : null,
      distanceMeters: distanceMeters,
    );
  }

  ManeuverType _mapManeuverType(String type, String modifier) {
    switch (type) {
      case 'depart':
        return ManeuverType.depart;
      case 'arrive':
        return ManeuverType.arrive;
      case 'fork':
        return modifier.contains('left')
            ? ManeuverType.slightLeft
            : ManeuverType.slightRight;
      case 'merge':
        return ManeuverType.straight;
      case 'roundabout':
      case 'rotary':
        return ManeuverType.roundabout;
      case 'turn':
        if (modifier == 'left') return ManeuverType.left;
        if (modifier == 'right') return ManeuverType.right;
        if (modifier == 'slight left') return ManeuverType.slightLeft;
        if (modifier == 'slight right') return ManeuverType.slightRight;
        if (modifier == 'sharp left') return ManeuverType.sharpLeft;
        if (modifier == 'sharp right') return ManeuverType.sharpRight;
        if (modifier == 'uturn') return ManeuverType.uTurn;
        return ManeuverType.left;
      case 'continue':
      case 'new name':
      default:
        return ManeuverType.straight;
    }
  }

  String _buildSpanishInstruction(ManeuverType type, String? roadName) {
    final onRoad = (roadName != null && roadName.trim().isNotEmpty)
        ? ' hacia ${roadName.trim()}'
        : '';

    switch (type) {
      case ManeuverType.depart:
        return 'Inicia la ruta$onRoad';
      case ManeuverType.left:
        return 'Gira a la izquierda$onRoad';
      case ManeuverType.right:
        return 'Gira a la derecha$onRoad';
      case ManeuverType.slightLeft:
        return 'Gira levemente a la izquierda$onRoad';
      case ManeuverType.slightRight:
        return 'Gira levemente a la derecha$onRoad';
      case ManeuverType.sharpLeft:
        return 'Giro pronunciado a la izquierda$onRoad';
      case ManeuverType.sharpRight:
        return 'Giro pronunciado a la derecha$onRoad';
      case ManeuverType.uTurn:
        return 'Haz un giro en U';
      case ManeuverType.straight:
        return 'Continúa recto$onRoad';
      case ManeuverType.roundabout:
        return 'Entra a la rotonda$onRoad';
      case ManeuverType.arrive:
        return 'Has llegado a tu destino';
      case ManeuverType.unknown:
        return 'Sigue la ruta$onRoad';
    }
  }
}
