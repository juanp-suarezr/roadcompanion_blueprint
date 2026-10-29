import 'package:flutter_test/flutter_test.dart';
import 'package:road_companion/domain/entities/coordinates.dart';
import 'package:road_companion/domain/entities/maneuver.dart';
import 'package:road_companion/domain/entities/maneuver_type.dart';
import 'package:road_companion/features/navigation/domain/entities/road_curvature.dart';
import 'package:road_companion/features/navigation/domain/services/road_curvature_estimator.dart';

void main() {
  group(
    'RoadCurvatureEstimator — Detección geométrica real y rechazo de falsos positivos (Prioridad B)',
    () {
      final baseOrigin = Coordinates(4.8143, -75.6946);

      test(
        '1. Recta: tramo con deflexión menor a 10° se clasifica como recto sin radio inventado',
        () {
          final p0 = baseOrigin;
          final p1 = p0.project(0.0, 60.0);
          final p2 = p1.project(2.0, 60.0);
          final p3 = p2.project(1.0, 60.0);

          final info = RoadCurvatureEstimator.estimate(
            geometry: [p0, p1, p2, p3],
            traveledDistanceMeters: 10.0,
            geometrySource: GeometrySource.internalRouteOsrm,
            routeVersion: 1,
          );

          expect(info.curveClass, equals(CurveClass.straight));
          expect(info.curveDirection, equals(CurveDirection.none));
          expect(info.type, equals(RoadCurvatureType.straight));
          expect(info.estimatedRadiusMeters, isNull);
          expect(info.hasActiveCurve, isFalse);
        },
      );

      test(
        '2. Curva amplia a izquierda: deflexión gradual a la izquierda o gran radio se clasifica como gentleLeft',
        () {
          // Arco amplio a la izquierda: 4 segmentos de 50m girando -12° cada uno (-36° total en 150m -> R ~ 238m > 110m)
          final p0 = baseOrigin;
          final p1 = p0.project(0.0, 50.0);
          final p2 = p1.project(348.0, 50.0); // -12°
          final p3 = p2.project(336.0, 50.0); // -24°
          final p4 = p3.project(324.0, 50.0); // -36°

          final info = RoadCurvatureEstimator.estimate(
            geometry: [p0, p1, p2, p3, p4],
            traveledDistanceMeters: 20.0,
            lookaheadMeters: 150.0,
          );

          expect(info.curveDirection, equals(CurveDirection.left));
          expect(info.curveClass, equals(CurveClass.gentle));
          expect(info.type, equals(RoadCurvatureType.gentleLeft));
          expect(info.estimatedRadiusMeters, isNotNull);
          expect(info.estimatedRadiusMeters!, greaterThan(110.0));
          expect(info.hasActiveCurve, isTrue);
        },
      );

      test(
        '3. Curva amplia a derecha: deflexión gradual a la derecha se clasifica como gentleRight',
        () {
          final p0 = baseOrigin;
          final p1 = p0.project(0.0, 45.0);
          final p2 = p1.project(14.0, 45.0);
          final p3 = p2.project(26.0, 45.0);

          final info = RoadCurvatureEstimator.estimate(
            geometry: [p0, p1, p2, p3],
            traveledDistanceMeters: 15.0,
            lookaheadMeters: 120.0,
          );

          expect(info.curveDirection, equals(CurveDirection.right));
          expect(info.curveClass, equals(CurveClass.gentle));
          expect(info.type, equals(RoadCurvatureType.gentleRight));
          expect(info.estimatedRadiusMeters, isNotNull);
          expect(info.distanceToCurveMeters, greaterThanOrEqualTo(0.0));
        },
      );

      test(
        '4. Curva pronunciada: cambio de rumbo >= 35° en distancia corta produce radio compacto y sharp',
        () {
          final p0 = baseOrigin;
          final p1 = p0.project(0.0, 35.0);
          final p2 = p1.project(30.0, 25.0);
          final p3 = p2.project(65.0, 35.0); // +65° acumulados en arco corto

          final info = RoadCurvatureEstimator.estimate(
            geometry: [p0, p1, p2, p3],
            traveledDistanceMeters: 10.0,
            lookaheadMeters: 100.0,
          );

          expect(info.curveDirection, equals(CurveDirection.right));
          expect(info.curveClass, equals(CurveClass.sharp));
          expect(info.type, equals(RoadCurvatureType.sharpRight));
          expect(info.estimatedRadiusMeters, isNotNull);
          expect(info.estimatedRadiusMeters!, lessThanOrEqualTo(110.0));
        },
      );

      test(
        '5. Curvas consecutivas: dos curvas cercanas se detectan como CurveClass.consecutive',
        () {
          final p0 = baseOrigin;
          final p1 = p0.project(0.0, 35.0);
          final p2 = p1.project(25.0, 35.0); // Curva 1 a la derecha (+25°)
          final p3 = p2.project(
            25.0,
            40.0,
          ); // Tramo recto intermedio de 40m (> 30m separa arcos)
          final p4 = p3.project(0.0, 35.0); // Curva 2 a la izquierda (-25°)

          final info = RoadCurvatureEstimator.estimate(
            geometry: [p0, p1, p2, p3, p4],
            traveledDistanceMeters: 5.0,
            lookaheadMeters: 120.0,
          );

          expect(info.curveClass, equals(CurveClass.consecutive));
          expect(info.type, equals(RoadCurvatureType.consecutiveCurves));
          expect(info.consecutiveCurveCount, equals(2));
        },
      );

      test(
        '6. Tramo sinuoso: sucesión de 3+ curvas alternadas se clasifica como CurveClass.winding',
        () {
          final p0 = baseOrigin;
          final p1 = p0.project(0.0, 30.0);
          final p2 = p1.project(30.0, 30.0); // Derecha (+30°)
          final p3 = p2.project(355.0, 30.0); // Izquierda (-35°)
          final p4 = p3.project(30.0, 30.0); // Derecha (+35°)
          final p5 = p4.project(0.0, 30.0); // Izquierda (-30°)

          final info = RoadCurvatureEstimator.estimate(
            geometry: [p0, p1, p2, p3, p4, p5],
            traveledDistanceMeters: 5.0,
            lookaheadMeters: 120.0,
          );

          expect(info.curveClass, equals(CurveClass.winding));
          expect(info.curveDirection, equals(CurveDirection.alternating));
          expect(info.type, equals(RoadCurvatureType.winding));
          expect(info.consecutiveCurveCount, greaterThanOrEqualTo(3));
        },
      );

      test(
        '7. Intersección con giro: maniobra discreta de intersección no se mezcla con curvatura vial',
        () {
          final p0 = baseOrigin;
          final corner = p0.project(0.0, 60.0);
          final afterTurn = corner.project(
            90.0,
            60.0,
          ); // Esquina de 90° en intersección

          final intersectionManeuver = Maneuver(
            instructionText: 'Gira a la derecha en Calle 50',
            type: ManeuverType.right,
            location: corner,
            distanceMeters: 40.0,
          );

          final info = RoadCurvatureEstimator.estimate(
            geometry: [p0, corner, afterTurn],
            traveledDistanceMeters: 20.0,
            maneuvers: [intersectionManeuver],
            upcomingManeuver: intersectionManeuver,
            distanceToManeuverMeters: 40.0,
          );

          // El giro discreto de intersección queda excluido de la curvatura de carretera
          expect(info.curveClass, equals(CurveClass.straight));
          expect(info.type, equals(RoadCurvatureType.straight));
        },
      );

      test(
        '8. Retorno: inversión brusca de sentido (~180°) no genera curva falsa de carretera',
        () {
          final p0 = baseOrigin;
          final pivot = p0.project(0.0, 60.0);
          final returnEnd = pivot.project(178.0, 60.0); // Retorno de ~178°

          final info = RoadCurvatureEstimator.estimate(
            geometry: [p0, pivot, returnEnd],
            traveledDistanceMeters: 20.0,
            upcomingManeuverType: ManeuverType.uTurn,
            upcomingManeuverDistance: 40.0,
          );

          expect(info.curveClass, equals(CurveClass.straight));
          expect(info.hasActiveCurve, isFalse);
        },
      );

      test(
        '9. Geometría incompleta: menos de 3 vértices o fuente externa sin geometría produce insufficientData',
        () {
          final emptyInfo = RoadCurvatureEstimator.estimate(
            geometry: const [],
            traveledDistanceMeters: 0.0,
          );
          expect(emptyInfo.curveClass, equals(CurveClass.insufficientData));
          expect(emptyInfo.confidence, equals(0.0));
          expect(emptyInfo.estimatedRadiusMeters, isNull);

          final twoPointsInfo = RoadCurvatureEstimator.estimate(
            geometry: [baseOrigin, baseOrigin.project(0.0, 100.0)],
            traveledDistanceMeters: 10.0,
          );
          expect(twoPointsInfo.curveClass, equals(CurveClass.insufficientData));

          final externalNoGeomInfo = RoadCurvatureEstimator.estimate(
            geometry: [
              baseOrigin,
              baseOrigin.project(0.0, 50.0),
              baseOrigin.project(0.0, 50.0).project(40.0, 50.0),
            ],
            traveledDistanceMeters: 10.0,
            geometrySource: GeometrySource.none,
          );
          expect(
            externalNoGeomInfo.curveClass,
            equals(CurveClass.insufficientData),
          );
          expect(externalNoGeomInfo.confidence, equals(0.0));
        },
      );

      test(
        '10. Coordenadas duplicadas: vértices idénticos consecutivos se consolidan sin NaN ni falsas curvas',
        () {
          final p0 = baseOrigin;
          final p1 = p0.project(0.0, 50.0);
          final p2 = p1.project(25.0, 50.0);

          final info = RoadCurvatureEstimator.estimate(
            geometry: [p0, p0, p1, p1, p1, p2, p2],
            traveledDistanceMeters: 10.0,
          );

          expect(info.bearingDeltaDegrees.isFinite, isTrue);
          expect(info.curveClass, equals(CurveClass.gentle));
          expect(info.curveDirection, equals(CurveDirection.right));
        },
      );

      test(
        '11. GPS ruidoso: zig-zag lateral menor a 2.5m sobre una recta se filtra como straight',
        () {
          final p0 = baseOrigin;
          // Puntos cada 15 m avanzando al norte (0°), pero con ruido lateral alternado de ±1.2 m
          final p1 = p0.project(4.0, 15.0);
          final p2 = p1.project(352.0, 15.0);
          final p3 = p2.project(8.0, 15.0);
          final p4 = p3.project(356.0, 15.0);
          final p5 = p4.project(0.0, 30.0);

          final info = RoadCurvatureEstimator.estimate(
            geometry: [p0, p1, p2, p3, p4, p5],
            traveledDistanceMeters: 0.0,
            lookaheadMeters: 80.0,
          );

          expect(info.curveClass, equals(CurveClass.straight));
          expect(info.type, equals(RoadCurvatureType.straight));
        },
      );

      test(
        '12. Ruta recalculada: versión de ruta anterior se detecta como desactualizada',
        () {
          final p0 = baseOrigin;
          final p1 = p0.project(0.0, 50.0);
          final p2 = p1.project(40.0, 50.0);

          final oldRouteCurve = RoadCurvatureEstimator.estimate(
            geometry: [p0, p1, p2],
            traveledDistanceMeters: 10.0,
            routeVersion: 1,
          );

          expect(oldRouteCurve.routeVersion, equals(1));
          expect(oldRouteCurve.isOutdated(activeRouteVersion: 1), isFalse);
          expect(oldRouteCurve.isOutdated(activeRouteVersion: 2), isTrue);
        },
      );

      test(
        '13. Cambio de sentido de la ruta: invertir la polilínea invierte izquierda <-> derecha simétricamente',
        () {
          final p0 = baseOrigin;
          final p1 = p0.project(0.0, 50.0);
          final p2 = p1.project(35.0, 50.0); // Giro a la derecha yendo p0 -> p2

          final forwardInfo = RoadCurvatureEstimator.estimate(
            geometry: [p0, p1, p2],
            traveledDistanceMeters: 15.0,
          );
          final reverseInfo = RoadCurvatureEstimator.estimate(
            geometry: [p2, p1, p0],
            traveledDistanceMeters: 15.0,
          );

          expect(forwardInfo.curveDirection, equals(CurveDirection.right));
          expect(reverseInfo.curveDirection, equals(CurveDirection.left));
          expect(
            forwardInfo.bearingDeltaDegrees.abs(),
            closeTo(reverseInfo.bearingDeltaDegrees.abs(), 0.5),
          );
        },
      );

      test(
        '14. Geometría desactualizada: marca temporal expirada o markStale inhabilita hasActiveCurve',
        () {
          final p0 = baseOrigin;
          final p1 = p0.project(0.0, 50.0);
          final p2 = p1.project(45.0, 50.0);
          final t0 = DateTime(2026, 10, 29, 10, 0, 0);

          final info = RoadCurvatureEstimator.estimate(
            geometry: [p0, p1, p2],
            traveledDistanceMeters: 15.0,
            timestamp: t0,
            routeVersion: 3,
          );

          expect(
            info.isOutdated(
              activeRouteVersion: 3,
              now: t0.add(const Duration(seconds: 5)),
            ),
            isFalse,
          );
          expect(
            info.isOutdated(
              activeRouteVersion: 3,
              now: t0.add(const Duration(seconds: 20)),
            ),
            isTrue,
          );

          final staleCopy = info.markStale();
          expect(staleCopy.isStale, isTrue);
          expect(staleCopy.hasActiveCurve, isFalse);
        },
      );

      test(
        '15. Segmentos con distancias demasiado pequeñas (< 2.5m) no disparan curvas falsas',
        () {
          final p0 = baseOrigin;
          final p1 = p0.project(0.0, 40.0);
          // Micro-escalón espurio de 0.8 metros a 80° que en un estimador ingenuo daría curva cerrada
          final microStep = p1.project(80.0, 0.8);
          final p2 = microStep.project(0.0, 40.0);

          final info = RoadCurvatureEstimator.estimate(
            geometry: [p0, p1, microStep, p2],
            traveledDistanceMeters: 10.0,
          );

          expect(info.curveClass, equals(CurveClass.straight));
          expect(info.type, equals(RoadCurvatureType.straight));
        },
      );
    },
  );
}
