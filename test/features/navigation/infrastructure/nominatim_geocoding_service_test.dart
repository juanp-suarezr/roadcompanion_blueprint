import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:road_companion/domain/entities/coordinates.dart';
import 'package:road_companion/features/navigation/infrastructure/services/nominatim_geocoding_service.dart';

void main() {
  group('NominatimGeocodingService - Pruebas de Geocodificación y Búsqueda', () {
    test(
      '1. Retorna lista de destinos estructurada ante respuesta HTTP 200 válida',
      () async {
        final mockClient = MockClient((request) async {
          expect(request.url.host, equals('nominatim.openstreetmap.org'));
          expect(request.url.path, equals('/search'));
          expect(request.headers['User-Agent'], contains('REstelar'));

          final sampleJson = jsonEncode([
            {
              'place_id': 12345,
              'name': 'Catedral Basílica de Manizales',
              'display_name':
                  'Catedral Basílica de Manizales, Carrera 22, Manizales, Caldas, Colombia',
              'lat': '5.06889',
              'lon': '-75.51738',
              'type': 'place_of_worship',
            },
            {
              'place_id': 67890,
              'name': 'Nevado del Ruiz',
              'display_name': 'Nevado del Ruiz, Villamaría, Caldas, Colombia',
              'lat': '4.89528',
              'lon': '-75.32222',
              'type': 'volcano',
            },
          ]);

          return http.Response(
            sampleJson,
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final service = NominatimGeocodingService(client: mockClient);
        final results = await service.search('Manizales');

        expect(results.length, equals(2));
        expect(results.first.title, equals('Catedral Basílica de Manizales'));
        expect(results.first.coordinates.latitude, closeTo(5.06889, 0.0001));
        expect(results.first.coordinates.longitude, closeTo(-75.51738, 0.0001));
        expect(results.first.category, equals('place_of_worship'));

        expect(results.last.title, equals('Nevado del Ruiz'));
      },
    );

    test(
      '2. Retorna lista vacía si la consulta es menor a 2 caracteres o vacía',
      () async {
        final service = NominatimGeocodingService(
          client: MockClient((_) async => http.Response('[]', 200)),
        );
        expect(await service.search(''), isEmpty);
        expect(await service.search(' '), isEmpty);
        expect(await service.search('a'), isEmpty);
      },
    );

    test(
      '3. Lanza excepción explicativa ante error del servidor (HTTP 500)',
      () async {
        final mockClient = MockClient(
          (_) async => http.Response('Internal Server Error', 500),
        );
        final service = NominatimGeocodingService(client: mockClient);

        expect(() => service.search('Bogotá'), throwsException);
      },
    );

    test('4. Realiza geocodificación inversa con éxito', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/reverse'));
        final sampleJson = jsonEncode({
          'place_id': 999,
          'name': 'Plaza de Bolívar',
          'display_name': 'Plaza de Bolívar, Manizales, Caldas, Colombia',
          'type': 'plaza',
        });
        return http.Response(sampleJson, 200);
      });

      final service = NominatimGeocodingService(client: mockClient);
      final dest = await service.reverseGeocode(
        Coordinates(5.068, -75.517),
      );

      expect(dest, isNotNull);
      expect(dest!.title, equals('Plaza de Bolívar'));
    });

    test('5. Envía parámetro limit configurable (default 10) y viewbox con bounded=0', () async {
      late Uri capturedUri;
      final mockClient = MockClient((request) async {
        capturedUri = request.url;
        return http.Response('[]', 200, headers: {'content-type': 'application/json'});
      });

      final service = NominatimGeocodingService(client: mockClient);
      await service.search(
        'Gasolinera',
        proximityHint: Coordinates(5.068, -75.517),
        limit: 10,
      );

      expect(capturedUri.queryParameters['limit'], equals('10'));
      expect(capturedUri.queryParameters['bounded'], equals('0'));
      expect(capturedUri.queryParameters['viewbox'], isNotNull);
    });

    test('6. Procesa hasta 10 resultados devueltos por el proveedor sin truncar a 2', () async {
      final tenResults = List.generate(10, (i) => {
        'place_id': i + 1,
        'name': 'Punto $i',
        'display_name': 'Punto $i, Vía $i, Manizales, Caldas, Colombia',
        'lat': '${5.0 + (i * 0.01)}',
        'lon': '-75.5',
        'type': 'attraction',
      });

      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode(tenResults), 200, headers: {'content-type': 'application/json'});
      });

      final service = NominatimGeocodingService(client: mockClient);
      final results = await service.search('Punto', limit: 10);

      expect(results.length, equals(10));
      expect(results.first.title, equals('Punto 0'));
      expect(results.last.title, equals('Punto 9'));
    });

    test('7. Extrae municipio y departamento a partir de address details estructurado', () async {
      final sampleItem = [
        {
          'place_id': 777,
          'name': 'Mirador de Chipre',
          'display_name': 'Mirador de Chipre, Carrera 15, Manizales, Caldas, 170001, Colombia',
          'lat': '5.071',
          'lon': '-75.524',
          'type': 'viewpoint',
          'address': {
            'road': 'Carrera 15',
            'city': 'Manizales',
            'state': 'Caldas',
            'country': 'Colombia',
          },
        },
      ];

      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode(sampleItem), 200, headers: {'content-type': 'application/json'});
      });

      final service = NominatimGeocodingService(client: mockClient);
      final results = await service.search('Chipre');

      expect(results.length, equals(1));
      expect(results.first.title, equals('Mirador de Chipre'));
      expect(results.first.subtitle, equals('Carrera 15, Manizales, Caldas'));
    });
  });
}
