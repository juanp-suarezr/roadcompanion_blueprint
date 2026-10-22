import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:road_companion/domain/entities/coordinates.dart';
import 'package:road_companion/domain/entities/maneuver_type.dart';
import 'package:road_companion/features/navigation/infrastructure/services/osrm_routing_service.dart';

void main() {
  group('OsrmRoutingService - Pruebas del motor vial de rutas', () {
    final origin = Coordinates(5.0688, -75.5173);
    final destination = Coordinates(5.0345, -75.4820);

    test(
      '1. Parsea exitosamente respuesta OSRM con geometría GeoJSON y maniobras viales',
      () async {
        final mockClient = MockClient((request) async {
          expect(request.url.path, contains('/route/v1/driving/'));
          expect(request.url.queryParameters['overview'], equals('full'));
          expect(request.url.queryParameters['steps'], equals('true'));

          final sampleOsrm = jsonEncode({
            'code': 'Ok',
            'routes': [
              {
                'distance': 8450.5,
                'duration': 720.0,
                'geometry': {
                  'coordinates': [
                    [-75.5173, 5.0688],
                    [-75.5000, 5.0500],
                    [-75.4820, 5.0345],
                  ],
                },
                'legs': [
                  {
                    'summary': 'Carrera 22 y Avenida Santander',
                    'steps': [
                      {
                        'name': 'Carrera 22',
                        'distance': 1200.0,
                        'maneuver': {'type': 'depart', 'modifier': ''},
                      },
                      {
                        'name': 'Avenida Santander',
                        'distance': 5400.0,
                        'maneuver': {'type': 'turn', 'modifier': 'left'},
                      },
                      {
                        'name': 'Destino',
                        'distance': 0.0,
                        'maneuver': {'type': 'arrive', 'modifier': ''},
                      },
                    ],
                  },
                ],
              },
            ],
          });

          return http.Response(
            sampleOsrm,
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final service = OsrmRoutingService(client: mockClient);
        final route = await service.calculateRoute(
          origin: origin,
          destination: destination,
        );

        expect(route.totalDistanceKm, closeTo(8.45, 0.01));
        expect(route.estimatedDuration.inMinutes, equals(12));
        expect(route.summary, equals('Carrera 22 y Avenida Santander'));
        expect(route.geometry.length, equals(3));
        expect(route.geometry.first, equals(origin));
        expect(route.geometry.last, equals(destination));

        // Comprobar mapeo a Maneuver del dominio
        final maneuvers = route.routePlan.maneuvers;
        expect(maneuvers.length, equals(3));
        expect(maneuvers[0].type, equals(ManeuverType.depart));
        expect(maneuvers[0].instruction, contains('Carrera 22'));

        expect(maneuvers[1].type, equals(ManeuverType.left));
        expect(
          maneuvers[1].instruction,
          contains('Gira a la izquierda hacia Avenida Santander'),
        );

        expect(maneuvers[2].type, equals(ManeuverType.arrive));
        expect(maneuvers[2].instruction, equals('Has llegado a tu destino'));
      },
    );

    test('2. Lanza NoRouteFoundException si OSRM no encuentra ruta', () async {
      final mockClient = MockClient((_) async {
        final sampleErr = jsonEncode({
          'code': 'NoRoute',
          'message': 'Impossible route between points',
        });
        return http.Response(sampleErr, 200);
      });

      final service = OsrmRoutingService(client: mockClient);
      expect(
        () => service.calculateRoute(origin: origin, destination: destination),
        throwsA(isA<NoRouteFoundException>()),
      );
    });

    test('3. Lanza excepción ante fallo del servidor (HTTP 502)', () async {
      final mockClient = MockClient(
        (_) async => http.Response('Bad Gateway', 502),
      );
      final service = OsrmRoutingService(client: mockClient);

      expect(
        () => service.calculateRoute(origin: origin, destination: destination),
        throwsException,
      );
    });

    test(
      '4. calculateRoutesWithAlternatives procesa 3 rutas con métricas relativas y etiquetas',
      () async {
        final mockClient = MockClient((request) async {
          expect(request.url.queryParameters['alternatives'], equals('3'));

          final sampleOsrm = jsonEncode({
            'code': 'Ok',
            'routes': [
              {
                'distance': 10000.0,
                'duration': 600.0, // 10 min (Más rápida)
                'geometry': {
                  'coordinates': [
                    [-75.5173, 5.0688],
                    [-75.5000, 5.0500],
                    [-75.4820, 5.0345],
                  ],
                },
                'legs': [
                  {'summary': 'Autopista Central', 'steps': []},
                ],
              },
              {
                'distance': 8000.0, // 8 km (Más corta)
                'duration': 720.0, // 12 min (+2 min)
                'geometry': {
                  'coordinates': [
                    [-75.5173, 5.0688],
                    [-75.4950, 5.0450],
                    [-75.4820, 5.0345],
                  ],
                },
                'legs': [
                  {'summary': 'Vía Panamericana', 'steps': []},
                ],
              },
              {
                'distance': 11500.0, // +3.5 km
                'duration': 900.0, // 15 min (+5 min)
                'geometry': {
                  'coordinates': [
                    [-75.5173, 5.0688],
                    [-75.5100, 5.0400],
                    [-75.4820, 5.0345],
                  ],
                },
                'legs': [
                  {'summary': 'Avenida del Río', 'steps': []},
                ],
              },
            ],
          });

          return http.Response(
            sampleOsrm,
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final service = OsrmRoutingService(client: mockClient);
        final routes = await service.calculateRoutesWithAlternatives(
          origin: origin,
          destination: destination,
        );

        expect(routes.length, equals(3));

        // Ruta 1 (Más rápida)
        expect(routes[0].routeName, equals('Ruta 1'));
        expect(routes[0].summary, equals('Autopista Central'));
        expect(routes[0].isFastest, isTrue);
        expect(routes[0].isShortest, isFalse);
        expect(
          routes[0].durationDiff,
          isNull,
        ); // Es la más rápida (sin exceso de tiempo)
        expect(
          routes[0].distanceDiffKm,
          closeTo(2.0, 0.01),
        ); // +2.0 km vs la más corta

        // Ruta 2 (Más corta)
        expect(routes[1].routeName, equals('Ruta 2'));
        expect(routes[1].summary, equals('Vía Panamericana'));
        expect(routes[1].isFastest, isFalse);
        expect(routes[1].isShortest, isTrue);
        expect(routes[1].durationDiff!.inMinutes, equals(2)); // +2 min
        expect(
          routes[1].distanceDiffKm,
          isNull,
        ); // Es la más corta (sin exceso de km)

        // Ruta 3 (Alternativa secundaria)
        expect(routes[2].routeName, equals('Ruta 3'));
        expect(routes[2].summary, equals('Avenida del Río'));
        expect(routes[2].isFastest, isFalse);
        expect(routes[2].isShortest, isFalse);
        expect(routes[2].durationDiff!.inMinutes, equals(5)); // +5 min
        expect(routes[2].distanceDiffKm, closeTo(3.5, 0.01)); // +3.5 km
      },
    );

    test(
      '5. calculateRoutesWithAlternatives devuelve 1 sola ruta si el proveedor no ofrece alternativas (sin fabricar ficticias)',
      () async {
        final mockClient = MockClient((_) async {
          final sampleOsrm = jsonEncode({
            'code': 'Ok',
            'routes': [
              {
                'distance': 5000.0,
                'duration': 400.0,
                'geometry': {
                  'coordinates': [
                    [-75.5173, 5.0688],
                    [-75.4820, 5.0345],
                  ],
                },
                'legs': [
                  {'summary': 'Única Vía', 'steps': []},
                ],
              },
            ],
          });
          return http.Response(
            sampleOsrm,
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final service = OsrmRoutingService(client: mockClient);
        final routes = await service.calculateRoutesWithAlternatives(
          origin: origin,
          destination: destination,
        );

        expect(routes.length, equals(1));
        expect(routes.first.routeName, equals('Ruta 1'));
        expect(routes.first.summary, equals('Única Vía'));
      },
    );

    test(
      '6. Lanza InvalidRouteGeometryException ante geometría vacía o corrupta',
      () async {
        final mockClient = MockClient((_) async {
          final sampleOsrm = jsonEncode({
            'code': 'Ok',
            'routes': [
              {
                'distance': 0.0,
                'duration': 0.0,
                'geometry': {
                  'coordinates': [], // Vacío
                },
                'legs': [],
              },
            ],
          });
          return http.Response(
            sampleOsrm,
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final service = OsrmRoutingService(client: mockClient);
        expect(
          () =>
              service.calculateRoute(origin: origin, destination: destination),
          throwsA(isA<InvalidRouteGeometryException>()),
        );
      },
    );

    test(
      '7. Caso 5 (Urbano): Acceso privado más corto vs alternativa pública más larga. Prioriza la pública como Ruta 1 y no premia la privada',
      () async {
        final mockClient = MockClient((_) async {
          final sampleOsrm = jsonEncode({
            'code': 'Ok',
            'routes': [
              // Atajo privado con cerrojo (OSRM lo devuelve primero por ser más corto)
              {
                'distance': 3200.0, // 3.2 km
                'duration': 300.0, // 5 min
                'geometry': {
                  'coordinates': [
                    [-75.5173, 5.0688],
                    [-75.5000, 5.0500],
                    [-75.4820, 5.0345],
                  ],
                },
                'legs': [
                  {
                    'summary': 'Atajo por Terreno Empresa Privada',
                    'steps': [
                      {
                        'name': 'Callejón Empresa Privada',
                        'distance': 1500.0,
                        'access': 'private',
                        'maneuver': {'type': 'turn', 'modifier': 'right'},
                      },
                    ],
                  },
                ],
              },
              // Vía pública principal (más larga pero libre y transitable)
              {
                'distance': 5800.0, // 5.8 km
                'duration': 650.0, // ~11 min
                'geometry': {
                  'coordinates': [
                    [-75.5173, 5.0688],
                    [-75.5100, 5.0450],
                    [-75.4820, 5.0345],
                  ],
                },
                'legs': [
                  {
                    'summary': 'Avenida Circunvalar Pública',
                    'steps': [
                      {
                        'name': 'Avenida Circunvalar',
                        'distance': 5800.0,
                        'access': 'yes',
                        'maneuver': {'type': 'depart', 'modifier': ''},
                      },
                    ],
                  },
                ],
              },
            ],
          });
          return http.Response(
            sampleOsrm,
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final service = OsrmRoutingService(client: mockClient);
        final routes = await service.calculateRoutesWithAlternatives(
          origin: origin,
          destination: destination,
        );

        expect(routes.length, equals(2));

        // La Ruta 1 DEBE ser la vía pública transitable, a pesar de ser más larga
        final recommendedRoute = routes[0];
        expect(recommendedRoute.routeName, equals('Ruta 1'));
        expect(recommendedRoute.summary, equals('Avenida Circunvalar Pública'));
        expect(recommendedRoute.isPubliclyPassable, isTrue);
        expect(recommendedRoute.isConfirmedRestricted, isFalse);
        expect(
          recommendedRoute.isFastest,
          isTrue,
        ); // La más rápida entre las públicas
        expect(
          recommendedRoute.isShortest,
          isTrue,
        ); // La más corta entre las públicas

        // La Ruta 2 es el atajo privado con cerrojo
        final restrictedShortcut = routes[1];
        expect(restrictedShortcut.routeName, equals('Ruta 2'));
        expect(
          restrictedShortcut.summary,
          equals('Atajo por Terreno Empresa Privada'),
        );
        expect(restrictedShortcut.isConfirmedRestricted, isTrue);
        expect(restrictedShortcut.isPubliclyPassable, isFalse);
        expect(
          restrictedShortcut.isFastest,
          isFalse,
        ); // No se premia con medallas
        expect(restrictedShortcut.isShortest, isFalse);
        expect(
          restrictedShortcut.validation.warnings.any(
            (w) => w.contains('access=private'),
          ),
          isTrue,
        );
      },
    );

    test(
      '8. Caso 7 (Urbano): Varias alternativas donde una tiene cerrojo/portón (barrier=gate) y otra es pública',
      () async {
        final mockClient = MockClient((_) async {
          final sampleOsrm = jsonEncode({
            'code': 'Ok',
            'routes': [
              {
                'distance': 4000.0,
                'duration': 500.0,
                'geometry': {
                  'coordinates': [
                    [-75.5173, 5.0688],
                    [-75.4820, 5.0345],
                  ],
                },
                'legs': [
                  {
                    'summary': 'Acceso Condominio Cerrado',
                    'steps': [
                      {
                        'name': 'Portón Cerrojo Norte',
                        'barrier': 'gate',
                        'distance': 100.0,
                        'maneuver': {'type': 'turn', 'modifier': 'left'},
                      },
                    ],
                  },
                ],
              },
              {
                'distance': 6000.0,
                'duration': 700.0,
                'geometry': {
                  'coordinates': [
                    [-75.5173, 5.0688],
                    [-75.4820, 5.0345],
                  ],
                },
                'legs': [
                  {
                    'summary': 'Vía Departamental Libre',
                    'steps': [
                      {
                        'name': 'Carretera Central',
                        'access': 'yes',
                        'distance': 6000.0,
                        'maneuver': {'type': 'depart', 'modifier': ''},
                      },
                    ],
                  },
                ],
              },
            ],
          });
          return http.Response(
            sampleOsrm,
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final service = OsrmRoutingService(client: mockClient);
        final routes = await service.calculateRoutesWithAlternatives(
          origin: origin,
          destination: destination,
        );

        expect(routes.length, equals(2));
        expect(routes[0].isPubliclyPassable, isTrue);
        expect(routes[0].summary, equals('Vía Departamental Libre'));
        expect(routes[1].isConfirmedRestricted, isTrue);
        expect(
          routes[1].validation.warnings.any(
            (w) => w.contains('portón/cerrojo'),
          ),
          isTrue,
        );
      },
    );

    test(
      '9. Detecta destino ajustado (snapping) con alerta cuando la calzada finaliza lejos del objetivo',
      () async {
        // Destino buscado: (5.0345, -75.4820)
        // Snapping de OSRM deja la calzada vehicular a 450 metros del objetivo
        final distantDestination = Coordinates(5.0345, -75.4820);

        final mockClient = MockClient((_) async {
          final sampleOsrm = jsonEncode({
            'code': 'Ok',
            'routes': [
              {
                'distance': 5000.0,
                'duration': 400.0,
                'geometry': {
                  'coordinates': [
                    [-75.5173, 5.0688],
                    [
                      -75.4860,
                      5.0375,
                    ], // Último punto vial (~460m de distancia geodésica)
                  ],
                },
                'legs': [
                  {'summary': 'Camino Rural Final', 'steps': []},
                ],
              },
            ],
          });
          return http.Response(
            sampleOsrm,
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final service = OsrmRoutingService(client: mockClient);
        final route = await service.calculateRoute(
          origin: origin,
          destination: distantDestination,
        );

        expect(route.validation.hasDestinationGap, isTrue);
        expect(route.validation.destinationGapMeters, greaterThan(300.0));
        expect(
          route.validation.warnings.any((w) => w.contains('finaliza a')),
          isTrue,
        );
      },
    );

    test(
      '10. Procesa correctamente el escenario donde OSRM devuelve 1 sola ruta física',
      () async {
        final mockClient = MockClient((request) async {
          expect(request.url.queryParameters['alternatives'], equals('3'));

          final sampleOsrm = jsonEncode({
            'code': 'Ok',
            'routes': [
              {
                'distance': 15000.0,
                'duration': 1200.0,
                'geometry': {
                  'coordinates': [
                    [-75.5173, 5.0688],
                    [-75.4900, 5.0450],
                    [-75.4820, 5.0345],
                  ],
                },
                'legs': [
                  {'summary': 'Carretera de un solo valle', 'steps': []},
                ],
              },
            ],
          });
          return http.Response(
            sampleOsrm,
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final service = OsrmRoutingService(client: mockClient);
        final routes = await service.calculateRoutesWithAlternatives(
          origin: origin,
          destination: destination,
        );

        expect(routes.length, equals(1));
        expect(routes.first.summary, equals('Carretera de un solo valle'));
        expect(routes.first.alternatives, isEmpty);
      },
    );

    test(
      '11. Procesa OSRM con 2 rutas devueltas asignando alternativas hermanas y diferencias',
      () async {
        final mockClient = MockClient((_) async {
          final sampleOsrm = jsonEncode({
            'code': 'Ok',
            'routes': [
              {
                'distance': 10000.0,
                'duration': 600.0,
                'geometry': {
                  'coordinates': [
                    [-75.5173, 5.0688],
                    [-75.4820, 5.0345],
                  ],
                },
                'legs': [
                  {'summary': 'Vía Principal', 'steps': []},
                ],
              },
              {
                'distance': 12000.0,
                'duration': 750.0,
                'geometry': {
                  'coordinates': [
                    [-75.5173, 5.0688],
                    [-75.4820, 5.0345],
                  ],
                },
                'legs': [
                  {'summary': 'Vía Alterna', 'steps': []},
                ],
              },
            ],
          });
          return http.Response(
            sampleOsrm,
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final service = OsrmRoutingService(client: mockClient);
        final routes = await service.calculateRoutesWithAlternatives(
          origin: origin,
          destination: destination,
        );

        expect(routes.length, equals(2));
        expect(routes[0].alternatives.length, equals(1));
        expect(routes[1].alternatives.length, equals(1));
        expect(routes[0].isFastest, isTrue);
        expect(routes[1].isFastest, isFalse);
      },
    );

    test(
      '12. Descarte de rutas con geometría inválida (< 2 puntos) conservando las rutas viables',
      () async {
        final mockClient = MockClient((_) async {
          final sampleOsrm = jsonEncode({
            'code': 'Ok',
            'routes': [
              {
                'distance': 8000.0,
                'duration': 500.0,
                'geometry': {
                  'coordinates': [
                    [-75.5173, 5.0688],
                    [-75.4820, 5.0345],
                  ],
                },
                'legs': [
                  {'summary': 'Ruta Válida', 'steps': []},
                ],
              },
              {
                'distance': 9000.0,
                'duration': 600.0,
                'geometry': {
                  // Solo 1 punto: geometría inválida
                  'coordinates': [
                    [-75.5173, 5.0688],
                  ],
                },
                'legs': [
                  {'summary': 'Ruta Corrupta', 'steps': []},
                ],
              },
            ],
          });
          return http.Response(
            sampleOsrm,
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final service = OsrmRoutingService(client: mockClient);
        final routes = await service.calculateRoutesWithAlternatives(
          origin: origin,
          destination: destination,
        );

        expect(routes.length, equals(1));
        expect(routes.first.summary, equals('Ruta Válida'));
      },
    );

    test(
      '13. Caso exacto Pereira -> Barrio Guadalupe, Dosquebradas: rechaza acceso por portón privado (4.833360, -75.672461) y recomienda alternativa pública',
      () async {
        final pereiraOrigin = Coordinates(4.81333, -75.69611);
        final guadalupeDest = Coordinates(4.83667, -75.67234);

        int callCount = 0;
        final mockClient = MockClient((request) async {
          callCount++;
          if (callCount == 1) {
            // Primera llamada: OSRM devuelve la ruta que ataja por el portón privado (nodo 9337280309)
            final sampleRestrictedOsrm = jsonEncode({
              'code': 'Ok',
              'routes': [
                {
                  'distance': 4800.0,
                  'duration': 400.0,
                  'geometry': {
                    'coordinates': [
                      [-75.69611, 4.81333],
                      [-75.672512, 4.833517],
                      [
                        -75.672461,
                        4.833360,
                      ], // Coordenada problemática del portón
                      [-75.672273, 4.833395],
                      [-75.67234, 4.83667],
                    ],
                  },
                  'legs': [
                    {
                      'summary': 'Avenida Simón Bolívar y Callejón Privado',
                      'annotation': {
                        'nodes': [
                          1001,
                          9333574353,
                          9337280309, // Nodo con barrier=gate documentado
                          9337280308,
                          1002,
                        ],
                      },
                      'steps': [
                        {
                          'name': 'Avenida Simón Bolívar',
                          'distance': 4200.0,
                          'maneuver': {'type': 'depart', 'modifier': ''},
                        },
                        {
                          'name': '',
                          'distance': 30.0,
                          'maneuver': {'type': 'turn', 'modifier': 'right'},
                        },
                        {
                          'name': 'Carrera 14',
                          'distance': 570.0,
                          'maneuver': {'type': 'arrive', 'modifier': ''},
                        },
                      ],
                    },
                  ],
                },
              ],
            });
            return http.Response(
              sampleRestrictedOsrm,
              200,
              headers: {'content-type': 'application/json'},
            );
          } else {
            // Segunda llamada: OSRM calcula el desvío público solicitado por ESTELA vía Av. Simón Bolívar / Retorno / Calle 36
            final samplePublicBypassOsrm = jsonEncode({
              'code': 'Ok',
              'routes': [
                {
                  'distance': 6640.0,
                  'duration': 500.0,
                  'geometry': {
                    'coordinates': [
                      [-75.69611, 4.81333],
                      [-75.6710, 4.8350],
                      [
                        -75.66653,
                        4.83906,
                      ], // Retorno público Postobón / Servientrega
                      [-75.6715, 4.8365], // Calle 36 hacia Carrera 15
                      [
                        -75.67234,
                        4.83667,
                      ], // Destino exacto en Barrio Guadalupe
                    ],
                  },
                  'legs': [
                    {
                      'summary': 'Avenida Simón Bolívar',
                      'annotation': {
                        'nodes': [1001, 2001, 2002],
                      },
                      'steps': [
                        {
                          'name': 'Avenida Simón Bolívar',
                          'distance': 4500.0,
                          'maneuver': {'type': 'depart', 'modifier': ''},
                        },
                      ],
                    },
                    {
                      'summary': 'Carrera 15 y Calle 38',
                      'annotation': {
                        'nodes': [2003, 2004, 2005],
                      },
                      'steps': [
                        {
                          'name': 'Calle 36',
                          'distance': 800.0,
                          'maneuver': {'type': 'turn', 'modifier': 'right'},
                        },
                        {
                          'name': 'Calle 38',
                          'distance': 1340.0,
                          'maneuver': {'type': 'arrive', 'modifier': ''},
                        },
                      ],
                    },
                  ],
                },
              ],
            });
            return http.Response(
              samplePublicBypassOsrm,
              200,
              headers: {'content-type': 'application/json'},
            );
          }
        });

        final service = OsrmRoutingService(client: mockClient);
        final routes = await service.calculateRoutesWithAlternatives(
          origin: pereiraOrigin,
          destination: guadalupeDest,
        );

        expect(routes.isNotEmpty, isTrue);
        final primaryRoute = routes.first;

        // La ruta recomendada (Ruta 1) debe ser la pública
        expect(primaryRoute.isPubliclyPassable, isTrue);
        expect(primaryRoute.isConfirmedRestricted, isFalse);
        expect(primaryRoute.summary, contains('Avenida Simón Bolívar'));
        expect(primaryRoute.summary, contains('Carrera 15 y Calle 38'));

        // Ningún nodo de la ruta pública debe cruzar los nodos barrera
        final allCoordinates = primaryRoute.geometry;
        final hasRestrictedCoord = allCoordinates.any(
          (c) => c.latitude == 4.833360 && c.longitude == -75.672461,
        );
        expect(hasRestrictedCoord, isFalse);

        // La ruta restringida original queda relegada con advertencias
        if (routes.length > 1) {
          final restrictedAlt = routes.last;
          expect(restrictedAlt.isConfirmedRestricted, isTrue);
          expect(
            restrictedAlt.validation.warnings.any(
              (w) => w.contains('Portón privado'),
            ),
            isTrue,
          );
        }
      },
    );

    test(
      '14. Destino en barrio público sin restricciones: no genera desvíos artificiales y conserva trazado directo',
      () async {
        final normalOrigin = Coordinates(4.81333, -75.69611);
        final normalDest = Coordinates(4.82000, -75.69000);

        int callCount = 0;
        final mockClient = MockClient((request) async {
          callCount++;
          final sampleNormalOsrm = jsonEncode({
            'code': 'Ok',
            'routes': [
              {
                'distance': 1500.0,
                'duration': 180.0,
                'geometry': {
                  'coordinates': [
                    [-75.69611, 4.81333],
                    [-75.69300, 4.81600],
                    [-75.69000, 4.82000],
                  ],
                },
                'legs': [
                  {
                    'summary': 'Carrera 7',
                    'annotation': {
                      'nodes': [5001, 5002, 5003],
                    },
                    'steps': [
                      {
                        'name': 'Carrera 7',
                        'distance': 1500.0,
                        'maneuver': {'type': 'depart', 'modifier': ''},
                      },
                      {
                        'name': 'Destino',
                        'distance': 0.0,
                        'maneuver': {'type': 'arrive', 'modifier': ''},
                      },
                    ],
                  },
                ],
              },
            ],
          });
          return http.Response(
            sampleNormalOsrm,
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final service = OsrmRoutingService(client: mockClient);
        final routes = await service.calculateRoutesWithAlternatives(
          origin: normalOrigin,
          destination: normalDest,
        );

        expect(routes.length, equals(1));
        expect(callCount, equals(1)); // No dispara bypasses innecesarios
        expect(routes.first.isPubliclyPassable, isTrue);
        expect(routes.first.isConfirmedRestricted, isFalse);
      },
    );

    test(
      '15. Cartografía con datos no confirmados: indica incertidumbre y precaución sin afirmar falsamente portón privado',
      () async {
        final mockClient = MockClient((_) async {
          final sampleUnconfirmedOsrm = jsonEncode({
            'code': 'Ok',
            'routes': [
              {
                'distance': 2500.0,
                'duration': 220.0,
                'geometry': {
                  'coordinates': [
                    [-75.5000, 5.0500],
                    [-75.5010, 5.0510],
                    [-75.5020, 5.0520],
                  ],
                },
                'legs': [
                  {
                    'summary': 'Vía Rural sin categorizar',
                    'annotation': {
                      'nodes': [8001, 8002],
                    },
                    'steps': [
                      {
                        'name': 'Vía Rural',
                        'access': 'unknown',
                        'unconfirmed': true,
                        'distance': 2500.0,
                        'maneuver': {'type': 'depart', 'modifier': ''},
                      },
                    ],
                  },
                ],
              },
            ],
          });
          return http.Response(
            sampleUnconfirmedOsrm,
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final service = OsrmRoutingService(client: mockClient);
        final routes = await service.calculateRoutesWithAlternatives(
          origin: origin,
          destination: destination,
        );

        expect(routes.first.hasUnconfirmedTransitability, isTrue);
        expect(routes.first.isConfirmedRestricted, isFalse);
        expect(
          routes.first.validation.warnings.any(
            (w) => w.contains('Información de acceso no confirmada'),
          ),
          isTrue,
        );
      },
    );

    test(
      '16. Selector de alternativas: clasifica Más rápida, Equilibrada y Preferida correctamente',
      () async {
        final mockClient = MockClient((_) async {
          final sampleMultiRoutes = jsonEncode({
            'code': 'Ok',
            'routes': [
              {
                'distance': 10000.0,
                'duration': 900.0, // 15 min (más rápida)
                'geometry': {
                  'coordinates': [
                    [-75.5000, 5.0500],
                    [-75.5050, 5.0550],
                  ],
                },
                'legs': [
                  {
                    'summary': 'Autopista Principal',
                    'annotation': {
                      'nodes': [101, 102],
                    },
                    'steps': [
                      {
                        'name': 'Autopista Principal',
                        'distance': 10000.0,
                        'maneuver': {'type': 'depart', 'modifier': ''},
                      },
                    ],
                  },
                ],
              },
              {
                'distance': 10500.0,
                'duration': 1020.0, // 17 min (equilibrada)
                'geometry': {
                  'coordinates': [
                    [-75.5000, 5.0500],
                    [-75.5070, 5.0570],
                  ],
                },
                'legs': [
                  {
                    'summary': 'Avenida Secundaria',
                    'annotation': {
                      'nodes': [201, 202],
                    },
                    'steps': [
                      {
                        'name': 'Avenida Secundaria',
                        'distance': 10500.0,
                        'maneuver': {'type': 'depart', 'modifier': ''},
                      },
                    ],
                  },
                ],
              },
              {
                'distance': 14000.0,
                'duration': 1500.0, // 25 min (rodeo largo)
                'geometry': {
                  'coordinates': [
                    [-75.5000, 5.0500],
                    [-75.5120, 5.0620],
                  ],
                },
                'legs': [
                  {
                    'summary': 'Variante Periférica',
                    'annotation': {
                      'nodes': [301, 302],
                    },
                    'steps': [
                      {
                        'name': 'Variante Periférica',
                        'distance': 14000.0,
                        'maneuver': {'type': 'depart', 'modifier': ''},
                      },
                    ],
                  },
                ],
              },
            ],
          });
          return http.Response(
            sampleMultiRoutes,
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final service = OsrmRoutingService(client: mockClient);
        final routes = await service.calculateRoutesWithAlternatives(
          origin: origin,
          destination: destination,
        );

        expect(routes.length, equals(3));

        // Ruta 1: Más rápida y preferida (sin advertencias y menor duración)
        final r1 = routes[0];
        expect(r1.isFastest, isTrue);
        expect(r1.isPreferred, isTrue);
        expect(r1.isBalanced, isFalse);
        expect(r1.alternatives.length, equals(2));

        // Ruta 2: Equilibrada (intermedia en tiempo y distancia)
        final r2 = routes[1];
        expect(r2.isFastest, isFalse);
        expect(r2.isBalanced, isTrue);
        expect(r2.distanceDiffKm, isNotNull);
        expect(r2.durationDiff, isNotNull);

        // Ruta 3: Ni más rápida ni equilibrada
        final r3 = routes[2];
        expect(r3.isFastest, isFalse);
        expect(r3.isBalanced, isFalse);
      },
    );
  });
}
