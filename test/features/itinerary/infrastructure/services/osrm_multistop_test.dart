import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:road_companion/road_companion.dart';
import 'package:test/test.dart';

void main() {
  final origin = Coordinates(4.5981, -74.0758); // Bogotá
  final wp1 = Coordinates(4.9351, -73.9921); // Briceño
  final destination = Coordinates(5.6322, -73.5244); // Villa de Leyva

  group('OsrmRoutingService - calculateMultistopRoute', () {
    test('delega a calculateRoute cuando no hay paradas intermedias', () async {
      String? requestedUrl;
      final mockClient = MockClient((request) async {
        requestedUrl = request.url.toString();
        final jsonResponse = {
          'code': 'Ok',
          'routes': [
            {
              'distance': 150000.0,
              'duration': 10800.0,
              'geometry': {
                'coordinates': [
                  [-74.0758, 4.5981],
                  [-73.5244, 5.6322],
                ],
              },
              'legs': [
                {
                  'summary': 'Autopista Norte',
                  'steps': [
                    {
                      'maneuver': {
                        'type': 'depart',
                        'location': [-74.0758, 4.5981],
                      },
                      'name': 'Calle 10',
                      'distance': 500.0,
                    },
                    {
                      'maneuver': {
                        'type': 'arrive',
                        'location': [-73.5244, 5.6322],
                      },
                      'name': 'Destino',
                      'distance': 0.0,
                    },
                  ],
                },
              ],
            },
          ],
        };
        return http.Response(jsonEncode(jsonResponse), 200);
      });

      final routingService = OsrmRoutingService(client: mockClient);
      final route = await routingService.calculateMultistopRoute(
        origin: origin,
        waypoints: const [],
        destination: destination,
      );

      expect(route.totalDistanceKm, equals(150.0));
      expect(requestedUrl, contains('alternatives=3'));
    });

    test(
      'concatena waypoints ordenados con punto y coma y procesa múltiples legs',
      () async {
        String? requestedUrl;
        final mockClient = MockClient((request) async {
          requestedUrl = request.url.toString();
          final jsonResponse = {
            'code': 'Ok',
            'routes': [
              {
                'distance': 165000.0,
                'duration': 12000.0,
                'geometry': {
                  'coordinates': [
                    [-74.0758, 4.5981],
                    [-73.9921, 4.9351],
                    [-73.5244, 5.6322],
                  ],
                },
                'legs': [
                  {
                    'summary': 'Tramo 1 (Bogotá a Briceño)',
                    'steps': [
                      {
                        'maneuver': {
                          'type': 'depart',
                          'location': [-74.0758, 4.5981],
                        },
                        'name': 'Autopista Norte',
                        'distance': 35000.0,
                      },
                      {
                        'maneuver': {
                          'type': 'arrive',
                          'location': [-73.9921, 4.9351],
                        },
                        'name': 'Llegada intermedia Briceño',
                        'distance': 0.0,
                      },
                    ],
                  },
                  {
                    'summary': 'Tramo 2 (Briceño a Villa de Leyva)',
                    'steps': [
                      {
                        'maneuver': {
                          'type': 'turn',
                          'modifier': 'right',
                          'location': [-73.9921, 4.9351],
                        },
                        'name': 'Vía Ubaté',
                        'distance': 130000.0,
                      },
                      {
                        'maneuver': {
                          'type': 'arrive',
                          'location': [-73.5244, 5.6322],
                        },
                        'name': 'Destino final',
                        'distance': 0.0,
                      },
                    ],
                  },
                ],
              },
            ],
          };
          return http.Response(jsonEncode(jsonResponse), 200);
        });

        final routingService = OsrmRoutingService(client: mockClient);
        final route = await routingService.calculateMultistopRoute(
          origin: origin,
          waypoints: [wp1],
          destination: destination,
        );

        expect(
          requestedUrl,
          contains(
            '-74.075800,4.598100;-73.992100,4.935100;-73.524400,5.632200',
          ),
        );
        expect(route.totalDistanceKm, equals(165.0));
        expect(route.geometry.length, equals(3));
        // Trata la llegada intermedia como una instrucción explícita hacia el motociclista
        expect(
          route.routePlan.maneuvers.any(
            (m) => m.instructionText.contains('Llegada a parada intermedia 1'),
          ),
          isTrue,
        );
        expect(
          route.routePlan.maneuvers.any((m) => m.type == ManeuverType.right),
          isTrue,
        );
      },
    );

    test(
      'calcula distancia y duración acumulando legs cuando el valor raíz es cero',
      () async {
        final mockClient = MockClient((request) async {
          final jsonResponse = {
            'code': 'Ok',
            'routes': [
              {
                'distance': 0.0, // Raíz vacía
                'duration': 0.0,
                'geometry': {
                  'coordinates': [
                    [-74.0758, 4.5981],
                    [-73.9921, 4.9351],
                    [-73.5244, 5.6322],
                  ],
                },
                'legs': [
                  {'distance': 50000.0, 'duration': 3600.0, 'steps': []},
                  {'distance': 70000.0, 'duration': 5400.0, 'steps': []},
                ],
              },
            ],
          };
          return http.Response(jsonEncode(jsonResponse), 200);
        });

        final routingService = OsrmRoutingService(client: mockClient);
        final route = await routingService.calculateMultistopRoute(
          origin: origin,
          waypoints: [wp1],
          destination: destination,
        );

        expect(route.totalDistanceKm, equals(120.0));
        expect(route.routePlan.estimatedDuration.inSeconds, equals(9000));
      },
    );

    test('lanza NoRouteFoundException cuando OSRM no encuentra ruta', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'code': 'NoRoute', 'message': 'No route'}),
          200,
        );
      });

      final routingService = OsrmRoutingService(client: mockClient);
      expect(
        () => routingService.calculateMultistopRoute(
          origin: origin,
          waypoints: [wp1],
          destination: destination,
        ),
        throwsA(isA<NoRouteFoundException>()),
      );
    });

    test('lanza HttpException ante código de estado distinto de 200', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Server Error', 500);
      });

      final routingService = OsrmRoutingService(client: mockClient);
      expect(
        () => routingService.calculateMultistopRoute(
          origin: origin,
          waypoints: [wp1],
          destination: destination,
        ),
        throwsA(isA<HttpException>()),
      );
    });

    test(
      'lanza InvalidRouteGeometryException cuando la ruta tiene geometría incompleta o corrupta',
      () async {
        final mockClient = MockClient((request) async {
          final jsonResponse = {
            'code': 'Ok',
            'routes': [
              {
                'distance': 100.0,
                'duration': 60.0,
                'geometry': {
                  'coordinates': [
                    [-74.0758, 4.5981], // Solo 1 punto: inválido
                  ],
                },
                'legs': [],
              },
            ],
          };
          return http.Response(jsonEncode(jsonResponse), 200);
        });

        final routingService = OsrmRoutingService(client: mockClient);
        expect(
          () => routingService.calculateMultistopRoute(
            origin: origin,
            waypoints: [wp1],
            destination: destination,
          ),
          throwsA(isA<InvalidRouteGeometryException>()),
        );
      },
    );
  });
}
