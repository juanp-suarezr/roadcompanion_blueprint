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
      coordinates: Coordinates(5.0687, -75.5172), // A ~30m pero "Catedral" está solo en subtítulo
      category: 'bakery',
    );

    test('1. Sin GPS (userLocation nulo) conserva estrictamente el orden del proveedor', () {
      final input = [destCatedralZipaquira, destCatedralManizales, destPanaderia];

      final output = rankDestinations(
        results: input,
        query: 'Catedral',
        userLocation: null,
      );

      expect(output, equals(input));
      expect(output.first.id, equals('3'));
    });

    test('2. Prioriza coincidencia exacta de nombre sobre cualquier cercanía', () {
      final input = [
        destCatedralManizales, // A 10 metros del usuario
        destManizales, // Exact match "Manizales"
      ];

      final userLoc = Coordinates(5.0688, -75.5173); // Justo frente a la catedral

      final output = rankDestinations(
        results: input,
        query: 'Manizales',
        userLocation: userLoc,
      );

      // El nombre exacto "Manizales" debe ser el primero (Tier 0)
      expect(output.first.id, equals('1'));
      expect(output.last.id, equals('2'));
    });

    test('3. A igual nivel de relevancia por nombre, prioriza el lugar más cercano al GPS', () {
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
    });

    test('4. La proximidad no sustituye la coincidencia de nombre', () {
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
    });

    test('5. Lista vacía retorna lista vacía sin excepciones', () {
      final output = rankDestinations(
        results: [],
        query: 'algo',
        userLocation: Coordinates(5.0, -75.0),
      );
      expect(output, isEmpty);
    });

    test('6. getDestinationCategoryIcon retorna iconos correspondientes', () {
      expect(getDestinationCategoryIcon('fuel'), equals(Icons.local_gas_station));
      expect(getDestinationCategoryIcon('gas_station'), equals(Icons.local_gas_station));
      expect(getDestinationCategoryIcon('restaurant'), equals(Icons.restaurant));
      expect(getDestinationCategoryIcon('hotel'), equals(Icons.hotel));
      expect(getDestinationCategoryIcon('volcano'), equals(Icons.terrain));
      expect(getDestinationCategoryIcon('city'), equals(Icons.location_city));
      expect(getDestinationCategoryIcon(null), equals(Icons.place));
      expect(getDestinationCategoryIcon('unknown_xyz'), equals(Icons.place));
    });
  });
}
