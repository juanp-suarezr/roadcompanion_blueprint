import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:road_companion/road_companion.dart';
import 'package:test/test.dart';

void main() {
  // Geometría de ruta de prueba: línea recta sobre latitud 5.0 desde lon -74.0 hasta -74.05
  // (~5.5 km de recorrido)
  final routeGeometry = [
    Coordinates(5.0000, -74.0000), // Origen (km 0.0)
    Coordinates(5.0000, -74.0250), // Punto intermedio (~2.75 km)
    Coordinates(5.0000, -74.0500), // Destino (~5.5 km)
  ];

  group('RoutePoiExplorerService - Búsqueda en Corredor Vial', () {
    test(
      'retorna lista vacía si la geometría de la ruta tiene menos de 2 puntos',
      () async {
        final mockClient = MockClient((_) async => http.Response('{}', 200));
        final explorer = RoutePoiExplorerService(
          osmPoiService: OsmPoiService(client: mockClient),
        );

        final resultsEmpty = await explorer.findPoisAlongRoute(
          routeGeometry: const [],
          category: 'fuel',
        );
        expect(resultsEmpty, isEmpty);

        final resultsSingle = await explorer.findPoisAlongRoute(
          routeGeometry: [Coordinates(5.0, -74.0)],
          category: 'fuel',
        );
        expect(resultsSingle, isEmpty);
      },
    );

    test(
      'incluye POI dentro del corredor y calcula distancia perpendicular y avance',
      () async {
        // POI a ~300 m al norte de la ruta (lat 5.0027 vs 5.0000) en el km ~2.75
        final mockClient = MockClient((request) async {
          final jsonResponse = {
            'elements': [
              {
                'type': 'node',
                'id': 1001,
                'lat': 5.0027,
                'lon': -74.0250,
                'tags': {
                  'name': 'Bomba Terpel Norte',
                  'amenity': 'fuel',
                  'addr:street': 'Troncal Central',
                },
              },
            ],
          };
          return http.Response(jsonEncode(jsonResponse), 200);
        });

        final explorer = RoutePoiExplorerService(
          osmPoiService: OsmPoiService(client: mockClient),
        );

        final pois = await explorer.findPoisAlongRoute(
          routeGeometry: routeGeometry,
          category: 'fuel',
          corridorRadiusMeters: 1000.0,
        );

        expect(pois.length, equals(1));
        final poi = pois.first;
        expect(poi.id, equals('osm_node_1001'));
        expect(poi.name, equals('Bomba Terpel Norte'));
        expect(poi.type, equals(TripStopType.fuel));
        // Distancia perpendicular a la calzada aproximada (~300 metros)
        expect(poi.distanceToRouteMeters, greaterThan(250.0));
        expect(poi.distanceToRouteMeters, lessThan(350.0));
        // Desvío estimado (~2 * distancia perpendicular)
        expect(
          poi.estimatedDetourMeters,
          closeTo(poi.distanceToRouteMeters * 2.0, 1.0),
        );
        // Distancia acumulada a lo largo de la ruta (~2.75 km)
        expect(poi.distanceAlongRouteMeters, greaterThan(2500.0));
        expect(poi.distanceAlongRouteMeters, lessThan(3000.0));
        expect(poi.hasIncompleteData, isFalse);
      },
    );

    test(
      'descarta POIs que están fuera del corredor vial configurado',
      () async {
        // POI a ~2.5 km de la calzada (lat 5.0225 vs 5.0000)
        final mockClient = MockClient((request) async {
          final jsonResponse = {
            'elements': [
              {
                'type': 'node',
                'id': 2001,
                'lat': 5.0225,
                'lon': -74.0250,
                'tags': {'name': 'Gasolinera Lejana', 'amenity': 'fuel'},
              },
            ],
          };
          return http.Response(jsonEncode(jsonResponse), 200);
        });

        final explorer = RoutePoiExplorerService(
          osmPoiService: OsmPoiService(client: mockClient),
        );

        // Con corredor de 1000 m (1 km), el punto a 2.5 km debe ser descartado
        final pois = await explorer.findPoisAlongRoute(
          routeGeometry: routeGeometry,
          category: 'fuel',
          corridorRadiusMeters: 1000.0,
        );

        expect(pois, isEmpty);
      },
    );

    test(
      'filtra resultados duplicados por ID y por proximidad espacial',
      () async {
        final mockClient = MockClient((request) async {
          final jsonResponse = {
            'elements': [
              {
                'type': 'node',
                'id': 3001,
                'lat': 5.0010,
                'lon': -74.0200,
                'tags': {'name': 'Taller Los Andes', 'shop': 'motorcycle'},
              },
              // Mismo ID
              {
                'type': 'node',
                'id': 3001,
                'lat': 5.0010,
                'lon': -74.0200,
                'tags': {'name': 'Taller Los Andes', 'shop': 'motorcycle'},
              },
              // Mismo nombre y ubicación a menos de 20 metros (duplicado en OSM)
              {
                'type': 'node',
                'id': 3002,
                'lat': 5.00105,
                'lon': -74.02005,
                'tags': {'name': 'Taller Los Andes', 'shop': 'motorcycle'},
              },
            ],
          };
          return http.Response(jsonEncode(jsonResponse), 200);
        });

        final explorer = RoutePoiExplorerService(
          osmPoiService: OsmPoiService(client: mockClient),
        );

        final pois = await explorer.findPoisAlongRoute(
          routeGeometry: routeGeometry,
          category: 'motorcycle_repair',
        );

        expect(pois.length, equals(1));
        expect(pois.first.name, equals('Taller Los Andes'));
      },
    );

    test(
      'reutiliza la caché interna evitando peticiones repetidas a la red',
      () async {
        int requestCount = 0;
        final mockClient = MockClient((request) async {
          requestCount++;
          final jsonResponse = {
            'elements': [
              {
                'type': 'node',
                'id': 4001,
                'lat': 5.0005,
                'lon': -74.0150,
                'tags': {'name': 'Mirador del Valle', 'tourism': 'viewpoint'},
              },
            ],
          };
          return http.Response(jsonEncode(jsonResponse), 200);
        });

        final explorer = RoutePoiExplorerService(
          osmPoiService: OsmPoiService(client: mockClient),
        );

        // Primera consulta: consulta la red
        final pois1 = await explorer.findPoisAlongRoute(
          routeGeometry: routeGeometry,
          category: 'viewpoint',
        );
        expect(pois1.length, equals(1));
        expect(requestCount, equals(1));

        // Segunda consulta idéntica: debe responder desde la caché
        final pois2 = await explorer.findPoisAlongRoute(
          routeGeometry: routeGeometry,
          category: 'viewpoint',
        );
        expect(pois2.length, equals(1));
        expect(requestCount, equals(1)); // No incrementó
      },
    );

    test(
      'gestiona errores de red y respuestas vacías retornando lista vacía',
      () async {
        final mockClient = MockClient((request) async {
          return http.Response('Server error', 503);
        });

        final explorer = RoutePoiExplorerService(
          osmPoiService: OsmPoiService(client: mockClient),
        );

        final pois = await explorer.findPoisAlongRoute(
          routeGeometry: routeGeometry,
          category: 'restaurant',
        );

        expect(pois, isEmpty);
      },
    );

    test(
      'identifica datos incompletos cuando el POI usa fallback por falta de nombre propio',
      () async {
        final mockClient = MockClient((request) async {
          final jsonResponse = {
            'elements': [
              {
                'type': 'node',
                'id': 5001,
                'lat': 5.0008,
                'lon': -74.0300,
                'tags': {
                  'amenity': 'fuel',
                  // Sin 'name' en tags: OsmPoiService genera 'Estación de Servicio / Gasolinera'
                },
              },
            ],
          };
          return http.Response(jsonEncode(jsonResponse), 200);
        });

        final explorer = RoutePoiExplorerService(
          osmPoiService: OsmPoiService(client: mockClient),
        );

        final pois = await explorer.findPoisAlongRoute(
          routeGeometry: routeGeometry,
          category: 'fuel',
        );

        expect(pois.length, equals(1));
        expect(pois.first.hasIncompleteData, isTrue);
      },
    );
  });
}
