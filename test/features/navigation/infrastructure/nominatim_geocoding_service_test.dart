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
      final dest = await service.reverseGeocode(Coordinates(5.068, -75.517));

      expect(dest, isNotNull);
      expect(dest!.title, equals('Plaza de Bolívar'));
    });

    test(
      '5. Envía parámetro limit configurable (default 10) y viewbox con bounded=0',
      () async {
        late Uri capturedUri;
        final mockClient = MockClient((request) async {
          capturedUri = request.url;
          return http.Response(
            '[]',
            200,
            headers: {'content-type': 'application/json'},
          );
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
      },
    );

    test(
      '6. Procesa hasta 10 resultados devueltos por el proveedor sin truncar a 2',
      () async {
        final tenResults = List.generate(
          10,
          (i) => {
            'place_id': i + 1,
            'name': 'Punto $i',
            'display_name': 'Punto $i, Vía $i, Manizales, Caldas, Colombia',
            'lat': '${5.0 + (i * 0.01)}',
            'lon': '-75.5',
            'type': 'attraction',
          },
        );

        final mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode(tenResults),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final service = NominatimGeocodingService(client: mockClient);
        final results = await service.search('Punto', limit: 10);

        expect(results.length, equals(10));
        expect(results.first.title, equals('Punto 0'));
        expect(results.last.title, equals('Punto 9'));
      },
    );

    test(
      '7. Extrae municipio y departamento a partir de address details estructurado',
      () async {
        final sampleItem = [
          {
            'place_id': 777,
            'name': 'Mirador de Chipre',
            'display_name':
                'Mirador de Chipre, Carrera 15, Manizales, Caldas, 170001, Colombia',
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
          return http.Response(
            jsonEncode(sampleItem),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final service = NominatimGeocodingService(client: mockClient);
        final results = await service.search('Chipre');

        expect(results.length, equals(1));
        expect(results.first.title, equals('Mirador de Chipre'));
        expect(results.first.subtitle, equals('Carrera 15, Manizales, Caldas'));
      },
    );

    test(
      '8. Buscar gasolineras con GPS en Pereira utiliza amenity=fuel, viewbox y bounded=1',
      () async {
        final pereiraGps = Coordinates(4.8133, -75.6961);
        late Uri capturedUri;

        final mockStations = [
          {
            'place_id': 101,
            'name': 'EDS El Viaducto',
            'display_name':
                'EDS El Viaducto, Dosquebradas, Risaralda, Colombia',
            'lat': '4.8259',
            'lon': '-75.6852',
            'type': 'fuel',
            'address': {
              'road': 'Avenida del Ferrocarril',
              'city': 'Pereira',
              'state': 'Risaralda',
            },
          },
          {
            'place_id': 102,
            'name': 'Econogas Pereira',
            'display_name':
                'Econogas Pereira, Calle 14, Pereira, Risaralda, Colombia',
            'lat': '4.8017',
            'lon': '-75.6927',
            'type': 'fuel',
            'address': {
              'road': 'Calle 14',
              'city': 'Pereira',
              'state': 'Risaralda',
            },
          },
        ];

        final mockClient = MockClient((request) async {
          capturedUri = request.url;
          expect(request.url.queryParameters['amenity'], equals('fuel'));
          expect(request.url.queryParameters['bounded'], equals('1'));
          expect(request.url.queryParameters['viewbox'], isNotNull);

          return http.Response(
            jsonEncode(mockStations),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final service = NominatimGeocodingService(client: mockClient);
        final results = await service.searchNearbyCategory(
          category: 'fuel',
          center: pereiraGps,
          limit: 10,
        );

        expect(results.length, equals(2));
        expect(results.any((d) => d.title.contains('El Viaducto')), isTrue);
        expect(results.any((d) => d.title.contains('Econogas')), isTrue);
        expect(capturedUri.queryParameters['bounded'], equals('1'));
      },
    );

    test(
      '9. Rechaza resultados de otros países en una búsqueda local de gasolineras',
      () async {
        final pereiraGps = Coordinates(4.8133, -75.6961);

        // Simula que Nominatim devolvió por error un resultado distante de España
        final mixedResults = [
          {
            'place_id': 888,
            'name': 'Gasolinera Barajas Madrid',
            'display_name': 'Gasolinera Barajas, Madrid, España',
            'lat': '40.4168',
            'lon': '-3.7038', // Coordenadas en España (~8000 km de Pereira)
            'type': 'fuel',
          },
          {
            'place_id': 999,
            'name': 'Terpel Centro Pereira',
            'display_name':
                'Terpel Centro, Carrera 8, Pereira, Risaralda, Colombia',
            'lat': '4.8140',
            'lon': '-75.6950', // Local en Pereira
            'type': 'fuel',
            'address': {
              'road': 'Carrera 8',
              'city': 'Pereira',
              'state': 'Risaralda',
            },
          },
        ];

        final mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode(mixedResults),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final service = NominatimGeocodingService(client: mockClient);
        final results = await service.searchNearbyCategory(
          category: 'fuel',
          center: pereiraGps,
        );

        // El resultado de España debe ser descartado estrictamente por el filtro geodésico
        expect(results.length, equals(1));
        expect(results.first.title, equals('Terpel Centro Pereira'));
        expect(results.any((d) => d.title.contains('Madrid')), isFalse);
      },
    );

    test(
      '10. Ordena estaciones de servicio ascendentemente por distancia real desde el usuario',
      () async {
        final userGps = Coordinates(4.8133, -75.6961); // Plaza Bolívar Pereira

        final stations = [
          {
            'place_id': 1,
            'name': 'Estación Lejana Dosquebradas',
            'lat': '4.8500',
            'lon': '-75.6700', // ~5.0 km
            'type': 'fuel',
          },
          {
            'place_id': 2,
            'name': 'Estación Muy Cercana Centro',
            'lat': '4.8145',
            'lon': '-75.6955', // ~150 metros
            'type': 'fuel',
          },
          {
            'place_id': 3,
            'name': 'Estación Media Invico',
            'lat': '4.8250',
            'lon': '-75.6900', // ~1.5 km
            'type': 'fuel',
          },
        ];

        final mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode(stations),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final service = NominatimGeocodingService(client: mockClient);
        final results = await service.searchNearbyCategory(
          category: 'fuel',
          center: userGps,
        );

        expect(results.length, equals(3));
        expect(results[0].title, equals('Estación Muy Cercana Centro'));
        expect(results[1].title, equals('Estación Media Invico'));
        expect(results[2].title, equals('Estación Lejana Dosquebradas'));

        final dist0 = userGps.distanceTo(results[0].coordinates);
        final dist1 = userGps.distanceTo(results[1].coordinates);
        final dist2 = userGps.distanceTo(results[2].coordinates);
        expect(dist0 < dist1 && dist1 < dist2, isTrue);
      },
    );

    test(
      '11. Busca una ciudad distante cuando el usuario la solicita explícitamente (ej. Cali desde Pereira)',
      () async {
        final pereiraGps = Coordinates(4.8133, -75.6961);

        final caliResult = [
          {
            'place_id': 5555,
            'name': 'Cali',
            'display_name': 'Cali, Valle del Cauca, RAP Pacífico, Colombia',
            'lat': '3.4516',
            'lon': '-76.5320',
            'type': 'city',
            'address': {
              'city': 'Cali',
              'state': 'Valle del Cauca',
              'country': 'Colombia',
            },
          },
        ];

        late Uri capturedUri;
        final mockClient = MockClient((request) async {
          capturedUri = request.url;
          expect(request.url.queryParameters['q'], equals('Cali'));
          expect(
            request.url.queryParameters['bounded'],
            equals('0'),
          ); // Permite ciudades lejanas
          expect(request.url.queryParameters['countrycodes'], equals('co'));

          return http.Response(
            jsonEncode(caliResult),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final service = NominatimGeocodingService(client: mockClient);
        final results = await service.search('Cali', proximityHint: pereiraGps);

        expect(results.length, equals(1));
        expect(results.first.title, equals('Cali'));
        expect(results.first.subtitle, contains('Valle del Cauca'));
        expect(capturedUri.queryParameters['bounded'], equals('0'));
      },
    );

    test(
      '12. Desambigua homónimos geográficos del destino Guadalupe con municipios y departamentos claros',
      () async {
        final guadalupeHomonyms = [
          {
            'place_id': 201,
            'name': 'Guadalupe',
            'display_name':
                'Guadalupe, Dosquebradas, Risaralda, RAP Eje Cafetero, Colombia',
            'lat': '4.8366',
            'lon': '-75.6723',
            'type': 'administrative',
            'address': {
              'suburb': 'Guadalupe',
              'town': 'Dosquebradas',
              'state': 'Risaralda',
              'country': 'Colombia',
            },
          },
          {
            'place_id': 202,
            'name': 'Guadalupe',
            'display_name': 'Guadalupe, Centro, Huila, Colombia',
            'lat': '2.0248',
            'lon': '-75.7564',
            'type': 'administrative',
            'address': {
              'municipality': 'Guadalupe',
              'state': 'Huila',
              'country': 'Colombia',
            },
          },
          {
            'place_id': 203,
            'name': 'Guadalupe',
            'display_name': 'Guadalupe, Comunera, Santander, Colombia',
            'lat': '6.2468',
            'lon': '-73.4181',
            'type': 'administrative',
            'address': {
              'municipality': 'Guadalupe',
              'state': 'Santander',
              'country': 'Colombia',
            },
          },
        ];

        final mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode(guadalupeHomonyms),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final service = NominatimGeocodingService(client: mockClient);
        final results = await service.search('Guadalupe');

        expect(results.length, equals(3));
        expect(results[0].subtitle, contains('Risaralda'));
        expect(results[1].subtitle, contains('Huila'));
        expect(results[2].subtitle, contains('Santander'));
      },
    );
  });
}
