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
  });
}
