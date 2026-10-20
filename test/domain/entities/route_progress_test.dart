import 'package:road_companion/road_companion.dart';
import 'package:test/test.dart';

void main() {
  final coord = Coordinates(4.7110, -74.0721);

  group('RouteProgress - Creación y validaciones de dominio', () {
    test('instancia correctamente un RouteProgress válido', () {
      final progress = RouteProgress(
        distanceTraveledMeters: 500.0,
        remainingDistanceMeters: 1500.0,
        progressPercentage: 25.0,
        projectedPoint: coord,
        distanceToRouteMeters: 12.5,
        closestSegmentIndex: 1,
      );

      expect(progress.distanceTraveledMeters, equals(500.0));
      expect(progress.remainingDistanceMeters, equals(1500.0));
      expect(progress.progressPercentage, equals(25.0));
      expect(progress.projectedPoint, equals(coord));
      expect(progress.distanceToRouteMeters, equals(12.5));
      expect(progress.closestSegmentIndex, equals(1));
    });

    test('acepta valores límite (0.0 y 100.0 %)', () {
      expect(
        () => RouteProgress(
          distanceTraveledMeters: 0.0,
          remainingDistanceMeters: 1000.0,
          progressPercentage: 0.0,
          projectedPoint: coord,
          distanceToRouteMeters: 0.0,
          closestSegmentIndex: 0,
        ),
        returnsNormally,
      );

      expect(
        () => RouteProgress(
          distanceTraveledMeters: 1000.0,
          remainingDistanceMeters: 0.0,
          progressPercentage: 100.0,
          projectedPoint: coord,
          distanceToRouteMeters: 0.0,
          closestSegmentIndex: 2,
        ),
        returnsNormally,
      );
    });

    test('rechaza métricas negativas', () {
      expect(
        () => RouteProgress(
          distanceTraveledMeters: -1.0,
          remainingDistanceMeters: 1000.0,
          progressPercentage: 0.0,
          projectedPoint: coord,
          distanceToRouteMeters: 0.0,
          closestSegmentIndex: 0,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'distanceTraveledMeters',
        )),
      );

      expect(
        () => RouteProgress(
          distanceTraveledMeters: 0.0,
          remainingDistanceMeters: -0.1,
          progressPercentage: 0.0,
          projectedPoint: coord,
          distanceToRouteMeters: 0.0,
          closestSegmentIndex: 0,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'remainingDistanceMeters',
        )),
      );

      expect(
        () => RouteProgress(
          distanceTraveledMeters: 0.0,
          remainingDistanceMeters: 1000.0,
          progressPercentage: -0.5,
          projectedPoint: coord,
          distanceToRouteMeters: 0.0,
          closestSegmentIndex: 0,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'progressPercentage',
        )),
      );

      expect(
        () => RouteProgress(
          distanceTraveledMeters: 0.0,
          remainingDistanceMeters: 1000.0,
          progressPercentage: 100.0001,
          projectedPoint: coord,
          distanceToRouteMeters: 0.0,
          closestSegmentIndex: 0,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'progressPercentage',
        )),
      );

      expect(
        () => RouteProgress(
          distanceTraveledMeters: 0.0,
          remainingDistanceMeters: 1000.0,
          progressPercentage: 0.0,
          projectedPoint: coord,
          distanceToRouteMeters: -5.0,
          closestSegmentIndex: 0,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'distanceToRouteMeters',
        )),
      );

      expect(
        () => RouteProgress(
          distanceTraveledMeters: 0.0,
          remainingDistanceMeters: 1000.0,
          progressPercentage: 0.0,
          projectedPoint: coord,
          distanceToRouteMeters: 0.0,
          closestSegmentIndex: -1,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'closestSegmentIndex',
        )),
      );
    });

    test('rechaza valores no finitos (NaN, Infinity, -Infinity)', () {
      final nonFiniteValues = [
        double.nan,
        double.infinity,
        double.negativeInfinity
      ];

      for (final val in nonFiniteValues) {
        expect(
          () => RouteProgress(
            distanceTraveledMeters: val,
            remainingDistanceMeters: 1000.0,
            progressPercentage: 0.0,
            projectedPoint: coord,
            distanceToRouteMeters: 0.0,
            closestSegmentIndex: 0,
          ),
          throwsA(isA<ArgumentError>()),
        );

        expect(
          () => RouteProgress(
            distanceTraveledMeters: 0.0,
            remainingDistanceMeters: val,
            progressPercentage: 0.0,
            projectedPoint: coord,
            distanceToRouteMeters: 0.0,
            closestSegmentIndex: 0,
          ),
          throwsA(isA<ArgumentError>()),
        );

        expect(
          () => RouteProgress(
            distanceTraveledMeters: 0.0,
            remainingDistanceMeters: 1000.0,
            progressPercentage: val,
            projectedPoint: coord,
            distanceToRouteMeters: 0.0,
            closestSegmentIndex: 0,
          ),
          throwsA(isA<ArgumentError>()),
        );

        expect(
          () => RouteProgress(
            distanceTraveledMeters: 0.0,
            remainingDistanceMeters: 1000.0,
            progressPercentage: 0.0,
            projectedPoint: coord,
            distanceToRouteMeters: val,
            closestSegmentIndex: 0,
          ),
          throwsA(isA<ArgumentError>()),
        );
      }
    });

    test(
        'rechaza trayecto de distancia total cero si el progreso no es 100.0 %',
        () {
      expect(
        () => RouteProgress(
          distanceTraveledMeters: 0.0,
          remainingDistanceMeters: 0.0,
          progressPercentage: 0.0,
          projectedPoint: coord,
          distanceToRouteMeters: 0.0,
          closestSegmentIndex: 0,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'progressPercentage',
        )),
      );

      expect(
        () => RouteProgress(
          distanceTraveledMeters: 0.0,
          remainingDistanceMeters: 0.0,
          progressPercentage: 50.0,
          projectedPoint: coord,
          distanceToRouteMeters: 0.0,
          closestSegmentIndex: 0,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'progressPercentage',
        )),
      );

      // Progreso 100.0 % en distancia total cero es válido
      expect(
        () => RouteProgress(
          distanceTraveledMeters: 0.0,
          remainingDistanceMeters: 0.0,
          progressPercentage: 100.0,
          projectedPoint: coord,
          distanceToRouteMeters: 0.0,
          closestSegmentIndex: 0,
        ),
        returnsNormally,
      );
    });

    test('rechaza suma acumulada de distancias no finita', () {
      expect(
        () => RouteProgress(
          distanceTraveledMeters: 1e308,
          remainingDistanceMeters: 1e308,
          progressPercentage: 50.0,
          projectedPoint: coord,
          distanceToRouteMeters: 0.0,
          closestSegmentIndex: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test(
        'acepta índices de segmento positivos sin acoplarse ni requerir conocer la geometría',
        () {
      expect(
        () => RouteProgress(
          distanceTraveledMeters: 500.0,
          remainingDistanceMeters: 500.0,
          progressPercentage: 50.0,
          projectedPoint: coord,
          distanceToRouteMeters: 1.0,
          closestSegmentIndex: 12500,
        ),
        returnsNormally,
      );
    });
  });

  group('RouteProgress - Coherencia categórica entre distancias y porcentaje',
      () {
    test('acepta combinaciones coherentes válidas', () {
      // 1. Inicio: recorrida 0, restante positiva, progreso 0%
      expect(
        () => RouteProgress(
          distanceTraveledMeters: 0.0,
          remainingDistanceMeters: 5000.0,
          progressPercentage: 0.0,
          projectedPoint: coord,
          distanceToRouteMeters: 0.0,
          closestSegmentIndex: 0,
        ),
        returnsNormally,
      );

      // 2. Destino: recorrida positiva, restante 0, progreso 100%
      expect(
        () => RouteProgress(
          distanceTraveledMeters: 5000.0,
          remainingDistanceMeters: 0.0,
          progressPercentage: 100.0,
          projectedPoint: coord,
          distanceToRouteMeters: 0.0,
          closestSegmentIndex: 5,
        ),
        returnsNormally,
      );

      // 3. Trayecto cero: recorrida 0, restante 0, progreso 100%
      expect(
        () => RouteProgress(
          distanceTraveledMeters: 0.0,
          remainingDistanceMeters: 0.0,
          progressPercentage: 100.0,
          projectedPoint: coord,
          distanceToRouteMeters: 0.0,
          closestSegmentIndex: 0,
        ),
        returnsNormally,
      );

      // 4. En curso: recorrida positiva, restante positiva, progreso en (0.0, 100.0)
      expect(
        () => RouteProgress(
          distanceTraveledMeters: 2500.0,
          remainingDistanceMeters: 2500.0,
          progressPercentage: 50.0,
          projectedPoint: coord,
          distanceToRouteMeters: 2.0,
          closestSegmentIndex: 2,
        ),
        returnsNormally,
      );

      expect(
        () => RouteProgress(
          distanceTraveledMeters: 10.0,
          remainingDistanceMeters: 990.0,
          progressPercentage: 1.0,
          projectedPoint: coord,
          distanceToRouteMeters: 0.5,
          closestSegmentIndex: 0,
        ),
        returnsNormally,
      );

      expect(
        () => RouteProgress(
          distanceTraveledMeters: 990.0,
          remainingDistanceMeters: 10.0,
          progressPercentage: 99.0,
          projectedPoint: coord,
          distanceToRouteMeters: 0.5,
          closestSegmentIndex: 1,
        ),
        returnsNormally,
      );
    });

    test('rechaza combinaciones incoherentes de inicio con progreso positivo',
        () {
      expect(
        () => RouteProgress(
          distanceTraveledMeters: 0.0,
          remainingDistanceMeters: 5000.0,
          progressPercentage: 0.1,
          projectedPoint: coord,
          distanceToRouteMeters: 0.0,
          closestSegmentIndex: 0,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'progressPercentage',
        )),
      );

      expect(
        () => RouteProgress(
          distanceTraveledMeters: 0.0,
          remainingDistanceMeters: 5000.0,
          progressPercentage: 100.0,
          projectedPoint: coord,
          distanceToRouteMeters: 0.0,
          closestSegmentIndex: 0,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'progressPercentage',
        )),
      );
    });

    test(
        'rechaza combinaciones incoherentes de arribo (restante 0) con progreso menor a 100%',
        () {
      expect(
        () => RouteProgress(
          distanceTraveledMeters: 5000.0,
          remainingDistanceMeters: 0.0,
          progressPercentage: 99.9,
          projectedPoint: coord,
          distanceToRouteMeters: 0.0,
          closestSegmentIndex: 3,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'progressPercentage',
        )),
      );

      expect(
        () => RouteProgress(
          distanceTraveledMeters: 5000.0,
          remainingDistanceMeters: 0.0,
          progressPercentage: 0.0,
          projectedPoint: coord,
          distanceToRouteMeters: 0.0,
          closestSegmentIndex: 3,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'progressPercentage',
        )),
      );
    });

    test(
        'rechaza combinaciones en curso (ambas distancias positivas) con progreso 0% o 100%',
        () {
      // Avance positivo no puede reportar 0%
      expect(
        () => RouteProgress(
          distanceTraveledMeters: 500.0,
          remainingDistanceMeters: 500.0,
          progressPercentage: 0.0,
          projectedPoint: coord,
          distanceToRouteMeters: 1.0,
          closestSegmentIndex: 1,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'progressPercentage',
        )),
      );

      // Distancia restante positiva no puede reportar 100%
      expect(
        () => RouteProgress(
          distanceTraveledMeters: 500.0,
          remainingDistanceMeters: 500.0,
          progressPercentage: 100.0,
          projectedPoint: coord,
          distanceToRouteMeters: 1.0,
          closestSegmentIndex: 1,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'progressPercentage',
        )),
      );
    });
  });

  group('RouteProgress - Igualdad estructural y representación', () {
    test('instancias con propiedades idénticas son equivalentes', () {
      final p1 = RouteProgress(
        distanceTraveledMeters: 250.0,
        remainingDistanceMeters: 750.0,
        progressPercentage: 25.0,
        projectedPoint: coord,
        distanceToRouteMeters: 5.0,
        closestSegmentIndex: 0,
      );

      final p2 = RouteProgress(
        distanceTraveledMeters: 250.0,
        remainingDistanceMeters: 750.0,
        progressPercentage: 25.0,
        projectedPoint: coord,
        distanceToRouteMeters: 5.0,
        closestSegmentIndex: 0,
      );

      expect(p1, equals(p2));
      expect(p1.hashCode, equals(p2.hashCode));
    });

    test('instancias con alguna propiedad distinta no son equivalentes', () {
      final base = RouteProgress(
        distanceTraveledMeters: 250.0,
        remainingDistanceMeters: 750.0,
        progressPercentage: 25.0,
        projectedPoint: coord,
        distanceToRouteMeters: 5.0,
        closestSegmentIndex: 0,
      );

      final diffTraveled = RouteProgress(
        distanceTraveledMeters: 260.0,
        remainingDistanceMeters: 750.0,
        progressPercentage: 25.0,
        projectedPoint: coord,
        distanceToRouteMeters: 5.0,
        closestSegmentIndex: 0,
      );

      expect(base, isNot(equals(diffTraveled)));
    });

    test('toString entrega información concisa y formateada', () {
      final progress = RouteProgress(
        distanceTraveledMeters: 250.0,
        remainingDistanceMeters: 750.0,
        progressPercentage: 25.0,
        projectedPoint: coord,
        distanceToRouteMeters: 5.0,
        closestSegmentIndex: 0,
      );

      expect(progress.toString(), contains('traveled: 250.0 m'));
      expect(progress.toString(), contains('remaining: 750.0 m'));
      expect(progress.toString(), contains('progress: 25.0%'));
      expect(progress.toString(), contains('seg: 0'));
      expect(progress.toString(), contains('crossTrack: 5.0 m'));
    });
  });
}
