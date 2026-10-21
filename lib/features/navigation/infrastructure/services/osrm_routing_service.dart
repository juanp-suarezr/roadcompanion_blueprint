import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;

import '../../../../domain/entities/coordinates.dart';
import '../../../../domain/entities/maneuver.dart';
import '../../../../domain/entities/maneuver_type.dart';
import '../../../../domain/entities/route_plan.dart';
import '../../domain/entities/access_restriction.dart';
import '../../domain/entities/calculated_route.dart';
import '../../domain/entities/navigation_issue_report.dart';
import '../../domain/services/navigation_diagnostic_logger.dart';
import '../../domain/services/osm_access_service.dart';
import '../../domain/services/route_integrity_validator.dart';
import '../../domain/services/routing_service.dart';
import '../../domain/services/smart_navigation_memory_service.dart';

/// Excepción lanzada cuando el motor de enrutamiento no encuentra un camino viable.
class NoRouteFoundException implements Exception {
  final String message;
  const NoRouteFoundException([
    this.message = 'No se encontró una ruta vial entre los puntos indicados.',
  ]);

  @override
  String toString() => message;
}

/// Excepción lanzada cuando la geometría devuelta por el motor de rutas es vacía o inconsistente.
class InvalidRouteGeometryException extends NoRouteFoundException {
  const InvalidRouteGeometryException([
    super.message =
        'Ninguna de las rutas devueltas cuenta con geometría vial o trazado válido.',
  ]);
}

/// Implementación de [RoutingService] mediante el motor Open Source Routing Machine (OSRM).
///
/// Consulta el perfil de conducción y transforma la geometría GeoJSON y los pasos
/// en las entidades [RoutePlan] y [Maneuver] del dominio de REstelar.
/// Soporta cálculo de rutas principales y alternativas reales (`alternatives=3`),
/// e integra controles de integridad de trazado, seguridad vial y detección de accesos privados con cerrojos.
class OsrmRoutingService implements RoutingService {
  final http.Client _client;
  final String _baseUrl;
  final RoadAccessRestrictionRegistry _restrictionRegistry;
  final OsmAccessService _osmAccessService;
  final SmartNavigationMemoryService? _memoryService;

  OsrmRoutingService({
    http.Client? client,
    String baseUrl = 'https://router.project-osrm.org',
    RoadAccessRestrictionRegistry? restrictionRegistry,
    OsmAccessService? osmAccessService,
    SmartNavigationMemoryService? memoryService,
  })  : _client = client ?? http.Client(),
        _baseUrl = baseUrl,
        _restrictionRegistry =
            restrictionRegistry ?? RoadAccessRestrictionRegistry(),
        _osmAccessService = osmAccessService ?? OsmAccessService(client: client),
        _memoryService = memoryService;

  RoadAccessRestrictionRegistry get restrictionRegistry => _restrictionRegistry;
  OsmAccessService get osmAccessService => _osmAccessService;
  SmartNavigationMemoryService? get memoryService => _memoryService;

  @override
  Future<CalculatedRoute> calculateRoute({
    required Coordinates origin,
    required Coordinates destination,
  }) async {
    final routes = await calculateRoutesWithAlternatives(
      origin: origin,
      destination: destination,
    );
    return routes.first;
  }

  @override
  Future<List<CalculatedRoute>> calculateRoutesWithAlternatives({
    required Coordinates origin,
    required Coordinates destination,
  }) async {
    // Sincronizar restricciones y reportes confirmados de la memoria local
    if (_memoryService != null) {
      _memoryService.syncWithRestrictionRegistry(_restrictionRegistry);
    }

    final coordsSegment =
        '${origin.longitude.toStringAsFixed(6)},${origin.latitude.toStringAsFixed(6)};'
        '${destination.longitude.toStringAsFixed(6)},${destination.latitude.toStringAsFixed(6)}';

    // Solicita geometría completa, pasos de maniobra, nodos OSM y hasta 3 alternativas reales
    final uri = Uri.parse(
      '$_baseUrl/route/v1/driving/$coordsSegment?overview=full&geometries=geojson&steps=true&annotations=nodes,distance&alternatives=3',
    );

    try {
      final response = await _client.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'REstelarNavigationApp/1.0 (motorcycle route companion)',
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

      final rawRoutes = data['routes'] as List<dynamic>?;
      if (rawRoutes == null || rawRoutes.isEmpty) {
        throw const NoRouteFoundException();
      }

      // Procesar y validar cada ruta devuelta por el proveedor
      final parsedRoutes = <CalculatedRoute>[];
      final discardReasons = <String>[];

      for (int i = 0; i < rawRoutes.length; i++) {
        final routeMap = rawRoutes[i];
        if (routeMap is! Map<String, dynamic>) {
          discardReasons.add('Ruta ${i + 1} descartada: formato JSON no reconocido');
          continue;
        }

        // Extraer todos los nodos OSM de las anotaciones de cada pierna (leg)
        final annotationNodes = <int>[];
        final legs = routeMap['legs'] as List<dynamic>?;
        if (legs != null) {
          for (final leg in legs) {
            if (leg is! Map<String, dynamic>) continue;
            final nodes = leg['annotation']?['nodes'] as List<dynamic>?;
            if (nodes != null) {
              for (final n in nodes) {
                if (n is num) annotationNodes.add(n.toInt());
              }
            }
          }
        }

        final parsed = _parseSingleRoute(
          routeMap,
          origin: origin,
          destination: destination,
          index: i,
          annotationNodes: annotationNodes,
        );

        if (parsed != null) {
          var activeRoute = parsed;
          // Evaluar si la ruta atraviesa zonas con reportes locales no confirmados (generar advertencia preventiva)
          if (_memoryService != null) {
            final nearbyReports =
                _memoryService.checkReportsAlongRoute(activeRoute.geometry);
            for (final rep in nearbyReports) {
              if (rep.status != ReportVerificationStatus.confirmed) {
                final caution =
                    'Aviso local (${rep.typeLabel}): ${rep.description}';
                if (!activeRoute.validation.warnings.contains(caution)) {
                  final newWarnings =
                      List<String>.from(activeRoute.validation.warnings)..add(caution);
                  activeRoute = activeRoute.copyWith(
                    validation: activeRoute.validation.copyWith(
                      warnings: newWarnings,
                    ),
                  );
                }
              }
            }
          }

          parsedRoutes.add(activeRoute);
          if (!activeRoute.isPubliclyPassable) {
            final warningsSummary = activeRoute.validation.warnings.isNotEmpty
                ? activeRoute.validation.warnings.join('; ')
                : 'Paso por vía restringida o cerrojo';
            discardReasons.add(
              'Ruta ${i + 1} ("${activeRoute.summary}") relegada tras alternativas públicas ($warningsSummary)',
            );
          }
        } else {
          discardReasons.add(
            'Ruta ${i + 1} descartada: geometría vial inválida, corrupta o desconectada (< 2 puntos)',
          );
        }
      }

      if (parsedRoutes.isEmpty) {
        NavigationDiagnosticLogger.logRoutingDiagnostics(
          origin: origin,
          destination: destination,
          requestUri: uri.toString(),
          rawRoutesCount: rawRoutes.length,
          validatedRoutesCount: 0,
          validatedRoutes: const [],
          discardReasons: discardReasons,
        );
        throw const InvalidRouteGeometryException();
      }

      Coordinates? problemCoordinate;
      String? problemSegmentAndEvidence;
      String? publicAlternativeSelected;

      // Si ninguna de las rutas devueltas por OSRM es de libre tránsito público (o solo se devolvió una con restricción confirmada)
      final hasPublicRoute = parsedRoutes.any((r) => r.isPubliclyPassable);
      if (!hasPublicRoute && parsedRoutes.isNotEmpty) {
        final primaryRestricted = parsedRoutes.first;
        final detected = primaryRestricted.validation.detectedRestriction;

        if (detected != null) {
          problemCoordinate = detected.location;
          problemSegmentAndEvidence =
              '${detected.description} [${detected.sourceEvidence}]';
        } else {
          final warnings = primaryRestricted.validation.warnings;
          problemSegmentAndEvidence = warnings.isNotEmpty
              ? warnings.first
              : 'Paso por vía restringida o portón privado';
          if (primaryRestricted.geometry.isNotEmpty) {
            problemCoordinate = primaryRestricted.geometry.last;
          }
        }

        // Intentar calcular una ruta alternativa pública que desvíe el paso restringido
        final publicRoute = await _attemptComputePublicAlternative(
          origin: origin,
          destination: destination,
          restrictedRoute: primaryRestricted,
          discardReasons: discardReasons,
        );

        if (publicRoute != null && publicRoute.isPubliclyPassable) {
          parsedRoutes.insert(0, publicRoute);
          publicAlternativeSelected =
              '${publicRoute.summary} (${publicRoute.totalDistanceKm.toStringAsFixed(2)} km, ${publicRoute.formattedDuration})';
          discardReasons.add(
            'Ruta original relegada por acceso privado cerrado. Se seleccionó y promovió alternativa 100% pública.',
          );
        }
      }

      // Priorizar rutas públicas transitables sobre aquellas con restricción confirmada:
      // Si existen alternativas de libre tránsito, deben encabezar la selección,
      // evitando que un atajo privado con cerrojo se recomiende por el solo hecho de ser más corto.
      final sortedRoutes = List<CalculatedRoute>.from(parsedRoutes)
        ..sort((a, b) {
          if (a.isPubliclyPassable && !b.isPubliclyPassable) return -1;
          if (!a.isPubliclyPassable && b.isPubliclyPassable) return 1;
          return 0;
        });

      final List<CalculatedRoute> returnRoutes;

      // Si hay múltiples rutas, calcular diferencias relativas y etiquetas
      if (sortedRoutes.length > 1) {
        // Buscar el mínimo entre las rutas transitables para no premiar atajos privados prohibidos
        final publicRoutes =
            sortedRoutes.where((r) => r.isPubliclyPassable).toList();
        final candidatePool =
            publicRoutes.isNotEmpty ? publicRoutes : sortedRoutes;

        Duration minDuration = candidatePool.first.estimatedDuration;
        double minDistance = candidatePool.first.totalDistanceKm;

        for (final r in candidatePool) {
          if (r.estimatedDuration < minDuration) {
            minDuration = r.estimatedDuration;
          }
          if (r.totalDistanceKm < minDistance) {
            minDistance = r.totalDistanceKm;
          }
        }

        // Identificar ruta preferida y equilibrada entre las opciones públicas:
        // Preferida: Ruta pública transitable con menor cantidad de advertencias/reportes viales
        CalculatedRoute? preferredCandidate;
        int minWarnings = 999;
        for (final r in candidatePool) {
          final wCount = r.validation.warnings.length;
          if (wCount < minWarnings) {
            minWarnings = wCount;
            preferredCandidate = r;
          }
        }

        // Equilibrada: Si hay alternativas públicas, la opción que equilibra tiempo y distancia sin ser rodeo extremo
        CalculatedRoute? balancedCandidate;
        if (candidatePool.length >= 3) {
          balancedCandidate = candidatePool[1];
        } else if (candidatePool.length == 2) {
          final second = candidatePool[1];
          if (second.estimatedDuration.inSeconds <=
              (minDuration.inSeconds * 1.35).round()) {
            balancedCandidate = second;
          }
        }

        final enrichedRoutes = <CalculatedRoute>[];
        for (int i = 0; i < sortedRoutes.length; i++) {
          final r = sortedRoutes[i];
          final assignedName = 'Ruta ${i + 1}';
          final isFastest =
              r.isPubliclyPassable && r.estimatedDuration == minDuration;
          final isShortest = r.isPubliclyPassable &&
              (r.totalDistanceKm - minDistance).abs() < 0.05;
          final isPreferred = r.isPubliclyPassable && r == preferredCandidate;
          final isBalanced =
              r.isPubliclyPassable && r == balancedCandidate && !isFastest;

          final distDiff = r.totalDistanceKm - minDistance;
          final durDiff = r.estimatedDuration - minDuration;

          enrichedRoutes.add(
            r.copyWith(
              routeName: assignedName,
              isFastest: isFastest,
              isShortest: isShortest,
              isBalanced: isBalanced,
              isPreferred: isPreferred,
              distanceDiffKm: distDiff > 0.05 ? distDiff : null,
              durationDiff:
                  durDiff > const Duration(seconds: 30) ? durDiff : null,
            ),
          );
        }

        // Asociar alternativas hermanas a cada ruta
        final finalizedRoutes = <CalculatedRoute>[];
        for (int i = 0; i < enrichedRoutes.length; i++) {
          final current = enrichedRoutes[i];
          final siblings =
              enrichedRoutes.where((e) => e != current).toList();
          finalizedRoutes.add(current.copyWith(alternatives: siblings));
        }

        returnRoutes = finalizedRoutes;
      } else {
        returnRoutes = sortedRoutes;
      }

      final finalResultStr = returnRoutes.isNotEmpty
          ? '${returnRoutes.first.routeName} ("${returnRoutes.first.summary}", ${returnRoutes.first.totalDistanceKm.toStringAsFixed(2)} km, ${returnRoutes.first.formattedDuration}, Pública=${returnRoutes.first.isPubliclyPassable})'
          : 'Ninguna';

      NavigationDiagnosticLogger.logRoutingDiagnostics(
        origin: origin,
        destination: destination,
        requestUri: uri.toString(),
        rawRoutesCount: rawRoutes.length,
        validatedRoutesCount: returnRoutes.length,
        validatedRoutes: returnRoutes,
        discardReasons: discardReasons,
        problemCoordinateDetected: problemCoordinate,
        restrictionSegmentAndEvidence: problemSegmentAndEvidence,
        publicAlternativeSelected: publicAlternativeSelected,
        finalResultPresented: finalResultStr,
      );

      return returnRoutes;
    } on TimeoutException {
      throw const SocketException(
        'Tiempo de espera agotado al calcular la ruta.',
      );
    }
  }

  /// Calcula una ruta alternativa que desvía una restricción de acceso vehicular confirmada.
  ///
  /// Proyecta un punto de paso seguro (bypass) continuando la marcha a lo largo del corredor
  /// arterial público previo al giro cerrado, obligando a OSRM a utilizar los accesos y retornos
  /// oficiales y públicos hacia el destino.
  Future<CalculatedRoute?> _attemptComputePublicAlternative({
    required Coordinates origin,
    required Coordinates destination,
    required CalculatedRoute restrictedRoute,
    required List<String> discardReasons,
  }) async {
    final restrictionLoc =
        restrictedRoute.validation.detectedRestriction?.location;
    if (restrictionLoc == null) {
      return null;
    }

    // Localizar el punto de la geometría de la ruta más próximo al portón/restricción
    final coords = restrictedRoute.geometry;
    int closestIndex = 0;
    double minDistance = double.infinity;
    for (int i = 0; i < coords.length; i++) {
      final d = coords[i].distanceTo(restrictionLoc);
      if (d < minDistance) {
        minDistance = d;
        closestIndex = i;
      }
    }

    // Calcular el rumbo de aproximación de la calzada pública antes del giro prohibido
    final approachIndex = max(0, closestIndex - 3);
    final approachBearing =
        coords[approachIndex].bearingTo(coords[closestIndex]);

    // Distancias de proyección hacia adelante a lo largo del corredor arterial público
    final bypassDistances = [250.0, 350.0, 180.0, 450.0];

    for (final dist in bypassDistances) {
      final bypassPoint =
          coords[closestIndex].project(approachBearing, dist);

      final bypassSegment =
          '${origin.longitude.toStringAsFixed(6)},${origin.latitude.toStringAsFixed(6)};'
          '${bypassPoint.longitude.toStringAsFixed(6)},${bypassPoint.latitude.toStringAsFixed(6)};'
          '${destination.longitude.toStringAsFixed(6)},${destination.latitude.toStringAsFixed(6)}';

      final uri = Uri.parse(
        '$_baseUrl/route/v1/driving/$bypassSegment?overview=full&geometries=geojson&steps=true&annotations=nodes,distance',
      );

      try {
        final response = await _client.get(
          uri,
          headers: {
            'Accept': 'application/json',
            'User-Agent': 'REstelarNavigationApp/1.0 (motorcycle route companion)',
          },
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode != 200) continue;

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['code'] != 'Ok') continue;

        final routes = data['routes'] as List<dynamic>?;
        if (routes == null || routes.isEmpty) continue;

        final routeMap = routes.first as Map<String, dynamic>;
        final annotationNodes = <int>[];
        final legs = routeMap['legs'] as List<dynamic>?;
        if (legs != null) {
          for (final leg in legs) {
            if (leg is! Map<String, dynamic>) continue;
            final nodes = leg['annotation']?['nodes'] as List<dynamic>?;
            if (nodes != null) {
              for (final n in nodes) {
                if (n is num) annotationNodes.add(n.toInt());
              }
            }
          }
        }

        final candidate = _parseSingleRoute(
          routeMap,
          origin: origin,
          destination: destination,
          index: 0,
          annotationNodes: annotationNodes,
          overrideRouteName: 'Ruta 1',
        );

        if (candidate != null && candidate.isPubliclyPassable) {
          // Confirmada como pública y sin cruce por el portón
          return candidate;
        } else {
          discardReasons.add(
            'Candidato de desvío a +${dist.round()}m descartado: aún intersecta restricciones',
          );
        }
      } catch (_) {
        continue;
      }
    }

    return null;
  }

  CalculatedRoute? _parseSingleRoute(
    Map<String, dynamic> routeMap, {
    required Coordinates origin,
    required Coordinates destination,
    required int index,
    List<int>? annotationNodes,
    String? overrideRouteName,
  }) {
    final distanceMeters = (routeMap['distance'] as num?)?.toDouble() ?? 0.0;
    final durationSeconds = (routeMap['duration'] as num?)?.toDouble() ?? 0.0;

    // 1. Extraer geometría GeoJSON [lon, lat] -> Coordinates(lat, lon)
    final geometryMap = routeMap['geometry'] as Map<String, dynamic>?;
    final rawCoords = geometryMap?['coordinates'] as List<dynamic>?;

    final geometry = <Coordinates>[];
    if (rawCoords != null) {
      for (final pair in rawCoords) {
        if (pair is List && pair.length >= 2) {
          final lonNum = pair[0] as num?;
          final latNum = pair[1] as num?;
          if (lonNum == null || latNum == null) continue;

          final lon = lonNum.toDouble();
          final lat = latNum.toDouble();
          if (lat.isFinite && lon.isFinite) {
            geometry.add(Coordinates(lat, lon));
          }
        }
      }
    }

    // 2. Extraer pasos y maniobras de todas las piernas (legs)
    final maneuvers = <Maneuver>[];
    final rawStepsList = <Map<String, dynamic>>[];
    final legs = routeMap['legs'] as List<dynamic>?;
    final summaryParts = <String>{};

    if (legs != null && legs.isNotEmpty) {
      for (int l = 0; l < legs.length; l++) {
        final leg = legs[l];
        if (leg is! Map<String, dynamic>) continue;
        final legSummary = leg['summary'] as String? ?? '';
        if (legSummary.isNotEmpty) {
          summaryParts.add(legSummary);
        }
        final steps = leg['steps'] as List<dynamic>?;
        if (steps != null) {
          for (int s = 0; s < steps.length; s++) {
            final step = steps[s];
            if (step is! Map<String, dynamic>) continue;
            rawStepsList.add(step);

            // Omitir llegada intermedia entre piernas para no interrumpir el flujo del viaje
            final isIntermediateArrival =
                l < legs.length - 1 && s == steps.length - 1;
            if (isIntermediateArrival) {
              continue;
            }

            final maneuver = _parseStep(step, fallbackLocation: destination);
            if (maneuver != null) {
              maneuvers.add(maneuver);
            }
          }
        }
      }
    }

    // Validar integridad, conectividad y restricciones de acceso con RouteIntegrityValidator
    final validation = RouteIntegrityValidator.validate(
      geometry: geometry,
      origin: origin,
      destination: destination,
      rawSteps: rawStepsList,
      annotationNodes: annotationNodes,
      restrictionRegistry: _restrictionRegistry,
    );

    // Si la ruta es inválida (menos de 2 puntos, corrupta), se descarta
    if (!validation.isValid) {
      return null;
    }

    // Si no hay maniobras devueltas, crear salida y llegada mínimas
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

    final routeName = overrideRouteName ?? 'Ruta ${index + 1}';
    final fallbackSummary = index == 0 ? 'Vía Principal' : 'Alternativa $index';
    final summary = summaryParts.isNotEmpty
        ? summaryParts.join(' / ')
        : fallbackSummary;

    return CalculatedRoute(
      routePlan: routePlan,
      summary: summary,
      routeName: routeName,
      validation: validation,
    );
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

    final coordsList = stepManeuver['location'] as List<dynamic>?;
    Coordinates maneuverLocation = fallbackLocation;
    if (coordsList != null && coordsList.length >= 2) {
      final lon = (coordsList[0] as num).toDouble();
      final lat = (coordsList[1] as num).toDouble();
      if (lat.isFinite && lon.isFinite) {
        maneuverLocation = Coordinates(lat, lon);
      }
    }

    final type = _mapManeuverType(typeStr, modifierStr);
    final instruction = _buildInstructionText(
      type: type,
      modifier: modifierStr,
      roadName: roadName,
    );

    return Maneuver(
      instructionText: instruction,
      type: type,
      location: maneuverLocation,
      distanceMeters: distanceMeters,
      roadName: roadName?.isNotEmpty == true ? roadName : null,
    );
  }

  ManeuverType _mapManeuverType(String type, String modifier) {
    switch (type) {
      case 'depart':
        return ManeuverType.depart;
      case 'arrive':
        return ManeuverType.arrive;
      case 'turn':
        if (modifier.contains('left')) {
          if (modifier == 'sharp left') return ManeuverType.sharpLeft;
          if (modifier == 'slight left') return ManeuverType.slightLeft;
          return ManeuverType.left;
        } else if (modifier.contains('right')) {
          if (modifier == 'sharp right') return ManeuverType.sharpRight;
          if (modifier == 'slight right') return ManeuverType.slightRight;
          return ManeuverType.right;
        } else if (modifier == 'uturn') {
          return ManeuverType.uTurn;
        }
        return ManeuverType.straight;
      case 'new name':
      case 'continue':
        return ManeuverType.straight;
      case 'roundabout':
      case 'rotary':
        return ManeuverType.roundabout;
      case 'on ramp':
      case 'off ramp':
      case 'fork':
        if (modifier.contains('left')) return ManeuverType.slightLeft;
        if (modifier.contains('right')) return ManeuverType.slightRight;
        return ManeuverType.straight;
      default:
        return ManeuverType.straight;
    }
  }

  String _buildInstructionText({
    required ManeuverType type,
    required String modifier,
    String? roadName,
  }) {
    final roadPart =
        (roadName != null && roadName.isNotEmpty) ? ' hacia $roadName' : '';

    switch (type) {
      case ManeuverType.depart:
        return 'Inicia la ruta$roadPart';
      case ManeuverType.arrive:
        return 'Has llegado a tu destino';
      case ManeuverType.left:
        return 'Gira a la izquierda$roadPart';
      case ManeuverType.right:
        return 'Gira a la derecha$roadPart';
      case ManeuverType.sharpLeft:
        return 'Giro pronunciado a la izquierda$roadPart';
      case ManeuverType.sharpRight:
        return 'Giro pronunciado a la derecha$roadPart';
      case ManeuverType.slightLeft:
        return 'Mantente a la izquierda$roadPart';
      case ManeuverType.slightRight:
        return 'Mantente a la derecha$roadPart';
      case ManeuverType.straight:
        return 'Continúa recto$roadPart';
      case ManeuverType.roundabout:
        return 'En la rotonda, continúa$roadPart';
      case ManeuverType.uTurn:
        return 'Realiza un giro en U$roadPart';
      case ManeuverType.unknown:
        return 'Continúa la marcha$roadPart';
    }
  }
}
