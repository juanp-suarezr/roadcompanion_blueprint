import 'package:flutter_test/flutter_test.dart';
import 'package:road_companion/domain/entities/coordinates.dart';
import 'package:road_companion/domain/entities/maneuver.dart';
import 'package:road_companion/domain/entities/maneuver_type.dart';
import 'package:road_companion/domain/entities/route_plan.dart';
import 'package:road_companion/features/navigation/domain/entities/calculated_route.dart';
import 'package:road_companion/features/navigation/domain/services/navigation_maneuver_engine.dart';

void main() {
  group('NavigationManeuverEngine - Resolución métrica de maniobras', () {
    late NavigationManeuverEngine engine;
    late CalculatedRoute testRoute;

    setUp(() {
      engine = NavigationManeuverEngine();

      final geometry = [
        Coordinates(4.8000, -75.6900), // Vértice 0 (Inicio)
        Coordinates(4.8050, -75.6900), // Vértice 1 (~555 m)
        Coordinates(4.8050, -75.6950), // Vértice 2 (~1110 m)
        Coordinates(4.8100, -75.6950), // Vértice 3 (~1665 m) (Destino)
      ];

      final maneuvers = [
        Maneuver(
          instructionText: 'Inicia el recorrido hacia el norte',
          type: ManeuverType.depart,
          location: Coordinates(4.8000, -75.6900),
          distanceMeters: 555.0,
        ),
        Maneuver(
          instructionText: 'Gira a la izquierda en Calle 20',
          type: ManeuverType.left,
          location: Coordinates(4.8050, -75.6900),
          roadName: 'Calle 20',
          distanceMeters: 555.0,
        ),
        Maneuver(
          instructionText: 'Gira a la derecha en Carrera 8',
          type: ManeuverType.right,
          location: Coordinates(4.8050, -75.6950),
          roadName: 'Carrera 8',
          distanceMeters: 555.0,
        ),
        Maneuver(
          instructionText: 'Has llegado a tu destino',
          type: ManeuverType.arrive,
          location: Coordinates(4.8100, -75.6950),
          distanceMeters: 0.0,
        ),
      ];

      final routePlan = RoutePlan(
        origin: geometry.first,
        destination: geometry.last,
        geometry: geometry,
        totalDistanceMeters: 1665.0,
        estimatedDuration: const Duration(minutes: 5),
        maneuvers: maneuvers,
      );

      testRoute = CalculatedRoute(
        routePlan: routePlan,
        summary: 'Ruta de prueba urbana',
      );
    });

    test('Al inicio de la ruta, resuelve el primer paso con su distancia real', () {
      engine.setRoute(testRoute);

      // Posición del rider al inicio (a ~100m del origen)
      final step = engine.resolveStep(
        currentCoordinates: Coordinates(4.8009, -75.6900),
      );

      expect(step, isNotNull);
      // Tras iniciar, la maniobra a la que se aproxima es el giro en Calle 20
      expect(step!.activeManeuver.type, equals(ManeuverType.left));
      expect(step.distanceToManeuverMeters, closeTo(455.0, 30.0));
    });

    test('Al avanzar cerca del giro en Calle 20, calcula distancia métrica decreciente', () {
      engine.setRoute(testRoute);

      // Posición a ~55m antes de Calle 20 (4.8045, -75.6900)
      final step = engine.resolveStep(
        currentCoordinates: Coordinates(4.8045, -75.6900),
      );

      expect(step, isNotNull);
      expect(step!.activeManeuver.type, equals(ManeuverType.left));
      expect(step.distanceToManeuverMeters, closeTo(55.0, 15.0));
      expect(step.activeManeuver.roadName, equals('Calle 20'));
      expect(step.nextManeuver?.type, equals(ManeuverType.right));
    });

    test('Al superar Calle 20, avanza automáticamente a Carrera 8', () {
      engine.setRoute(testRoute);

      // Posición 100m después de Calle 20 sobre el segundo tramo
      final step = engine.resolveStep(
        currentCoordinates: Coordinates(4.8050, -75.6910),
      );

      expect(step, isNotNull);
      expect(step!.activeManeuver.type, equals(ManeuverType.right));
      expect(step.activeManeuver.roadName, equals('Carrera 8'));
    });
  });
}
