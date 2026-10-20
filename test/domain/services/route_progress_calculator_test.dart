import 'package:road_companion/road_companion.dart';
import 'package:test/test.dart';

void main() {
  const calculator = RouteProgressCalculator();

  // Coordenadas base de prueba (Bogotá)
  final pA = Coordinates(4.6097, -74.0817); // Plaza de Bolívar
  final pB = Coordinates(4.6533, -74.0836); // Parque Simón Bolívar
  final pC = Coordinates(4.6980, -74.0850); // Titán Plaza
  final pD = Coordinates(4.7400, -74.0860); // Suba

  group('RouteProgressCalculator - Ruta recta: inicio, mitad y destino', () {
    final straightGeometry = [pA, pB];
    final totalGeom = pA.distanceTo(pB);

    test('posición en el inicio exacto reporta 0% de avance', () {
      final progress = calculator.calculate(
        geometry: straightGeometry,
        currentPosition: pA,
      );

      expect(progress.closestSegmentIndex, equals(0));
      expect(progress.projectedPoint, equals(pA));
      expect(progress.distanceToRouteMeters, equals(0.0));
      expect(progress.distanceTraveledMeters, equals(0.0));
      expect(progress.remainingDistanceMeters, closeTo(totalGeom, 0.001));
      expect(progress.progressPercentage, equals(0.0));
    });

    test('posición en la mitad exacta reporta 50% de avance', () {
      final midPoint = Coordinates(
        (pA.latitude + pB.latitude) / 2.0,
        (pA.longitude + pB.longitude) / 2.0,
      );

      final progress = calculator.calculate(
        geometry: straightGeometry,
        currentPosition: midPoint,
      );

      expect(progress.closestSegmentIndex, equals(0));
      expect(progress.distanceToRouteMeters, closeTo(0.0, 0.01));
      expect(progress.distanceTraveledMeters, closeTo(totalGeom / 2.0, 1.0));
      expect(progress.remainingDistanceMeters, closeTo(totalGeom / 2.0, 1.0));
      expect(progress.progressPercentage, closeTo(50.0, 0.1));
    });

    test('posición en el destino exacto reporta 100% de avance', () {
      final progress = calculator.calculate(
        geometry: straightGeometry,
        currentPosition: pB,
      );

      expect(progress.closestSegmentIndex, equals(0));
      expect(progress.projectedPoint, equals(pB));
      expect(progress.distanceToRouteMeters, equals(0.0));
      expect(progress.distanceTraveledMeters, closeTo(totalGeom, 0.001));
      expect(progress.remainingDistanceMeters, equals(0.0));
      expect(progress.progressPercentage, equals(100.0));
    });
  });

  group('RouteProgressCalculator - Varios segmentos y giros reales', () {
    // Ruta en "L": pA -> pB (norte) -> pC_east (este)
    final pcEast = Coordinates(pB.latitude, pB.longitude + 0.05);
    final multiGeometry = [pA, pB, pcEast];
    final seg0Len = pA.distanceTo(pB);
    final seg1Len = pB.distanceTo(pcEast);
    final totalGeom = seg0Len + seg1Len;

    test(
      'la distancia restante sigue la geometría real de carretera y no Haversine directo',
      () {
        // Posición a 1/4 del segmento 0
        final quarterPoint = Coordinates(
          pA.latitude + 0.25 * (pB.latitude - pA.latitude),
          pA.longitude + 0.25 * (pB.longitude - pA.longitude),
        );

        final progress = calculator.calculate(
          geometry: multiGeometry,
          currentPosition: quarterPoint,
        );

        final directHaversineToDest = quarterPoint.distanceTo(pcEast);

        // La distancia restante por carretera debe ser la suma del tramo restante del segmento 0 más el segmento 1
        expect(
          progress.remainingDistanceMeters,
          greaterThan(directHaversineToDest),
        );
        expect(
          progress.distanceTraveledMeters + progress.remainingDistanceMeters,
          closeTo(totalGeom, 0.01),
        );
      },
    );

    test(
      'en el vértice de giro (pB) la distancia restante es exactamente la longitud del segmento final',
      () {
        final progress = calculator.calculate(
          geometry: multiGeometry,
          currentPosition: pB,
        );

        expect(progress.closestSegmentIndex, equals(0));
        expect(progress.distanceTraveledMeters, closeTo(seg0Len, 0.01));
        expect(progress.remainingDistanceMeters, closeTo(seg1Len, 0.01));
        expect(
          progress.progressPercentage,
          closeTo((seg0Len / totalGeom) * 100.0, 0.01),
        );
      },
    );
  });

  group('RouteProgressCalculator - Posición fuera de la ruta', () {
    final straightGeometry = [pA, pB];

    test(
      'proyecta ortogonalmente sobre la calzada y reporta la distancia de desvío',
      () {
        // Punto situado al este de la mitad de la ruta
        final midPoint = Coordinates(
          (pA.latitude + pB.latitude) / 2.0,
          (pA.longitude + pB.longitude) / 2.0,
        );
        // Desplazamiento de ~50 m al este
        final offRoutePosition = Coordinates(
          midPoint.latitude,
          midPoint.longitude + 0.0005,
        );

        final progress = calculator.calculate(
          geometry: straightGeometry,
          currentPosition: offRoutePosition,
        );

        // La proyección debe caer sobre la calzada (muy cerca del midPoint original)
        expect(
          progress.projectedPoint.latitude,
          closeTo(midPoint.latitude, 0.0001),
        );
        expect(
          progress.projectedPoint.longitude,
          closeTo(midPoint.longitude, 0.0001),
        );
        expect(progress.distanceToRouteMeters, greaterThan(30.0));
        expect(progress.distanceToRouteMeters, lessThan(70.0));

        // El progreso se calcula desde el punto proyectado sobre la calzada
        expect(progress.progressPercentage, closeTo(50.0, 1.0));
      },
    );
  });

  group(
    'RouteProgressCalculator - Segmentos consecutivos de longitud cero',
    () {
      test(
        'maneja puntos consecutivos idénticos sin división por cero ni NaN',
        () {
          final geometryWithDuplicates = [pA, pB, pB, pB, pC];

          final progress = calculator.calculate(
            geometry: geometryWithDuplicates,
            currentPosition: pB,
          );

          expect(progress.distanceTraveledMeters.isNaN, isFalse);
          expect(progress.remainingDistanceMeters.isNaN, isFalse);
          expect(progress.progressPercentage.isNaN, isFalse);
          expect(progress.distanceToRouteMeters.isNaN, isFalse);
          expect(progress.progressPercentage, inInclusiveRange(0.0, 100.0));
        },
      );
    },
  );

  group(
    'RouteProgressCalculator - Validación de rutas inválidas y límites de puntos',
    () {
      test('rechaza geometría vacía con ArgumentError', () {
        expect(
          () => calculator.calculate(geometry: [], currentPosition: pA),
          throwsA(
            isA<ArgumentError>().having((e) => e.name, 'name', 'geometry'),
          ),
        );
      });

      test('rechaza geometría de un solo punto con ArgumentError', () {
        expect(
          () => calculator.calculate(geometry: [pA], currentPosition: pA),
          throwsA(
            isA<ArgumentError>().having((e) => e.name, 'name', 'geometry'),
          ),
        );
      });

      test('rechaza totalDistanceMeters negativo o no finito', () {
        final validGeom = [pA, pB];

        expect(
          () => calculator.calculate(
            geometry: validGeom,
            currentPosition: pA,
            totalDistanceMeters: -1.0,
          ),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.name,
              'name',
              'totalDistanceMeters',
            ),
          ),
        );

        expect(
          () => calculator.calculate(
            geometry: validGeom,
            currentPosition: pA,
            totalDistanceMeters: double.nan,
          ),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.name,
              'name',
              'totalDistanceMeters',
            ),
          ),
        );

        expect(
          () => calculator.calculate(
            geometry: validGeom,
            currentPosition: pA,
            totalDistanceMeters: double.infinity,
          ),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.name,
              'name',
              'totalDistanceMeters',
            ),
          ),
        );
      });

      test(
        'rechaza coordenadas no finitas o fuera de rango antes de calcular',
        () {
          expect(
            () => Coordinates(150.0, 0.0),
            throwsA(
              isA<ArgumentError>().having((e) => e.name, 'name', 'latitude'),
            ),
          );

          expect(
            () => Coordinates(0.0, double.nan),
            throwsA(
              isA<ArgumentError>().having((e) => e.name, 'name', 'longitude'),
            ),
          );

          expect(
            () => Coordinates(0.0, 185.0),
            throwsA(
              isA<ArgumentError>().having((e) => e.name, 'name', 'longitude'),
            ),
          );
        },
      );

      test(
        'valida lastKnownSegmentIndex: rechaza negativos o superiores a geometry.length - 2 y acepta extremos válidos',
        () {
          final validGeom = [
            pA,
            pB,
            pC,
            pD,
          ]; // 3 segmentos: índices 0, 1 y 2. geometry.length - 2 = 2

          // Rechaza índice negativo (< 0)
          expect(
            () => calculator.calculate(
              geometry: validGeom,
              currentPosition: pA,
              lastKnownSegmentIndex: -1,
            ),
            throwsA(
              isA<ArgumentError>().having(
                (e) => e.name,
                'name',
                'lastKnownSegmentIndex',
              ),
            ),
          );

          // Rechaza índice superior a geometry.length - 2 (en este caso 3)
          expect(
            () => calculator.calculate(
              geometry: validGeom,
              currentPosition: pA,
              lastKnownSegmentIndex: 3,
            ),
            throwsA(
              isA<ArgumentError>().having(
                (e) => e.name,
                'name',
                'lastKnownSegmentIndex',
              ),
            ),
          );

          // Rechaza índice muy superior
          expect(
            () => calculator.calculate(
              geometry: validGeom,
              currentPosition: pA,
              lastKnownSegmentIndex: 99,
            ),
            throwsA(
              isA<ArgumentError>().having(
                (e) => e.name,
                'name',
                'lastKnownSegmentIndex',
              ),
            ),
          );

          // Acepta índice mínimo válido (0)
          expect(
            () => calculator.calculate(
              geometry: validGeom,
              currentPosition: pA,
              lastKnownSegmentIndex: 0,
            ),
            returnsNormally,
          );

          // Acepta índice máximo válido (geometry.length - 2, que es 2)
          final progressAtEnd = calculator.calculate(
            geometry: validGeom,
            currentPosition: pD,
            lastKnownSegmentIndex: 2,
          );
          expect(progressAtEnd.closestSegmentIndex, equals(2));
        },
      );
    },
  );

  group('RouteProgressCalculator - Rutas degeneradas de longitud total cero', () {
    test(
      'ruta de dos puntos idénticos entrega progreso completado 100% y 0 restante',
      () {
        final zeroLengthGeometry = [pA, pA];

        final progress = calculator.calculate(
          geometry: zeroLengthGeometry,
          currentPosition: pA,
        );

        expect(progress.distanceTraveledMeters, equals(0.0));
        expect(progress.remainingDistanceMeters, equals(0.0));
        expect(progress.progressPercentage, equals(100.0));
        expect(progress.distanceToRouteMeters, equals(0.0));
        expect(progress.projectedPoint, equals(pA));
        expect(progress.closestSegmentIndex, equals(0));
      },
    );

    test(
      'ruta con totalDistanceMeters = 0.0 explícito entrega 100% de progreso',
      () {
        final validGeom = [pA, pB];

        final progress = calculator.calculate(
          geometry: validGeom,
          currentPosition: pA,
          totalDistanceMeters: 0.0,
        );

        expect(progress.distanceTraveledMeters, equals(0.0));
        expect(progress.remainingDistanceMeters, equals(0.0));
        expect(progress.progressPercentage, equals(100.0));
      },
    );

    test(
      'rechaza con ArgumentError geometría de puntos coincidentes (distancia geométrica 0.0 m) cuando totalDistanceMeters > 0.0',
      () {
        final zeroGeom = [pA, pA];

        expect(
          () => calculator.calculate(
            geometry: zeroGeom,
            currentPosition: pA,
            totalDistanceMeters: 1500.0,
          ),
          throwsA(
            isA<ArgumentError>().having((e) => e.name, 'name', 'geometry'),
          ),
        );
      },
    );

    test(
      'rechaza con ArgumentError múltiples puntos coincidentes cuando totalDistanceMeters > 0.0',
      () {
        final multiZeroGeom = [pA, pA, pA];

        expect(
          () => calculator.calculate(
            geometry: multiZeroGeom,
            currentPosition: pA,
            totalDistanceMeters: 500.0,
          ),
          throwsA(
            isA<ArgumentError>().having((e) => e.name, 'name', 'geometry'),
          ),
        );
      },
    );

    test(
      'calculateForRoutePlan rechaza con ArgumentError si el plan tiene geometría de puntos coincidentes y totalDistanceMeters > 0',
      () {
        final plan = RoutePlan(
          origin: pA,
          destination: pA,
          geometry: [pA, pA],
          totalDistanceMeters: 1200.0,
          estimatedDuration: const Duration(minutes: 5),
          maneuvers: [
            Maneuver(
              instructionText: 'Punto de inicio',
              type: ManeuverType.depart,
              location: pA,
            ),
          ],
        );

        expect(
          () => calculator.calculateForRoutePlan(
            routePlan: plan,
            currentPosition: pA,
          ),
          throwsA(
            isA<ArgumentError>().having((e) => e.name, 'name', 'geometry'),
          ),
        );
      },
    );
  });

  group(
    'RouteProgressCalculator - Límites de porcentaje y coherencia matemática',
    () {
      final straightGeometry = [pA, pB];
      final totalGeom = pA.distanceTo(pB);

      test(
        'posición situada antes del inicio se acota al 0% sin valores negativos',
        () {
          // Punto hacia el sur antes del origen pA
          final beforeOrigin = Coordinates(pA.latitude - 0.05, pA.longitude);

          final progress = calculator.calculate(
            geometry: straightGeometry,
            currentPosition: beforeOrigin,
          );

          expect(progress.progressPercentage, equals(0.0));
          expect(progress.distanceTraveledMeters, equals(0.0));
          expect(progress.remainingDistanceMeters, closeTo(totalGeom, 0.001));
          expect(progress.projectedPoint, equals(pA));
          expect(progress.distanceToRouteMeters, greaterThan(0.0));
        },
      );

      test(
        'posición situada después del destino se acota al 100% sin sobrepasar la ruta',
        () {
          // Punto hacia el norte más allá del destino pB
          final pastDestination = Coordinates(pB.latitude + 0.05, pB.longitude);

          final progress = calculator.calculate(
            geometry: straightGeometry,
            currentPosition: pastDestination,
          );

          expect(progress.progressPercentage, equals(100.0));
          expect(progress.distanceTraveledMeters, closeTo(totalGeom, 0.001));
          expect(progress.remainingDistanceMeters, equals(0.0));
          expect(progress.projectedPoint, equals(pB));
          expect(progress.distanceToRouteMeters, greaterThan(0.0));
        },
      );

      test(
        'coherencia numérica: distanceTraveledMeters + remainingDistanceMeters converge a totalDistance con tolerancia explícita',
        () {
          const customTotal = 12500.0;
          final multiGeom = [pA, pB, pC, pD];

          // Probar en 10 puntos arbitrarios
          for (double frac = 0.0; frac <= 1.0; frac += 0.1) {
            final pos = Coordinates(
              pA.latitude + frac * (pD.latitude - pA.latitude),
              pA.longitude + frac * (pD.longitude - pA.longitude),
            );

            final progress = calculator.calculate(
              geometry: multiGeom,
              currentPosition: pos,
              totalDistanceMeters: customTotal,
            );

            expect(
              progress.distanceTraveledMeters +
                  progress.remainingDistanceMeters,
              closeTo(customTotal, 0.0001),
            );
            expect(progress.progressPercentage, inInclusiveRange(0.0, 100.0));
            expect(
              progress.remainingDistanceMeters,
              lessThanOrEqualTo(customTotal),
            );
          }
        },
      );
    },
  );

  group(
    'RouteProgressCalculator - Coherencia con diversas escalas de totalDistanceMeters',
    () {
      final straightGeometry = [pA, pB];
      final midPoint = Coordinates(
        (pA.latitude + pB.latitude) / 2.0,
        (pA.longitude + pB.longitude) / 2.0,
      );

      // Escalas de prueba: muy pequeñas, estándar y muy grandes
      final testDistances = [
        0.001, // 1 milímetro
        0.05, // 5 centímetros
        1.0, // 1 metro
        50.0, // 50 metros
        1000.0, // 1 km
        42195.0, // Maratón (~42.2 km)
        1200000.0, // 1.200 km
        10000000.0, // 10.000 km
        1000000000.0, // 1 millón de km
      ];

      for (final total in testDistances) {
        test(
          'escala totalDistanceMeters = $total m mantiene invariantes y coherencia',
          () {
            // 1. En el inicio exacto
            final atStart = calculator.calculate(
              geometry: straightGeometry,
              currentPosition: pA,
              totalDistanceMeters: total,
            );
            expect(atStart.distanceTraveledMeters, equals(0.0));
            expect(atStart.remainingDistanceMeters, equals(total));
            expect(atStart.progressPercentage, equals(0.0));
            expect(atStart.remainingDistanceMeters, lessThanOrEqualTo(total));

            // 2. En el punto medio
            final atMid = calculator.calculate(
              geometry: straightGeometry,
              currentPosition: midPoint,
              totalDistanceMeters: total,
            );
            expect(atMid.progressPercentage, closeTo(50.0, 0.1));
            expect(
              atMid.distanceTraveledMeters,
              closeTo(total / 2.0, total * 0.01),
            );
            expect(
              atMid.remainingDistanceMeters,
              closeTo(total / 2.0, total * 0.01),
            );
            expect(atMid.remainingDistanceMeters, lessThanOrEqualTo(total));
            expect(
              atMid.distanceTraveledMeters + atMid.remainingDistanceMeters,
              closeTo(total, total * 1e-9 + 1e-6),
            );

            // 3. En el destino exacto
            final atEnd = calculator.calculate(
              geometry: straightGeometry,
              currentPosition: pB,
              totalDistanceMeters: total,
            );
            expect(atEnd.distanceTraveledMeters, equals(total));
            expect(atEnd.remainingDistanceMeters, equals(0.0));
            expect(atEnd.progressPercentage, equals(100.0));
            expect(atEnd.remainingDistanceMeters, lessThanOrEqualTo(total));
          },
        );
      }

      test(
        'coherencia proporcional continua estricta entre porcentaje y distancias en múltiples puntos de ruta',
        () {
          final multiGeom = [pA, pB, pC, pD];
          const customTotal = 35000.0;

          // Evaluar 20 posiciones progresivas a lo largo de la ruta
          for (double frac = 0.0; frac <= 1.0; frac += 0.05) {
            final pos = Coordinates(
              pA.latitude + frac * (pD.latitude - pA.latitude),
              pA.longitude + frac * (pD.longitude - pA.longitude),
            );

            final progress = calculator.calculate(
              geometry: multiGeom,
              currentPosition: pos,
              totalDistanceMeters: customTotal,
            );

            final sumDist =
                progress.distanceTraveledMeters +
                progress.remainingDistanceMeters;
            expect(sumDist, closeTo(customTotal, 0.001));

            // Proporción matemática derivada de las distancias
            final derivedRatio =
                (progress.distanceTraveledMeters / sumDist) * 100.0;

            // Debe coincidir con progressPercentage dentro de la precisión numérica IEEE 754
            expect(progress.progressPercentage, closeTo(derivedRatio, 1e-6));
          }
        },
      );
    },
  );

  group(
    'RouteProgressCalculator - Ambigüedad y segmentos candidatos (lazos / cruces)',
    () {
      // Ruta en lazo que se cruza en pB: pA -> pB -> pC -> pB -> pD
      final loopGeometry = [pA, pB, pC, pB, pD];
      // Segmento 0: pA -> pB
      // Segmento 1: pB -> pC
      // Segmento 2: pC -> pB
      // Segmento 3: pB -> pD

      test(
        'en una intersección exacta, el cálculo sin estado selecciona deterministamente el primer tramo',
        () {
          final progress = calculator.calculate(
            geometry: loopGeometry,
            currentPosition: pB,
          );

          // Determinismo: selecciona el segmento 0 evitando saltos prematuros
          expect(progress.closestSegmentIndex, equals(0));
          expect(progress.projectedPoint, equals(pB));
        },
      );

      test(
        'cuando se suministra lastKnownSegmentIndex, respeta el avance de navegación hacia adelante',
        () {
          final progress = calculator.calculate(
            geometry: loopGeometry,
            currentPosition: pB,
            lastKnownSegmentIndex:
                2, // El vehículo ya transitó el bucle pB -> pC -> pB
          );

          // Ahora debe asociar al segmento 2 (o 3) que corresponde al segundo paso por pB
          expect(progress.closestSegmentIndex, equals(2));
          expect(progress.projectedPoint, equals(pB));
          expect(
            progress.distanceTraveledMeters,
            greaterThan(pA.distanceTo(pB)),
          );
        },
      );
    },
  );

  group(
    'RouteProgressCalculator - Integración y validación estricta con RoutePlan',
    () {
      final step1 = Maneuver(
        type: ManeuverType.depart,
        instructionText: 'Salida',
        location: pA,
      );

      final step2 = Maneuver(
        type: ManeuverType.arrive,
        instructionText: 'Llegada',
        location: pC,
      );

      test(
        'los resultados calculados son estrictamente compatibles con copyWithRemainingDistance de RoutePlan',
        () {
          final routePlan = RoutePlan(
            origin: pA,
            destination: pC,
            maneuvers: [step1, step2],
            geometry: [pA, pB, pC],
            totalDistanceMeters: 10000.0,
            estimatedDuration: const Duration(minutes: 20),
          );

          // Evaluar en varios puntos a lo largo de la ruta
          final testPositions = [
            pA,
            Coordinates(pA.latitude - 0.01, pA.longitude), // Antes del origen
            Coordinates(
              (pA.latitude + pB.latitude) / 2.0,
              (pA.longitude + pB.longitude) / 2.0,
            ),
            pB,
            Coordinates(
              (pB.latitude + pC.latitude) / 2.0,
              (pB.longitude + pC.longitude) / 2.0,
            ),
            pC,
            Coordinates(
              pC.latitude + 0.01,
              pC.longitude,
            ), // Más allá del destino
          ];

          for (final pos in testPositions) {
            final progress = calculator.calculateForRoutePlan(
              routePlan: routePlan,
              currentPosition: pos,
            );

            // La validación estricta de RoutePlan (remaining <= total) NUNCA debe fallar
            expect(
              progress.remainingDistanceMeters,
              lessThanOrEqualTo(routePlan.totalDistanceMeters),
            );
            expect(
              () => routePlan.copyWithRemainingDistance(
                progress.remainingDistanceMeters,
              ),
              returnsNormally,
            );
            expect(
              () => routePlan.copyWith(
                remainingDistanceMeters: progress.remainingDistanceMeters,
              ),
              returnsNormally,
            );
          }
        },
      );

      test(
        'coherencia estricta cuando la distancia del proveedor es mayor o menor que la distancia geométrica',
        () {
          // Geometría mide ~14.5 km
          final multiGeom = [pA, pB, pC, pD];
          final geomDistance = calculator
              .calculate(geometry: multiGeom, currentPosition: pD)
              .distanceTraveledMeters;

          // Proveedor 1: distancia mayor (considera curvas internas no muestreadas)
          final providerHigher = geomDistance * 1.10;
          final progHigher = calculator.calculate(
            geometry: multiGeom,
            currentPosition: pB,
            totalDistanceMeters: providerHigher,
          );
          expect(
            progHigher.remainingDistanceMeters,
            lessThanOrEqualTo(providerHigher),
          );
          expect(
            progHigher.distanceTraveledMeters +
                progHigher.remainingDistanceMeters,
            closeTo(providerHigher, 0.001),
          );

          // Proveedor 2: distancia menor
          final providerLower = geomDistance * 0.90;
          final progLower = calculator.calculate(
            geometry: multiGeom,
            currentPosition: pB,
            totalDistanceMeters: providerLower,
          );
          expect(
            progLower.remainingDistanceMeters,
            lessThanOrEqualTo(providerLower),
          );
          expect(
            progLower.distanceTraveledMeters +
                progLower.remainingDistanceMeters,
            closeTo(providerLower, 0.001),
          );
        },
      );
    },
  );

  group('RouteProgressCalculator - Cruce del antimeridiano (+180° / -180°)', () {
    // Tramo que cruza de 179° Este a -179° Oeste (longitud de 2 grados en el ecuador)
    final pEast = Coordinates(0.0, 179.0);
    final pWest = Coordinates(0.0, -179.0);
    final antimeridianGeom = [pEast, pWest];
    final segDistance = pEast.distanceTo(pWest); // ~222.39 km

    test(
      'proyecta e interpola correctamente al cruzar de este a oeste (+179 a -179)',
      () {
        // Posición a 75% del tramo (longitud -179.5), desplazada 0.001° al norte (~111.3 m)
        final pos = Coordinates(0.001, -179.5);

        final progress = calculator.calculate(
          geometry: antimeridianGeom,
          currentPosition: pos,
        );

        // La coordenada proyectada debe caer en el antimeridiano y en rango válido [-180, 180]
        expect(progress.projectedPoint.latitude, closeTo(0.0, 0.0001));
        expect(progress.projectedPoint.longitude, closeTo(-179.5, 0.0001));
        expect(progress.projectedPoint.longitude, greaterThanOrEqualTo(-180.0));
        expect(progress.projectedPoint.longitude, lessThanOrEqualTo(180.0));

        expect(progress.distanceToRouteMeters, closeTo(111.3, 2.0));
        expect(progress.progressPercentage, closeTo(75.0, 0.5));
        expect(
          progress.distanceTraveledMeters,
          closeTo(segDistance * 0.75, 100.0),
        );
        expect(
          progress.remainingDistanceMeters,
          closeTo(segDistance * 0.25, 100.0),
        );
      },
    );

    test(
      'proyecta e interpola correctamente al cruzar de oeste a este (-179 a +179)',
      () {
        final reverseGeom = [pWest, pEast];

        // Posición a 75% del tramo en sentido inverso (longitud +179.5)
        final pos = Coordinates(0.001, 179.5);

        final progress = calculator.calculate(
          geometry: reverseGeom,
          currentPosition: pos,
        );

        expect(progress.projectedPoint.latitude, closeTo(0.0, 0.0001));
        expect(progress.projectedPoint.longitude, closeTo(179.5, 0.0001));
        expect(progress.distanceToRouteMeters, closeTo(111.3, 2.0));
        expect(progress.progressPercentage, closeTo(75.0, 0.5));
      },
    );
  });

  group('RouteProgressCalculator - maxSegmentLookahead y prevención de saltos', () {
    // 5 segmentos consecutivos
    final pE = Coordinates(4.7800, -74.0870);
    final pF = Coordinates(4.8200, -74.0880);
    final longRoute = [pA, pB, pC, pD, pE, pF];

    test('rechaza maxSegmentLookahead negativo', () {
      expect(
        () => calculator.calculate(
          geometry: longRoute,
          currentPosition: pA,
          maxSegmentLookahead: -1,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.name,
            'name',
            'maxSegmentLookahead',
          ),
        ),
      );
    });

    test(
      'maxSegmentLookahead acota la búsqueda y previene saltos a tramos distantes',
      () {
        // Si el vehículo está físicamente en pA pero una posición anómala está cerca de pF
        // Con lastKnownSegmentIndex = 0 y maxSegmentLookahead = 1, solo evalúa segmentos 0 y 1
        final progressLimited = calculator.calculate(
          geometry: longRoute,
          currentPosition: pF,
          lastKnownSegmentIndex: 0,
          maxSegmentLookahead: 1,
        );

        // No puede saltar al segmento 4 (pF) porque la ventana solo permite 0 y 1
        expect(progressLimited.closestSegmentIndex, lessThanOrEqualTo(1));
      },
    );

    test(
      'cuando maxSegmentLookahead es null, evalúa toda la ruta sin restringir saltos a tramos lejanos más cercanos',
      () {
        // Con lastKnownSegmentIndex = 0 y maxSegmentLookahead = null (por defecto):
        // Si la posición está en pF (al final), el cálculo evalúa toda la ruta
        // y selecciona el segmento 4 por proximidad geométrica estricta.
        final progressUnbounded = calculator.calculate(
          geometry: longRoute,
          currentPosition: pF,
          lastKnownSegmentIndex: 0,
          maxSegmentLookahead: null,
        );

        expect(progressUnbounded.closestSegmentIndex, equals(4));
      },
    );
  });

  group(
    'RouteProgressCalculator - Segmentos degenerados, vértices y compatibilidad con RoutePlan',
    () {
      // Helper para verificar compatibilidad estricta con RoutePlan
      void verifyRoutePlanCompatibility({
        required List<Coordinates> geometry,
        required double totalDistanceMeters,
        required RouteProgress progress,
      }) {
        // 1. Debe poder instanciarse un RoutePlan válido con la distancia restante calculada
        final plan = RoutePlan(
          origin: geometry.first,
          destination: geometry.last,
          geometry: geometry,
          totalDistanceMeters: totalDistanceMeters,
          remainingDistanceMeters: progress.remainingDistanceMeters,
          estimatedDuration: const Duration(minutes: 15),
          maneuvers: [
            Maneuver(
              instructionText: 'Salida de prueba',
              type: ManeuverType.depart,
              location: geometry.first,
            ),
          ],
        );

        // 2. copyWithRemainingDistance debe funcionar sin arrojar ArgumentError
        final updatedPlan = plan.copyWithRemainingDistance(
          progress.remainingDistanceMeters,
        );
        expect(
          updatedPlan.remainingDistanceMeters,
          equals(progress.remainingDistanceMeters),
        );
        expect(
          updatedPlan.remainingDistanceMeters,
          lessThanOrEqualTo(updatedPlan.totalDistanceMeters),
        );
      }

      test(
        'geometría [A, A, B]: posición en A selecciona tramo 0 por desempate determinista, reporta 0% y es compatible con RoutePlan',
        () {
          final geomAAB = [pA, pA, pB];
          final totalGeom = pA.distanceTo(pB);

          final progressAtA = calculator.calculate(
            geometry: geomAAB,
            currentPosition: pA,
          );

          // Segmento 0 [A, A] y segmento 1 [A, B] ambos tienen distancia 0.0 m a pA.
          // El desempate determinista estricto (<) preserva el tramo más temprano: índice 0.
          expect(progressAtA.closestSegmentIndex, equals(0));
          expect(progressAtA.projectedPoint, equals(pA));
          expect(progressAtA.distanceToRouteMeters, equals(0.0));
          expect(progressAtA.distanceTraveledMeters, equals(0.0));
          expect(
            progressAtA.remainingDistanceMeters,
            closeTo(totalGeom, 0.001),
          );
          expect(progressAtA.progressPercentage, equals(0.0));

          // Verificación de invariantes de RouteProgress
          expect(progressAtA.distanceTraveledMeters == 0.0, isTrue);
          expect(progressAtA.remainingDistanceMeters > 0.0, isTrue);
          expect(progressAtA.progressPercentage == 0.0, isTrue);

          verifyRoutePlanCompatibility(
            geometry: geomAAB,
            totalDistanceMeters: totalGeom,
            progress: progressAtA,
          );
        },
      );

      test(
        'geometría [A, A, B]: posición en B selecciona tramo 1, reporta 100% y es compatible con RoutePlan',
        () {
          final geomAAB = [pA, pA, pB];
          final totalGeom = pA.distanceTo(pB);

          final progressAtB = calculator.calculate(
            geometry: geomAAB,
            currentPosition: pB,
          );

          // Segmento 0 [A, A] está a distance(A, B) de B, mientras que segmento 1 [A, B] proyecta a B con distancia 0.0 m.
          // Por ende, la menor distancia selecciona deterministamente el índice 1.
          expect(progressAtB.closestSegmentIndex, equals(1));
          expect(progressAtB.projectedPoint, equals(pB));
          expect(progressAtB.distanceToRouteMeters, equals(0.0));
          expect(progressAtB.distanceTraveledMeters, closeTo(totalGeom, 0.001));
          expect(progressAtB.remainingDistanceMeters, equals(0.0));
          expect(progressAtB.progressPercentage, equals(100.0));

          // Verificación de invariantes de RouteProgress
          expect(progressAtB.distanceTraveledMeters > 0.0, isTrue);
          expect(progressAtB.remainingDistanceMeters == 0.0, isTrue);
          expect(progressAtB.progressPercentage == 100.0, isTrue);

          verifyRoutePlanCompatibility(
            geometry: geomAAB,
            totalDistanceMeters: totalGeom,
            progress: progressAtB,
          );
        },
      );

      test(
        'geometría [A, B, B]: posición en A selecciona tramo 0, reporta 0% y es compatible con RoutePlan',
        () {
          final geomABB = [pA, pB, pB];
          final totalGeom = pA.distanceTo(pB);

          final progressAtA = calculator.calculate(
            geometry: geomABB,
            currentPosition: pA,
          );

          // Segmento 0 [A, B] proyecta a A con distancia 0.0 m; segmento 1 [B, B] está a distance(A, B).
          expect(progressAtA.closestSegmentIndex, equals(0));
          expect(progressAtA.projectedPoint, equals(pA));
          expect(progressAtA.distanceToRouteMeters, equals(0.0));
          expect(progressAtA.distanceTraveledMeters, equals(0.0));
          expect(
            progressAtA.remainingDistanceMeters,
            closeTo(totalGeom, 0.001),
          );
          expect(progressAtA.progressPercentage, equals(0.0));

          verifyRoutePlanCompatibility(
            geometry: geomABB,
            totalDistanceMeters: totalGeom,
            progress: progressAtA,
          );
        },
      );

      test(
        'geometría [A, B, B]: posición en B selecciona tramo 0 por desempate determinista (<), reporta 100% y es compatible con RoutePlan',
        () {
          final geomABB = [pA, pB, pB];
          final totalGeom = pA.distanceTo(pB);

          final progressAtB = calculator.calculate(
            geometry: geomABB,
            currentPosition: pB,
          );

          // Ambos tramos (segmento 0 con t=1.0 y segmento 1 con t=0.0) tienen distancia ortogonal 0.0 m hacia B.
          // La regla estricta de desempate (<) no presupone que el vértice final deba seleccionar
          // el segmento degenerado posterior, preservando deterministamente el tramo 0.
          expect(progressAtB.closestSegmentIndex, equals(0));
          expect(progressAtB.projectedPoint, equals(pB));
          expect(progressAtB.distanceToRouteMeters, equals(0.0));
          // El segmento 0 en B (t=1.0) acumula el 100% de la longitud geométrica
          expect(progressAtB.distanceTraveledMeters, closeTo(totalGeom, 0.001));
          expect(progressAtB.remainingDistanceMeters, equals(0.0));
          expect(progressAtB.progressPercentage, equals(100.0));

          verifyRoutePlanCompatibility(
            geometry: geomABB,
            totalDistanceMeters: totalGeom,
            progress: progressAtB,
          );
        },
      );

      test(
        'geometría con todos los puntos coincidentes y distancia total efectiva cero reporta arribo (100%) y es compatible con RoutePlan',
        () {
          final allCoincidentGeom = [pA, pA, pA];

          // Caso A: con totalDistanceMeters = 0.0 explícito en la posición exacta
          final progressExact = calculator.calculate(
            geometry: allCoincidentGeom,
            currentPosition: pA,
            totalDistanceMeters: 0.0,
          );

          expect(progressExact.closestSegmentIndex, equals(0));
          expect(progressExact.projectedPoint, equals(pA));
          expect(progressExact.distanceToRouteMeters, equals(0.0));
          expect(progressExact.distanceTraveledMeters, equals(0.0));
          expect(progressExact.remainingDistanceMeters, equals(0.0));
          expect(progressExact.progressPercentage, equals(100.0));

          verifyRoutePlanCompatibility(
            geometry: allCoincidentGeom,
            totalDistanceMeters: 0.0,
            progress: progressExact,
          );

          // Caso B: con totalDistanceMeters = null (distancia geométrica total 0.0 efectiva)
          final progressNullTotal = calculator.calculate(
            geometry: allCoincidentGeom,
            currentPosition: pA,
            totalDistanceMeters: null,
          );

          expect(progressNullTotal.distanceTraveledMeters, equals(0.0));
          expect(progressNullTotal.remainingDistanceMeters, equals(0.0));
          expect(progressNullTotal.progressPercentage, equals(100.0));

          verifyRoutePlanCompatibility(
            geometry: allCoincidentGeom,
            totalDistanceMeters: 0.0,
            progress: progressNullTotal,
          );

          // Caso C: posición fuera del punto coincidente (ej. en pB)
          final progressOffset = calculator.calculate(
            geometry: allCoincidentGeom,
            currentPosition: pB,
            totalDistanceMeters: 0.0,
          );

          expect(progressOffset.distanceTraveledMeters, equals(0.0));
          expect(progressOffset.remainingDistanceMeters, equals(0.0));
          expect(progressOffset.progressPercentage, equals(100.0));
          expect(progressOffset.projectedPoint, equals(pA));
          expect(
            progressOffset.distanceToRouteMeters,
            closeTo(pB.distanceTo(pA), 0.001),
          );

          verifyRoutePlanCompatibility(
            geometry: allCoincidentGeom,
            totalDistanceMeters: 0.0,
            progress: progressOffset,
          );
        },
      );

      test(
        'geometría válida con totalDistanceMeters distinto de la distancia geométrica (mayor o menor)',
        () {
          final validGeom = [pA, pB];
          final geomDistance = pA.distanceTo(pB); // ~4850.5 m

          // Subcaso A: totalDistanceMeters mayor a la distancia geométrica (ej. 6000.0 m)
          const providerGreater = 6000.0;
          expect(providerGreater, greaterThan(geomDistance));

          // 1. En el inicio (pA)
          final progStartGreater = calculator.calculate(
            geometry: validGeom,
            currentPosition: pA,
            totalDistanceMeters: providerGreater,
          );
          expect(progStartGreater.distanceTraveledMeters, equals(0.0));
          expect(
            progStartGreater.remainingDistanceMeters,
            equals(providerGreater),
          );
          expect(progStartGreater.progressPercentage, equals(0.0));
          verifyRoutePlanCompatibility(
            geometry: validGeom,
            totalDistanceMeters: providerGreater,
            progress: progStartGreater,
          );

          // 2. En el destino (pB)
          final progEndGreater = calculator.calculate(
            geometry: validGeom,
            currentPosition: pB,
            totalDistanceMeters: providerGreater,
          );
          expect(
            progEndGreater.distanceTraveledMeters,
            equals(providerGreater),
          );
          expect(progEndGreater.remainingDistanceMeters, equals(0.0));
          expect(progEndGreater.progressPercentage, equals(100.0));
          verifyRoutePlanCompatibility(
            geometry: validGeom,
            totalDistanceMeters: providerGreater,
            progress: progEndGreater,
          );

          // 3. En la mitad geométrica
          final midPoint = Coordinates(
            (pA.latitude + pB.latitude) / 2.0,
            (pA.longitude + pB.longitude) / 2.0,
          );
          final progMidGreater = calculator.calculate(
            geometry: validGeom,
            currentPosition: midPoint,
            totalDistanceMeters: providerGreater,
          );
          expect(progMidGreater.progressPercentage, closeTo(50.0, 0.5));
          expect(progMidGreater.distanceTraveledMeters, closeTo(3000.0, 5.0));
          expect(progMidGreater.remainingDistanceMeters, closeTo(3000.0, 5.0));
          expect(
            progMidGreater.distanceTraveledMeters +
                progMidGreater.remainingDistanceMeters,
            closeTo(providerGreater, 0.001),
          );
          verifyRoutePlanCompatibility(
            geometry: validGeom,
            totalDistanceMeters: providerGreater,
            progress: progMidGreater,
          );

          // Subcaso B: totalDistanceMeters menor a la distancia geométrica (ej. 3500.0 m)
          const providerLesser = 3500.0;
          expect(providerLesser, lessThan(geomDistance));

          // 1. En el inicio (pA)
          final progStartLesser = calculator.calculate(
            geometry: validGeom,
            currentPosition: pA,
            totalDistanceMeters: providerLesser,
          );
          expect(progStartLesser.distanceTraveledMeters, equals(0.0));
          expect(
            progStartLesser.remainingDistanceMeters,
            equals(providerLesser),
          );
          expect(progStartLesser.progressPercentage, equals(0.0));
          verifyRoutePlanCompatibility(
            geometry: validGeom,
            totalDistanceMeters: providerLesser,
            progress: progStartLesser,
          );

          // 2. En el destino (pB)
          final progEndLesser = calculator.calculate(
            geometry: validGeom,
            currentPosition: pB,
            totalDistanceMeters: providerLesser,
          );
          expect(progEndLesser.distanceTraveledMeters, equals(providerLesser));
          expect(progEndLesser.remainingDistanceMeters, equals(0.0));
          expect(progEndLesser.progressPercentage, equals(100.0));
          verifyRoutePlanCompatibility(
            geometry: validGeom,
            totalDistanceMeters: providerLesser,
            progress: progEndLesser,
          );
        },
      );
    },
  );
}
