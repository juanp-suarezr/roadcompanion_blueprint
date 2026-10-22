import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:road_companion/domain/entities/coordinates.dart';
import 'package:road_companion/features/navigation/domain/services/osm_poi_service.dart';

void main() {
  group('OsmPoiService - Consulta de POIs en Overpass API', () {
    test(
      '1. Consulta y parsea POIs de talleres de motocicletas correctamente',
      () async {
        final mockClient = MockClient((request) async {
          expect(request.url.host, equals('overpass-api.de'));
          final data = request.url.queryParameters['data'] ?? '';
          expect(data, contains('shop"="motorcycle"'));

          final sampleResponse = {
            'elements': [
              {
                'type': 'node',
                'id': 1001,
                'lat': 4.8145,
                'lon': -75.6942,
                'tags': {
                  'name': 'Taller Moto Sport',
                  'shop': 'motorcycle',
                  'addr:street': 'Carrera 7',
                },
              },
              {
                'type': 'node',
                'id': 1002,
                'lat': 4.8160,
                'lon': -75.6920,
                'tags': {
                  'name': 'ServiMotos Pereira',
                  'amenity': 'motorcycle_repair',
                },
              },
            ],
          };

          return http.Response(
            jsonEncode(sampleResponse),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        });

        final service = OsmPoiService(client: mockClient);
        final results = await service.fetchCategoryPois(
          categoryKey: 'motorcycle_repair',
          center: Coordinates(4.8133, -75.6961),
          deltaDegrees: 0.045,
          limit: 10,
        );

        expect(results.length, equals(2));
        expect(results.first.title, equals('Taller Moto Sport'));
        expect(results.first.category, equals('motorcycle_repair'));
        expect(results.first.coordinates.latitude, equals(4.8145));
        expect(results.last.title, equals('ServiMotos Pereira'));
      },
    );

    test(
      '2. Utiliza caché en memoria para llamadas subsecuentes idénticas',
      () async {
        int requestCount = 0;
        final mockClient = MockClient((request) async {
          requestCount++;
          return http.Response(
            jsonEncode({
              'elements': [
                {
                  'type': 'node',
                  'id': 2001,
                  'lat': 4.8333,
                  'lon': -75.6724,
                  'tags': {'name': 'Montallantas El Paisa', 'shop': 'tyres'},
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final service = OsmPoiService(client: mockClient);
        final center = Coordinates(4.8333, -75.6724);

        // Primera consulta
        final res1 = await service.fetchCategoryPois(
          categoryKey: 'tyres',
          center: center,
          deltaDegrees: 0.045,
        );
        expect(res1.length, equals(1));
        expect(requestCount, equals(1));

        // Segunda consulta: debe retornar desde caché
        final res2 = await service.fetchCategoryPois(
          categoryKey: 'tyres',
          center: center,
          deltaDegrees: 0.045,
        );
        expect(res2.length, equals(1));
        expect(requestCount, equals(1)); // Sin nueva petición de red
      },
    );

    test(
      '3. Construye consultas Overpass con filtros adecuados para iglesias, barberías y centros comerciales',
      () async {
        final requestedQueries = <String>[];
        final mockClient = MockClient((request) async {
          requestedQueries.add(request.url.queryParameters['data'] ?? '');
          return http.Response(
            jsonEncode({'elements': []}),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final service = OsmPoiService(client: mockClient);
        final center = Coordinates(4.8133, -75.6961);

        await service.fetchCategoryPois(
          categoryKey: 'place_of_worship',
          center: center,
          deltaDegrees: 0.045,
        );
        expect(requestedQueries.last, contains('amenity"="place_of_worship"'));

        await service.fetchCategoryPois(
          categoryKey: 'mall',
          center: center,
          deltaDegrees: 0.045,
        );
        expect(requestedQueries.last, contains('shop"="mall"'));

        await service.fetchCategoryPois(
          categoryKey: 'hairdresser',
          center: center,
          deltaDegrees: 0.045,
        );
        expect(requestedQueries.last, contains('shop"="hairdresser"'));
      },
    );
  });
}
