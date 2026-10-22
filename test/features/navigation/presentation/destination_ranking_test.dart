import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_companion/domain/entities/coordinates.dart';
import 'package:road_companion/features/navigation/domain/entities/destination.dart';
import 'package:road_companion/features/navigation/presentation/widgets/destination_search_sheet.dart';

void main() {
  group('rankDestinations - Ordenamiento y priorización de resultados de búsqueda', () {
    final destManizales = Destination(
      id: '1',
      title: 'Manizales',
      subtitle: 'Caldas, Colombia',
      coordinates: Coordinates(5.0689, -75.5174),
      category: 'city',
    );

    final destCatedralManizales = Destination(
      id: '2',
      title: 'Catedral Basílica de Manizales',
      subtitle: 'Carrera 22, Manizales, Caldas',
      coordinates: Coordinates(5.0688, -75.5173), // A ~20m del centro
      category: 'place_of_worship',
    );

    final destCatedralZipaquira = Destination(
      id: '3',
      title: 'Catedral de Sal de Zipaquirá',
      subtitle: 'Zipaquirá, Cundinamarca',
      coordinates: Coordinates(5.0192, -74.0044), // A ~160km
      category: 'tourism',
    );

    final destPanaderia = Destination(
      id: '4',
      title: 'Panadería La Espiga',
      subtitle: 'Cerca a la Catedral, Manizales',
      coordinates: Coordinates(
        5.0687,
        -75.5172,
      ), // A ~30m pero "Catedral" está solo en subtítulo
      category: 'bakery',
    );

    // Gasolineras para pruebas de categoría
    final gasolineraLejana = Destination(
      id: 'gas_far',
      title: 'Gasolineras del Norte S.A.S.',
      subtitle: 'Chinchiná, Caldas',
      coordinates: Coordinates(4.9810, -75.6040), // A ~20 km
      category: 'fuel',
    );

    final gasolineraCercana = Destination(
      id: 'gas_near',
      title: 'Estación de Servicio Terpel Los Cedros',
      subtitle: 'Avenida Santander, Manizales',
      coordinates: Coordinates(5.0695, -75.5160), // A ~2 km
      category: 'fuel',
    );

    test(
      '1. Sin GPS (userLocation nulo) conserva estrictamente el orden del proveedor',
      () {
        final input = [
          destCatedralZipaquira,
          destCatedralManizales,
          destPanaderia,
        ];

        final output = rankDestinations(
          results: input,
          query: 'Catedral',
          userLocation: null,
        );

        expect(output, equals(input));
        expect(output.first.id, equals('3'));
      },
    );

    test(
      '2. Prioriza coincidencia exacta de nombre en lugar específico (ej. "Manizales")',
      () {
        final input = [
          destCatedralManizales, // A 10 metros del usuario
          destManizales, // Exact match "Manizales"
        ];

        final userLoc = Coordinates(
          5.0688,
          -75.5173,
        ); // Justo frente a la catedral

        final output = rankDestinations(
          results: input,
          query: 'Manizales',
          userLocation: userLoc,
        );

        // El nombre exacto "Manizales" debe ser el primero (Tier 0)
        expect(output.first.id, equals('1'));
        expect(output.last.id, equals('2'));
      },
    );

    test(
      '3. Búsqueda por ciudad ("Armenia") prioriza el nombre exacto de la ciudad sobre comercios cercanos',
      () {
        final destPanaderiaArmenia = Destination(
          id: 'pan_arm',
          title: 'Panadería Armenia Tradicional',
          subtitle: 'Manizales, Caldas',
          coordinates: Coordinates(
            5.0689,
            -75.5170,
          ), // A 40 metros del usuario en Manizales
          category: 'bakery',
        );

        final destCiudadArmenia = Destination(
          id: 'city_arm',
          title: 'Armenia',
          subtitle: 'Quindío, Colombia',
          coordinates: Coordinates(4.5338, -75.6811), // A ~80 km en Quindío
          category: 'city',
        );

        final output = rankDestinations(
          results: [destPanaderiaArmenia, destCiudadArmenia],
          query: 'Armenia',
          userLocation: Coordinates(5.0689, -75.5174),
        );

        // La ciudad de Armenia tiene coincidencia nominal exacta (Tier 0) y no debe ser desplazada por una panadería
        expect(output.first.id, equals('city_arm'));
      },
    );

    test(
      '4. Búsqueda por categoría ("gasolineras") con GPS ubica primero la más cercana (2 km vs 20 km)',
      () {
        final userLoc = Coordinates(5.0689, -75.5174);
        final input = [gasolineraLejana, gasolineraCercana];

        final output = rankDestinations(
          results: input,
          query: 'gasolineras',
          userLocation: userLoc,
        );

        // Aunque gasolineraLejana tenga la palabra "Gasolineras" en su título,
        // la búsqueda por categoría pondera la proximidad real y pone primero la estación a 2 km
        expect(output.first.id, equals('gas_near'));
        expect(output.last.id, equals('gas_far'));
      },
    );

    test('5. Consulta "gasolineras cerca de mí" prioriza proximidad alta', () {
      final userLoc = Coordinates(5.0689, -75.5174);
      final input = [gasolineraLejana, gasolineraCercana];

      final output = rankDestinations(
        results: input,
        query: 'gasolineras cerca de mí',
        userLocation: userLoc,
      );

      expect(output.first.id, equals('gas_near'));
    });

    test(
      '6. A igual nivel de relevancia por nombre en lugar específico, prioriza el más cercano',
      () {
        final input = [destCatedralZipaquira, destCatedralManizales];
        final userLocManizales = Coordinates(5.0689, -75.5174);

        final output = rankDestinations(
          results: input,
          query: 'Catedral',
          userLocation: userLocManizales,
        );

        // Ambas contienen "Catedral" en el título (Tier 1/2), pero la de Manizales está a 100m vs 160km
        expect(output.first.id, equals('2'));
        expect(output.last.id, equals('3'));
      },
    );

    test(
      '7. En lugar específico, la proximidad no sustituye la coincidencia de nombre',
      () {
        final input = [destPanaderia, destCatedralZipaquira];
        final userLocManizales = Coordinates(5.0689, -75.5174);

        final output = rankDestinations(
          results: input,
          query: 'Catedral',
          userLocation: userLocManizales,
        );

        // La panadería está al lado (30m) pero "Catedral" está en subtítulo (Tier 3).
        // La Catedral de Zipaquirá tiene "Catedral" en su título (Tier 1).
        // Debe anteponerse la que realmente se llama Catedral.
        expect(output.first.id, equals('3'));
        expect(output.last.id, equals('4'));
      },
    );

    test('8. Lista vacía retorna lista vacía sin excepciones', () {
      final output = rankDestinations(
        results: [],
        query: 'algo',
        userLocation: Coordinates(5.0, -75.0),
      );
      expect(output, isEmpty);
    });

    test(
      '9. Resultados con nombres idénticos y distancias iguales mantienen orden estable',
      () {
        final d1 = Destination(
          id: 'a',
          title: 'Estación Terpel',
          subtitle: 'Sector 1',
          coordinates: Coordinates(5.0, -75.0),
          category: 'fuel',
        );
        final d2 = Destination(
          id: 'b',
          title: 'Estación Terpel',
          subtitle: 'Sector 2',
          coordinates: Coordinates(5.0, -75.0),
          category: 'fuel',
        );

        final output = rankDestinations(
          results: [d1, d2],
          query: 'gasolineras',
          userLocation: Coordinates(5.0, -75.0),
        );

        expect(output.length, equals(2));
        expect(output[0].id, equals('a'));
        expect(output[1].id, equals('b'));
      },
    );

    test('10. getDestinationCategoryIcon retorna iconos correspondientes', () {
      expect(
        getDestinationCategoryIcon('fuel'),
        equals(Icons.local_gas_station),
      );
      expect(
        getDestinationCategoryIcon('gas_station'),
        equals(Icons.local_gas_station),
      );
      expect(
        getDestinationCategoryIcon('restaurant'),
        equals(Icons.restaurant),
      );
      expect(getDestinationCategoryIcon('hotel'), equals(Icons.hotel));
      expect(getDestinationCategoryIcon('volcano'), equals(Icons.terrain));
      expect(getDestinationCategoryIcon('city'), equals(Icons.location_city));
      expect(getDestinationCategoryIcon(null), equals(Icons.place));
      expect(getDestinationCategoryIcon('unknown_xyz'), equals(Icons.place));
    });

    test(
      '11. isCategoryQuery clasifica gasolina y singular/plural sin confundir ciudades',
      () {
        expect(isCategoryQuery('gasolina'), isTrue);
        expect(isCategoryQuery('gasolinas'), isTrue);
        expect(isCategoryQuery('gasolinera'), isTrue);
        expect(isCategoryQuery('estaciones de servicio'), isTrue);
        expect(isCategoryQuery('restaurantes'), isTrue);
        expect(isCategoryQuery('talleres de motos'), isTrue);

        // Ciudades no deben confundirse con categorías
        expect(isCategoryQuery('Guadalupe'), isFalse);
        expect(isCategoryQuery('guadalupe'), isFalse);
        expect(isCategoryQuery('Pereira'), isFalse);
        expect(isCategoryQuery('Armenia'), isFalse);
        expect(isCategoryQuery('Manizales'), isFalse);
        expect(isCategoryQuery('Bogotá'), isFalse);

        // Resolución de llave semántica de categoría
        expect(resolveCategoryKey('gasolina'), equals('fuel'));
        expect(resolveCategoryKey('gasolinas'), equals('fuel'));
        expect(resolveCategoryKey('estaciones de servicio'), equals('fuel'));
        expect(
          resolveCategoryKey('talleres de motos'),
          equals('motorcycle_repair'),
        );
        expect(resolveCategoryKey('restaurantes'), equals('restaurant'));
      },
    );
  });
}
