import 'dart:math' as math;

import '../../../../domain/entities/coordinates.dart';
import '../../../../domain/entities/maneuver.dart';
import '../../../../domain/entities/maneuver_type.dart';
import '../entities/road_curvature.dart';

/// Segmento vial consolidado tras filtrado de coordenadas duplicadas y micro-segmentos.
class _ConsolidatedSegment {
  final Coordinates start;
  final Coordinates end;
  final double startDistanceMeters;
  final double endDistanceMeters;
  final double lengthMeters;
  final double bearingDegrees;

  const _ConsolidatedSegment({
    required this.start,
    required this.end,
    required this.startDistanceMeters,
    required this.endDistanceMeters,
    required this.lengthMeters,
    required this.bearingDegrees,
  });
}

/// Arco de curva individual detectado dentro de la ventana de anticipación.
class _DetectedCurveArc {
  final double startDistanceMeters;
  final double endDistanceMeters;
  final double arcLengthMeters;
  final double cumulativeAngleDegrees;
  final int vertexCount;

  const _DetectedCurveArc({
    required this.startDistanceMeters,
    required this.endDistanceMeters,
    required this.arcLengthMeters,
    required this.cumulativeAngleDegrees,
    required this.vertexCount,
  });

  CurveDirection get direction =>
      cumulativeAngleDegrees >= 0 ? CurveDirection.right : CurveDirection.left;

  double? get estimatedRadiusMeters {
    final absDeg = cumulativeAngleDegrees.abs();
    if (arcLengthMeters < 15.0 || absDeg < 12.0) return null;
    final radians = absDeg * math.pi / 180.0;
    if (radians <= 1e-4) return null;
    return arcLengthMeters / radians;
  }
}

/// Estimador geométrico de curvatura vial basado en polilíneas reales.
///
/// Principios de diseño (Prioridad B):
/// 1. **Separación estricta entre maniobra y curvatura**: No convierte giros discretos
///    de navegación (`left`, `right`, `roundabout`, `uTurn`) en curvas de carretera,
///    y excluye los vértices de intersección o retorno conocidos para evitar falsos positivos.
/// 2. **Consolidación espacial**: Elimina coordenadas duplicadas y fusiona micro-segmentos
///    ruidosos (`< minSegmentLengthMeters`) antes de calcular rumbos.
/// 3. **Rechazo de ruido GPS / digitalización**: Evalúa la desviación transversal máxima
///    respecto a la cuerda del tramo para no clasificar zig-zags submétricos como curvas.
/// 4. **Clasificación conjunta ángulo + longitud/radio**: Una curva amplia con gran cambio
///    de rumbo acumulado sobre una distancia larga ($R > 110\text{ m}$) no se clasifica
///    erróneamente como curva cerrada.
/// 5. **Detección de curvas consecutivas y tramos sinuosos**: Reconoce sucesiones de
///    curvas y tramos sinuosos alternados en la ventana de anticipación.
class RoadCurvatureEstimator {
  /// Longitud mínima de segmento para evitar ruido por cuantización de coordenadas.
  static const double minSegmentLengthMeters = 2.5;

  /// Umbral mínimo de deflexión acumulada para considerar una curva suave (grados).
  static const double gentleCurveThresholdDegrees = 10.0;

  /// Umbral de deflexión acumulada para considerar una curva pronunciada cuando el radio es compacto.
  static const double sharpCurveThresholdDegrees = 35.0;

  /// Radio máximo (m) para que una curva con deflexión >= 35° se considere pronunciada y no amplia.
  static const double sharpCurveMaxRadiusMeters = 110.0;

  /// Normaliza una diferencia angular al intervalo `[-180.0, 180.0]`.
  static double normalizeAngleDelta(double deltaDegrees) {
    double normalized = (deltaDegrees + 180.0) % 360.0;
    if (normalized < 0) normalized += 360.0;
    return normalized - 180.0;
  }

  /// Estima la curvatura vial hacia adelante sobre [geometry] desde [traveledDistanceMeters].
  ///
  /// NOTA SOBRE [upcomingManeuver]:
  /// Se conserva el parámetro por compatibilidad de firma, pero las maniobras discretas
  /// de navegación **nunca** se convierten en curvas viales; al contrario, si se proveen
  /// [maneuvers] o una maniobra de intersección/retorno en el vértice, dicho giro discreto
  /// se excluye de la estimación de curvatura de carretera.
  static RoadCurvatureInfo estimate({
    required List<Coordinates> geometry,
    required double traveledDistanceMeters,
    List<double>? cumulativeDistances,
    double lookaheadMeters = 100.0,
    Maneuver? upcomingManeuver,
    ManeuverType? upcomingManeuverType,
    double? distanceToManeuverMeters,
    double? upcomingManeuverDistance,
    List<Maneuver> maneuvers = const [],
    GeometrySource geometrySource = GeometrySource.internalRouteOsrm,
    int routeVersion = 1,
    DateTime? timestamp,
    bool isStale = false,
  }) {
    final evalTime = timestamp ?? DateTime.now();
    final resolvedManeuverType = upcomingManeuverType ?? upcomingManeuver?.type;
    final resolvedManeuverDistance =
        upcomingManeuverDistance ?? distanceToManeuverMeters;

    if (geometrySource == GeometrySource.none || geometry.length < 3) {
      return RoadCurvatureInfo.insufficient(
        geometrySource: geometrySource,
        routeVersion: routeVersion,
        timestamp: evalTime,
      );
    }

    // 1. Consolidar puntos duplicados y micro-segmentos (< 2.5 m)
    final cleanedPoints = <Coordinates>[geometry.first];
    for (int i = 1; i < geometry.length; i++) {
      final candidate = geometry[i];
      final dist = cleanedPoints.last.distanceTo(candidate);
      if (dist >= minSegmentLengthMeters) {
        cleanedPoints.add(candidate);
      } else if (i == geometry.length - 1 && cleanedPoints.length >= 2 && dist > 0.05) {
        // Reemplazar el penúltimo si el último tramo es un micro-segmento terminal
        cleanedPoints[cleanedPoints.length - 1] = candidate;
      }
    }

    if (cleanedPoints.length < 3) {
      return RoadCurvatureInfo.insufficient(
        geometrySource: geometrySource,
        routeVersion: routeVersion,
        timestamp: evalTime,
      );
    }

    // 2. Construir segmentos consolidados y distancias acumuladas reales
    final segments = <_ConsolidatedSegment>[];
    double accDist = 0.0;
    for (int i = 0; i < cleanedPoints.length - 1; i++) {
      final start = cleanedPoints[i];
      final end = cleanedPoints[i + 1];
      final len = start.distanceTo(end);
      if (len < 0.05) continue;
      final bearing = start.bearingTo(end);
      segments.add(
        _ConsolidatedSegment(
          start: start,
          end: end,
          startDistanceMeters: accDist,
          endDistanceMeters: accDist + len,
          lengthMeters: len,
          bearingDegrees: bearing,
        ),
      );
      accDist += len;
    }

    if (segments.length < 2) {
      return RoadCurvatureInfo.insufficient(
        geometrySource: geometrySource,
        routeVersion: routeVersion,
        timestamp: evalTime,
      );
    }

    final totalLength = segments.last.endDistanceMeters;
    final clampedTraveled = traveledDistanceMeters.clamp(0.0, totalLength);
    final remainingAhead = totalLength - clampedTraveled;

    if (remainingAhead < 5.0) {
      return RoadCurvatureInfo.insufficient(
        geometrySource: geometrySource,
        routeVersion: routeVersion,
        timestamp: evalTime,
      );
    }

    // 3. Localizar segmento actual
    int currentSegIndex = 0;
    for (int i = 0; i < segments.length; i++) {
      if (segments[i].endDistanceMeters >= clampedTraveled) {
        currentSegIndex = i;
        break;
      }
    }

    final double extendedWindow = math.max(lookaheadMeters * 2.0, 220.0);
    final double targetMaxDist = clampedTraveled + extendedWindow;

    // 4. Evaluar si los vértices dentro de la ventana son mero ruido lateral (GPS jitter)
    final windowVertices = <Coordinates>[segments[currentSegIndex].start];
    int lastSegInLookahead = currentSegIndex;
    for (int i = currentSegIndex; i < segments.length; i++) {
      windowVertices.add(segments[i].end);
      lastSegInLookahead = i;
      if (segments[i].endDistanceMeters >= clampedTraveled + lookaheadMeters) {
        break;
      }
    }

    if (windowVertices.length >= 3) {
      final chordStart = windowVertices.first;
      final chordEnd = windowVertices.last;
      final chordLen = chordStart.distanceTo(chordEnd);
      if (chordLen >= 20.0) {
        final chordBearing = chordStart.bearingTo(chordEnd);
        final entryBearing = segments[currentSegIndex].bearingDegrees;
        final exitBearing = segments[lastSegInLookahead].bearingDegrees;
        final netHeadingChange =
            normalizeAngleDelta(exitBearing - entryBearing).abs();

        double maxCrossTrackMeters = 0.0;
        for (int k = 1; k < windowVertices.length - 1; k++) {
          final d = chordStart.distanceTo(windowVertices[k]);
          final brg = chordStart.bearingTo(windowVertices[k]);
          final angleRad =
              normalizeAngleDelta(brg - chordBearing).abs() * math.pi / 180.0;
          final crossTrack = d * math.sin(angleRad);
          if (crossTrack > maxCrossTrackMeters) {
            maxCrossTrackMeters = crossTrack;
          }
        }

        // Si todos los vértices intermedios se mantienen dentro de ±2.8 m de la línea recta
        // y el rumbo neto entre entrada y salida varía menos de 8°, es ruido GPS/digitalización.
        if (maxCrossTrackMeters <= 2.8 && netHeadingChange < 8.0) {
          return RoadCurvatureInfo(
            type: RoadCurvatureType.straight,
            curveDirection: CurveDirection.none,
            curveClass: CurveClass.straight,
            distanceToCurveMeters: 0.0,
            estimatedLengthMeters: 0.0,
            estimatedRadiusMeters: null,
            confidence: 0.9,
            geometrySource: geometrySource,
            routeVersion: routeVersion,
            timestamp: evalTime,
            isStale: isStale,
            bearingDeltaDegrees: 0.0,
            windowLengthMeters: lookaheadMeters,
          );
        }
      }
    }

    // 5. Detectar transiciones angulares entre segmentos consecutivos,
    //    excluyendo giros discretos de intersección o retornos.
    final arcs = <_DetectedCurveArc>[];
    double? currentArcStart;
    double currentArcEnd = 0.0;
    double currentArcLength = 0.0;
    double currentArcAngle = 0.0;
    int currentArcVertices = 0;

    void flushCurrentArc() {
      if (currentArcStart != null &&
          currentArcAngle.abs() >= gentleCurveThresholdDegrees) {
        arcs.add(
          _DetectedCurveArc(
            startDistanceMeters: currentArcStart!,
            endDistanceMeters: currentArcEnd,
            arcLengthMeters: math.max(currentArcLength, 10.0),
            cumulativeAngleDegrees: currentArcAngle,
            vertexCount: currentArcVertices,
          ),
        );
      }
      currentArcStart = null;
      currentArcEnd = 0.0;
      currentArcLength = 0.0;
      currentArcAngle = 0.0;
      currentArcVertices = 0;
    }

    for (int i = currentSegIndex; i < segments.length - 1; i++) {
      final segA = segments[i];
      final segB = segments[i + 1];
      if (segA.endDistanceMeters > targetMaxDist) break;

      final vertexCoord = segA.end;
      final vertexDistFromCurrent = math.max(
        0.0,
        segA.endDistanceMeters - clampedTraveled,
      );
      final delta = normalizeAngleDelta(
        segB.bearingDegrees - segA.bearingDegrees,
      );

      // Verificar si este vértice corresponde a una maniobra discreta de intersección o retorno
      final isDiscreteManeuverVertex = _isDiscreteNavigationVertex(
        vertexCoord: vertexCoord,
        vertexDistFromRider: vertexDistFromCurrent,
        deltaDegrees: delta,
        segALength: segA.lengthMeters,
        segBLength: segB.lengthMeters,
        upcomingManeuver: resolvedManeuverType,
        upcomingManeuverDistance: resolvedManeuverDistance,
        maneuvers: maneuvers,
      );

      if (isDiscreteManeuverVertex) {
        flushCurrentArc();
        continue;
      }

      // Umbral por vértice para iniciar o continuar un arco de curva
      if (delta.abs() >= 4.0) {
        final sameSign =
            currentArcAngle == 0.0 ||
            (currentArcAngle > 0 && delta > 0) ||
            (currentArcAngle < 0 && delta < 0);

        if (currentArcStart == null) {
          currentArcStart = segA.startDistanceMeters;
          currentArcEnd = segB.endDistanceMeters;
          currentArcLength =
              0.5 * segA.lengthMeters + 0.5 * segB.lengthMeters;
          currentArcAngle = delta;
          currentArcVertices = 1;
        } else if (sameSign &&
            (segA.startDistanceMeters - currentArcEnd) <= 25.0) {
          currentArcEnd = segB.endDistanceMeters;
          currentArcLength += 0.5 * segA.lengthMeters + 0.5 * segB.lengthMeters;
          currentArcAngle += delta;
          currentArcVertices += 1;
        } else {
          flushCurrentArc();
          currentArcStart = segA.startDistanceMeters;
          currentArcEnd = segB.endDistanceMeters;
          currentArcLength =
              0.5 * segA.lengthMeters + 0.5 * segB.lengthMeters;
          currentArcAngle = delta;
          currentArcVertices = 1;
        }
      } else if (currentArcStart != null && segA.lengthMeters > 30.0) {
        flushCurrentArc();
      }
    }
    flushCurrentArc();

    // Filtrar arcos cuya entrada comienza dentro de la ventana de anticipación principal
    // y evaluar la secuencia completa para detectar curvas consecutivas / tramos sinuosos.
    if (arcs.isEmpty) {
      return RoadCurvatureInfo(
        type: RoadCurvatureType.straight,
        curveDirection: CurveDirection.none,
        curveClass: CurveClass.straight,
        distanceToCurveMeters: 0.0,
        estimatedLengthMeters: 0.0,
        estimatedRadiusMeters: null,
        confidence: _computeConfidence(
          segments: segments,
          startIndex: currentSegIndex,
          vertexCount: 0,
        ),
        geometrySource: geometrySource,
        routeVersion: routeVersion,
        timestamp: evalTime,
        isStale: isStale,
        bearingDeltaDegrees: 0.0,
        windowLengthMeters: lookaheadMeters,
        consecutiveCurveCount: 0,
      );
    }

    final primaryArc = arcs.first;
    final distToPrimary = math.max(
      0.0,
      primaryArc.startDistanceMeters - clampedTraveled,
    );

    // Si la primera curva aún está fuera de la ventana de anticipación inmediata
    if (distToPrimary > lookaheadMeters) {
      return RoadCurvatureInfo(
        type: RoadCurvatureType.straight,
        curveDirection: CurveDirection.none,
        curveClass: CurveClass.straight,
        distanceToCurveMeters: distToPrimary,
        estimatedLengthMeters: 0.0,
        estimatedRadiusMeters: null,
        confidence: _computeConfidence(
          segments: segments,
          startIndex: currentSegIndex,
          vertexCount: 0,
        ),
        geometrySource: geometrySource,
        routeVersion: routeVersion,
        timestamp: evalTime,
        isStale: isStale,
        bearingDeltaDegrees: 0.0,
        windowLengthMeters: lookaheadMeters,
        consecutiveCurveCount: 0,
      );
    }

    // Contar curvas cercanas y alternancia de sentido
    int alternatingTransitions = 0;
    double totalAbsAngle = primaryArc.cumulativeAngleDegrees.abs();
    for (int i = 1; i < arcs.length; i++) {
      totalAbsAngle += arcs[i].cumulativeAngleDegrees.abs();
      if (arcs[i].direction != arcs[i - 1].direction) {
        alternatingTransitions++;
      }
    }

    final confidence = _computeConfidence(
      segments: segments,
      startIndex: currentSegIndex,
      vertexCount: primaryArc.vertexCount,
    );

    // 6. Clasificar tramo sinuoso vs curvas consecutivas vs curva individual
    if (arcs.length >= 3 && alternatingTransitions >= 2 && totalAbsAngle >= 55.0) {
      final totalSpan = arcs.last.endDistanceMeters - primaryArc.startDistanceMeters;
      return RoadCurvatureInfo(
        type: RoadCurvatureType.winding,
        curveDirection: CurveDirection.alternating,
        curveClass: CurveClass.winding,
        distanceToCurveMeters: distToPrimary,
        estimatedLengthMeters: totalSpan,
        estimatedRadiusMeters: primaryArc.estimatedRadiusMeters,
        confidence: confidence,
        geometrySource: geometrySource,
        routeVersion: routeVersion,
        timestamp: evalTime,
        isStale: isStale,
        bearingDeltaDegrees: primaryArc.cumulativeAngleDegrees,
        windowLengthMeters: lookaheadMeters,
        consecutiveCurveCount: arcs.length,
      );
    }

    if (arcs.length == 2 &&
        (arcs[1].startDistanceMeters - primaryArc.endDistanceMeters) <= 80.0) {
      final totalSpan = arcs[1].endDistanceMeters - primaryArc.startDistanceMeters;
      return RoadCurvatureInfo(
        type: RoadCurvatureType.consecutiveCurves,
        curveDirection: arcs[0].direction != arcs[1].direction
            ? CurveDirection.alternating
            : primaryArc.direction,
        curveClass: CurveClass.consecutive,
        distanceToCurveMeters: distToPrimary,
        estimatedLengthMeters: totalSpan,
        estimatedRadiusMeters: primaryArc.estimatedRadiusMeters,
        confidence: confidence,
        geometrySource: geometrySource,
        routeVersion: routeVersion,
        timestamp: evalTime,
        isStale: isStale,
        bearingDeltaDegrees: primaryArc.cumulativeAngleDegrees,
        windowLengthMeters: lookaheadMeters,
        consecutiveCurveCount: 2,
      );
    }

    // 7. Clasificar curva individual combinando ángulo acumulado y radio/longitud
    final absAngle = primaryArc.cumulativeAngleDegrees.abs();
    final radius = primaryArc.estimatedRadiusMeters;
    final isRight = primaryArc.cumulativeAngleDegrees > 0;
    final direction = isRight ? CurveDirection.right : CurveDirection.left;

    // Si el radio estimado es muy amplio (> 650 m), el tramo es prácticamente recto
    if (radius != null && radius > 650.0) {
      return RoadCurvatureInfo(
        type: RoadCurvatureType.straight,
        curveDirection: CurveDirection.none,
        curveClass: CurveClass.straight,
        distanceToCurveMeters: 0.0,
        estimatedLengthMeters: primaryArc.arcLengthMeters,
        estimatedRadiusMeters: radius,
        confidence: confidence,
        geometrySource: geometrySource,
        routeVersion: routeVersion,
        timestamp: evalTime,
        isStale: isStale,
        bearingDeltaDegrees: primaryArc.cumulativeAngleDegrees,
        windowLengthMeters: lookaheadMeters,
        consecutiveCurveCount: 1,
      );
    }

    // Determinar si es pronunciada/horquilla o amplia/gradual
    final bool isTightRadius =
        radius == null || radius <= sharpCurveMaxRadiusMeters;
    final bool isHairpin = absAngle >= 120.0 && (radius == null || radius <= 45.0);
    final bool isSharp = absAngle >= sharpCurveThresholdDegrees && isTightRadius;

    final CurveClass curveClass = isHairpin
        ? CurveClass.hairpin
        : (isSharp ? CurveClass.sharp : CurveClass.gentle);

    final RoadCurvatureType curvatureType = isSharp
        ? (isRight ? RoadCurvatureType.sharpRight : RoadCurvatureType.sharpLeft)
        : (isRight
              ? RoadCurvatureType.gentleRight
              : RoadCurvatureType.gentleLeft);

    return RoadCurvatureInfo(
      type: curvatureType,
      curveDirection: direction,
      curveClass: curveClass,
      distanceToCurveMeters: distToPrimary,
      estimatedLengthMeters: primaryArc.arcLengthMeters,
      estimatedRadiusMeters: radius,
      confidence: confidence,
      geometrySource: geometrySource,
      routeVersion: routeVersion,
      timestamp: evalTime,
      isStale: isStale,
      bearingDeltaDegrees: primaryArc.cumulativeAngleDegrees,
      windowLengthMeters: lookaheadMeters,
      consecutiveCurveCount: arcs.length,
    );
  }

  /// Determina si un vértice corresponde a una maniobra discreta de intersección o retorno
  /// que NO debe clasificarse como curvatura continua de carretera.
  static bool _isDiscreteNavigationVertex({
    required Coordinates vertexCoord,
    required double vertexDistFromRider,
    required double deltaDegrees,
    required double segALength,
    required double segBLength,
    required ManeuverType? upcomingManeuver,
    required double? upcomingManeuverDistance,
    required List<Maneuver> maneuvers,
  }) {
    // 1. Retorno brusco aislado (>= 155° en un único pivote o micro-transición)
    if (deltaDegrees.abs() >= 155.0) {
      return true;
    }

    // 2. Coincidencia con la lista explícita de maniobras de la ruta
    for (final m in maneuvers) {
      if (_isIntersectionOrTurnaroundManeuver(m.type)) {
        if (m.location.distanceTo(vertexCoord) <= 25.0) {
          return true;
        }
      }
    }

    // 3. Coincidencia con la próxima maniobra discreta reportada por el motor
    if (upcomingManeuver != null &&
        _isIntersectionOrTurnaroundManeuver(upcomingManeuver) &&
        upcomingManeuverDistance != null) {
      if ((vertexDistFromRider - upcomingManeuverDistance).abs() <= 30.0) {
        return true;
      }
    }

    return false;
  }

  static bool _isIntersectionOrTurnaroundManeuver(ManeuverType type) {
    switch (type) {
      case ManeuverType.left:
      case ManeuverType.right:
      case ManeuverType.sharpLeft:
      case ManeuverType.sharpRight:
      case ManeuverType.uTurn:
      case ManeuverType.roundabout:
        return true;
      case ManeuverType.depart:
      case ManeuverType.straight:
      case ManeuverType.slightLeft:
      case ManeuverType.slightRight:
      case ManeuverType.arrive:
      case ManeuverType.unknown:
        return false;
    }
  }

  static double _computeConfidence({
    required List<_ConsolidatedSegment> segments,
    required int startIndex,
    required int vertexCount,
  }) {
    if (segments.length < 2) return 0.0;
    final availableAhead = segments.length - startIndex;
    double baseConfidence = availableAhead >= 4 ? 0.85 : 0.70;
    if (vertexCount >= 2) {
      baseConfidence += 0.10;
    }
    return baseConfidence.clamp(0.0, 1.0);
  }

  /// Interpola linealmente una coordenada sobre [geometry] a la distancia acumulada [distanceMeters].
  static Coordinates interpolateAtDistance(
    List<Coordinates> geometry,
    List<double> cumulativeDistances,
    double distanceMeters,
  ) {
    if (geometry.isEmpty) return Coordinates(4.814278, -75.694247);
    if (geometry.length == 1 || distanceMeters <= 0.0) return geometry.first;
    if (cumulativeDistances.isEmpty ||
        distanceMeters >= cumulativeDistances.last) {
      return geometry.last;
    }

    int seg = 0;
    for (int i = 0; i < cumulativeDistances.length - 1; i++) {
      if (cumulativeDistances[i + 1] >= distanceMeters) {
        seg = i;
        break;
      }
    }

    final d0 = cumulativeDistances[seg];
    final d1 = cumulativeDistances[seg + 1];
    final segLength = d1 - d0;
    if (segLength <= 0.0001) return geometry[seg];

    final t = ((distanceMeters - d0) / segLength).clamp(0.0, 1.0);
    final pA = geometry[seg];
    final pB = geometry[seg + 1];

    final lat = pA.latitude + t * (pB.latitude - pA.latitude);
    final lon = pA.longitude + t * (pB.longitude - pA.longitude);
    return Coordinates(lat, lon);
  }
}
