import 'package:road_companion/road_companion.dart';
import 'package:test/test.dart';

void main() {
  final origin = Coordinates(4.8133, -75.6961); // Pereira
  final waypoint = Coordinates(4.7000, -75.6500); // Tramo vial intermedio
  final destination = Coordinates(4.5339, -75.6811); // Armenia

  final step1 = Maneuver(
    instructionText: 'Salida de Pereira por Variante',
    type: ManeuverType.depart,
    location: origin,
    distanceMeters: 5000.0,
  );

  final step2 = Maneuver(
    instructionText: 'Continúa por Autopista del Café',
    type: ManeuverType.straight,
    location: waypoint,
    distanceMeters: 35000.0,
  );

  final step3 = Maneuver(
    instructionText: 'Llegada a Plaza de Bolívar de Armenia',
    type: ManeuverType.arrive,
    location: destination,
    distanceMeters: 0.0,
  );

  group('RoutePlan - Validaciones de métricas y estados', () {
    test('crea un RoutePlan válido con todos sus datos', () {
      final plan = RoutePlan(
        origin: origin,
        destination: destination,
        maneuvers: [step1, step2, step3],
        geometry: [origin, waypoint, destination],
        totalDistanceMeters: 45000.0,
        estimatedDuration: const Duration(minutes: 55),
        remainingDistanceMeters: 45000.0,
      );

      expect(plan.origin, equals(origin));
      expect(plan.destination, equals(destination));
      expect(plan.maneuvers.length, equals(3));
      expect(plan.geometry.length, equals(3));
      expect(plan.totalDistanceMeters, equals(45000.0));
      expect(plan.estimatedDuration, equals(const Duration(minutes: 55)));
      expect(plan.remainingDistanceMeters, equals(45000.0));
    });

    test(
        'acepta distancia total 0.0 m con duración Duration.zero (origen == destino)',
        () {
      final zeroPlan = RoutePlan(
        origin: origin,
        destination: origin,
        maneuvers: [step3],
        geometry: [origin],
        totalDistanceMeters: 0.0,
        estimatedDuration: Duration.zero,
        remainingDistanceMeters: 0.0,
      );

      expect(zeroPlan.totalDistanceMeters, equals(0.0));
      expect(zeroPlan.estimatedDuration, equals(Duration.zero));
      expect(zeroPlan.remainingDistanceMeters, equals(0.0));
    });

    test('acepta distancia restante igual a 0.0 m (arribo a destino)', () {
      final plan = RoutePlan(
        origin: origin,
        destination: destination,
        maneuvers: [step1],
        totalDistanceMeters: 1000.0,
        estimatedDuration: const Duration(minutes: 2),
        remainingDistanceMeters: 0.0,
      );

      expect(plan.remainingDistanceMeters, equals(0.0));
    });

    test(
        'acepta distancia restante igual exactamente a totalDistanceMeters (inicio del viaje)',
        () {
      final plan = RoutePlan(
        origin: origin,
        destination: destination,
        maneuvers: [step1],
        totalDistanceMeters: 12500.0,
        estimatedDuration: const Duration(minutes: 18),
        remainingDistanceMeters: 12500.0,
      );

      expect(plan.remainingDistanceMeters, equals(12500.0));
    });

    test('rechaza distancia total negativa', () {
      expect(
        () => RoutePlan(
          origin: origin,
          destination: destination,
          maneuvers: [step1],
          totalDistanceMeters: -0.01,
          estimatedDuration: const Duration(minutes: 10),
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'totalDistanceMeters',
        )),
      );
    });

    test('rechaza distancia total no finita (NaN, Infinity, -Infinity)', () {
      expect(
        () => RoutePlan(
          origin: origin,
          destination: destination,
          maneuvers: [step1],
          totalDistanceMeters: double.nan,
          estimatedDuration: const Duration(minutes: 10),
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'totalDistanceMeters',
        )),
      );

      expect(
        () => RoutePlan(
          origin: origin,
          destination: destination,
          maneuvers: [step1],
          totalDistanceMeters: double.infinity,
          estimatedDuration: const Duration(minutes: 10),
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'totalDistanceMeters',
        )),
      );

      expect(
        () => RoutePlan(
          origin: origin,
          destination: destination,
          maneuvers: [step1],
          totalDistanceMeters: double.negativeInfinity,
          estimatedDuration: const Duration(minutes: 10),
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'totalDistanceMeters',
        )),
      );
    });

    test('rechaza duración estimada negativa', () {
      expect(
        () => RoutePlan(
          origin: origin,
          destination: destination,
          maneuvers: [step1],
          totalDistanceMeters: 1000.0,
          estimatedDuration: const Duration(milliseconds: -1),
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'estimatedDuration',
        )),
      );
    });

    test('rechaza distancia restante negativa', () {
      expect(
        () => RoutePlan(
          origin: origin,
          destination: destination,
          maneuvers: [step1],
          totalDistanceMeters: 5000.0,
          estimatedDuration: const Duration(minutes: 10),
          remainingDistanceMeters: -0.1,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'remainingDistanceMeters',
        )),
      );
    });

    test('rechaza distancia restante no finita (NaN, Infinity, -Infinity)', () {
      expect(
        () => RoutePlan(
          origin: origin,
          destination: destination,
          maneuvers: [step1],
          totalDistanceMeters: 5000.0,
          estimatedDuration: const Duration(minutes: 10),
          remainingDistanceMeters: double.nan,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'remainingDistanceMeters',
        )),
      );

      expect(
        () => RoutePlan(
          origin: origin,
          destination: destination,
          maneuvers: [step1],
          totalDistanceMeters: 5000.0,
          estimatedDuration: const Duration(minutes: 10),
          remainingDistanceMeters: double.infinity,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'remainingDistanceMeters',
        )),
      );
    });

    test('rechaza distancia restante mayor a la distancia total por carretera',
        () {
      expect(
        () => RoutePlan(
          origin: origin,
          destination: destination,
          maneuvers: [step1],
          totalDistanceMeters: 10000.0,
          estimatedDuration: const Duration(minutes: 15),
          remainingDistanceMeters: 10005.0, // Supera por 5 metros
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'remainingDistanceMeters',
        )),
      );
    });
  });

  group('RoutePlan - Inmutabilidad estricta de colecciones', () {
    test('las listas maneuvers y geometry no pueden modificarse externamente',
        () {
      final plan = RoutePlan(
        origin: origin,
        destination: destination,
        maneuvers: [step1, step2],
        geometry: [origin, destination],
        totalDistanceMeters: 40000.0,
        estimatedDuration: const Duration(minutes: 45),
      );

      expect(() => plan.maneuvers.add(step3), throwsA(isA<UnsupportedError>()));
      expect(() => plan.maneuvers.clear(), throwsA(isA<UnsupportedError>()));
      expect(
          () => plan.geometry.add(waypoint), throwsA(isA<UnsupportedError>()));
      expect(() => plan.geometry.clear(), throwsA(isA<UnsupportedError>()));
    });

    test(
        'modificar la lista original antes del constructor no afecta la entidad (copia defensiva)',
        () {
      final mutableManeuvers = [step1, step2];
      final mutableGeometry = [origin, destination];

      final plan = RoutePlan(
        origin: origin,
        destination: destination,
        maneuvers: mutableManeuvers,
        geometry: mutableGeometry,
        totalDistanceMeters: 40000.0,
        estimatedDuration: const Duration(minutes: 45),
      );

      mutableManeuvers.add(step3);
      mutableGeometry.add(waypoint);

      expect(plan.maneuvers.length, equals(2));
      expect(plan.geometry.length, equals(2));
    });
  });

  group(
      'RoutePlan - Responsabilidades, limitaciones y no consistencia forzada de distancias',
      () {
    test(
        'calculateDirectDistance calcula Haversine directo sin considerar carretera',
        () {
      final plan = RoutePlan(
        origin: origin,
        destination: destination,
        maneuvers: [step1, step2, step3],
        geometry: [origin, waypoint, destination],
        totalDistanceMeters: 45000.0,
        estimatedDuration: const Duration(minutes: 50),
      );

      final direct = plan.calculateDirectDistance();
      expect(direct, closeTo(31100, 400));
      expect(direct, lessThan(plan.totalDistanceMeters));
    });

    test(
        'calculateGeometryDistance devuelve 0.0 en geometrías vacías o de un solo punto',
        () {
      final emptyGeomPlan = RoutePlan(
        origin: origin,
        destination: destination,
        maneuvers: [step1],
        geometry: const [],
        totalDistanceMeters: 1000.0,
        estimatedDuration: const Duration(minutes: 2),
      );
      final singlePointPlan = RoutePlan(
        origin: origin,
        destination: destination,
        maneuvers: [step1],
        geometry: [origin],
        totalDistanceMeters: 1000.0,
        estimatedDuration: const Duration(minutes: 2),
      );

      expect(emptyGeomPlan.calculateGeometryDistance(), equals(0.0));
      expect(singlePointPlan.calculateGeometryDistance(), equals(0.0));
    });

    test(
        'calculateGeometryDistance suma segmentos rectos consecutivos de la polilínea',
        () {
      final plan = RoutePlan(
        origin: origin,
        destination: destination,
        maneuvers: [step1, step2],
        geometry: [origin, waypoint, destination],
        totalDistanceMeters: 40000.0,
        estimatedDuration: const Duration(minutes: 40),
      );

      final expectedSum =
          origin.distanceTo(waypoint) + waypoint.distanceTo(destination);
      expect(plan.calculateGeometryDistance(), closeTo(expectedSum, 0.001));
    });

    test(
        'no se asume consistencia artificial entre calculateGeometryDistance y totalDistanceMeters',
        () {
      // Un proveedor entrega una polilínea simplificada con longitud menor a la distancia vial real
      final plan = RoutePlan(
        origin: origin,
        destination: destination,
        maneuvers: [step1, step2, step3],
        geometry: [
          origin,
          destination
        ], // Polilínea simplificada a línea directa (~31.1 km)
        totalDistanceMeters:
            45000.0, // Proveedor declara 45 km reales por carretera
        estimatedDuration: const Duration(minutes: 50),
      );

      final geometrySum = plan.calculateGeometryDistance();

      // Comprueba que no se fuerzan a ser idénticos ni se lanzan excepciones
      expect(geometrySum, closeTo(31100, 400));
      expect(plan.totalDistanceMeters, equals(45000.0));
      expect(geometrySum, isNot(equals(plan.totalDistanceMeters)));
    });

    test(
        'copyWithRemainingDistance actualiza la distancia restante de forma inmutable',
        () {
      final initialPlan = RoutePlan(
        origin: origin,
        destination: destination,
        maneuvers: [step1, step2],
        totalDistanceMeters: 40000.0,
        estimatedDuration: const Duration(minutes: 40),
        remainingDistanceMeters: 40000.0,
      );

      final updatedPlan = initialPlan.copyWithRemainingDistance(25000.0);

      expect(updatedPlan.remainingDistanceMeters, equals(25000.0));
      expect(initialPlan.remainingDistanceMeters, equals(40000.0));

      expect(
        () => initialPlan.copyWithRemainingDistance(-10.0),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => initialPlan.copyWithRemainingDistance(50000.0),
        throwsA(isA<ArgumentError>()),
      );
    });

    test(
        'copyWith permite establecer remainingDistanceMeters explícitamente en null',
        () {
      final initialPlan = RoutePlan(
        origin: origin,
        destination: destination,
        maneuvers: [step1, step2],
        totalDistanceMeters: 40000.0,
        estimatedDuration: const Duration(minutes: 40),
        remainingDistanceMeters: 20000.0,
      );

      final clearedPlan = initialPlan.copyWith(remainingDistanceMeters: null);

      expect(clearedPlan.remainingDistanceMeters, isNull);
      expect(clearedPlan.totalDistanceMeters,
          equals(initialPlan.totalDistanceMeters));
      expect(clearedPlan.origin, equals(initialPlan.origin));
    });

    test('copyWith preserva remainingDistanceMeters si se omite el argumento',
        () {
      final initialPlan = RoutePlan(
        origin: origin,
        destination: destination,
        maneuvers: [step1, step2],
        totalDistanceMeters: 40000.0,
        estimatedDuration: const Duration(minutes: 40),
        remainingDistanceMeters: 20000.0,
      );

      final updatedPlan = initialPlan.copyWith(totalDistanceMeters: 42000.0);

      expect(updatedPlan.remainingDistanceMeters, equals(20000.0));
      expect(updatedPlan.totalDistanceMeters, equals(42000.0));
    });

    test(
        'copyWith lanza TypeError si se pasa un tipo incompatible a remainingDistanceMeters',
        () {
      final initialPlan = RoutePlan(
        origin: origin,
        destination: destination,
        maneuvers: [step1],
        totalDistanceMeters: 1000.0,
        estimatedDuration: const Duration(minutes: 2),
      );

      expect(
        () =>
            initialPlan.copyWith(remainingDistanceMeters: 'distancia_invalida'),
        throwsA(isA<TypeError>()),
      );
    });

    test(
        'copyWith valida restricciones de dominio y lanza ArgumentError ante valores inválidos',
        () {
      final initialPlan = RoutePlan(
        origin: origin,
        destination: destination,
        maneuvers: [step1],
        totalDistanceMeters: 1000.0,
        estimatedDuration: const Duration(minutes: 2),
      );

      expect(
        () => initialPlan.copyWith(totalDistanceMeters: -50.0),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => initialPlan.copyWith(remainingDistanceMeters: -1.0),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => initialPlan.copyWith(remainingDistanceMeters: 5000.0),
        throwsA(isA<ArgumentError>()),
      );

      // copyWith() aplica la misma validación estricta
      expect(
        () => initialPlan.copyWith(remainingDistanceMeters: 1000.0),
        returnsNormally,
      );

      expect(
        () => initialPlan.copyWith(remainingDistanceMeters: 1000.0000000000001),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => initialPlan.copyWith(remainingDistanceMeters: 1001.0),
        throwsA(isA<ArgumentError>()),
      );
    });

    test(
        'rechaza estrictamente cualquier distancia restante mayor a la total sin tolerancias',
        () {
      // remainingDistanceMeters == totalDistanceMeters es válido
      expect(
        () => RoutePlan(
          origin: origin,
          destination: destination,
          maneuvers: [step1],
          totalDistanceMeters: 1000.0,
          estimatedDuration: const Duration(minutes: 2),
          remainingDistanceMeters: 1000.0,
        ),
        returnsNormally,
      );

      // Exceso mínimo representable como double distinto de 1000.0
      const smallExcess = 1000.0000000000001;
      expect(smallExcess > 1000.0, isTrue);
      expect(
        () => RoutePlan(
          origin: origin,
          destination: destination,
          maneuvers: [step1],
          totalDistanceMeters: 1000.0,
          estimatedDuration: const Duration(minutes: 2),
          remainingDistanceMeters: smallExcess,
        ),
        throwsA(isA<ArgumentError>()),
      );

      // Exceso de 1 metro (anterior tolerancia) ahora debe ser rechazado
      expect(
        () => RoutePlan(
          origin: origin,
          destination: destination,
          maneuvers: [step1],
          totalDistanceMeters: 1000.0,
          estimatedDuration: const Duration(minutes: 2),
          remainingDistanceMeters: 1001.0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('RoutePlan - Igualdad estructural y representación', () {
    test('planes de ruta idénticos son considerados iguales', () {
      final p1 = RoutePlan(
        origin: origin,
        destination: destination,
        maneuvers: [step1],
        geometry: [origin, destination],
        totalDistanceMeters: 1000.0,
        estimatedDuration: const Duration(minutes: 2),
      );

      final p2 = RoutePlan(
        origin: origin,
        destination: destination,
        maneuvers: [step1],
        geometry: [origin, destination],
        totalDistanceMeters: 1000.0,
        estimatedDuration: const Duration(minutes: 2),
      );

      expect(p1, equals(p2));
      expect(p1.hashCode, equals(p2.hashCode));
    });

    test(
        'toString retorna formato legible con distancia y cantidad de maniobras',
        () {
      final plan = RoutePlan(
        origin: origin,
        destination: destination,
        maneuvers: [step1],
        geometry: [origin, destination],
        totalDistanceMeters: 1000.0,
        estimatedDuration: const Duration(minutes: 2),
        remainingDistanceMeters: 800.0,
      );

      expect(plan.toString(), contains('RoutePlan('));
      expect(plan.toString(), contains('roadDist: 1000.0 m'));
      expect(plan.toString(), contains('remaining: 800.0 m'));
    });
  });
}
