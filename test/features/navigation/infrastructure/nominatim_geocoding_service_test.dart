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
          expect(request.headers['User-Agent'], contains('Estela'));

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
        const Coordinates(5.068, -75.517),
      );

      expect(dest, isNotNull);
      expect(dest!.title, equals('Plaza de Bolívar'));
    });
  });
}
