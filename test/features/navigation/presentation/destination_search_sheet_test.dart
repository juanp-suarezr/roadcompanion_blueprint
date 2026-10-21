import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_companion/domain/entities/coordinates.dart';
import 'package:road_companion/features/navigation/domain/entities/destination.dart';
import 'package:road_companion/features/navigation/domain/services/geocoding_service.dart';
import 'package:road_companion/features/navigation/presentation/widgets/destination_search_sheet.dart';

class _FakeGeocodingService implements GeocodingService {
  int searchCalls = 0;
  int searchNearbyCalls = 0;
  bool shouldThrow = false;
  List<Destination> nearbyReturn = [];
  List<Destination> searchReturn = [];

  @override
  Future<List<Destination>> search(
    String query, {
    Coordinates? proximityHint,
    int limit = 10,
  }) async {
    searchCalls++;
    if (shouldThrow) throw Exception('Network error');
    return searchReturn;
  }

  @override
  Future<List<Destination>> searchNearbyCategory({
    required String category,
    required Coordinates center,
    int limit = 15,
  }) async {
    searchNearbyCalls++;
    if (shouldThrow) throw Exception('Network error');
    return nearbyReturn;
  }

  @override
  Future<Destination?> reverseGeocode(Coordinates coordinates) async => null;
}

void main() {
  group('DestinationSearchSheet - Pruebas de Búsqueda Local y Categorías', () {
    testWidgets(
      '1. Buscar "gasolina" sin GPS muestra advertencia solicitando GPS sin llamar a la API global',
      (tester) async {
        final fakeService = _FakeGeocodingService();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DestinationSearchSheet(
                geocodingService: fakeService,
                userLocation: null, // Sin GPS
                onDestinationSelected: (_) {},
              ),
            ),
          ),
        );

        // Escribir "gasolina" en el buscador
        final searchField = find.byType(TextField);
        expect(searchField, findsOneWidget);
        await tester.enterText(searchField, 'gasolina');

        // Avanzar el timer de debounce (500 ms)
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();

        // No debe haber llamado a la API global ni a la API de cercanos
        expect(fakeService.searchCalls, equals(0));
        expect(fakeService.searchNearbyCalls, equals(0));

        // Debe mostrar el mensaje informativo
        expect(
          find.textContaining('Búsqueda local de "gasolina"'),
          findsOneWidget,
        );
        expect(
          find.textContaining('activa la ubicación GPS de tu teléfono'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '2. Buscar "gasolina" con GPS utiliza searchNearbyCategory y muestra resultados',
      (tester) async {
        final fakeService = _FakeGeocodingService()
          ..nearbyReturn = [
            Destination(
              id: 'eds_1',
              title: 'EDS Terpel El Viaducto',
              subtitle: 'Avenida del Ferrocarril, Pereira',
              coordinates: Coordinates(4.825, -75.685),
              category: 'fuel',
            ),
          ];

        final userGps = Coordinates(4.8133, -75.6961);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DestinationSearchSheet(
                geocodingService: fakeService,
                userLocation: userGps,
                onDestinationSelected: (_) {},
              ),
            ),
          ),
        );

        final searchField = find.byType(TextField);
        await tester.enterText(searchField, 'gasolina');

        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();

        // Debe haber llamado exclusivamente a searchNearbyCategory
        expect(fakeService.searchNearbyCalls, equals(1));
        expect(fakeService.searchCalls, equals(0));

        expect(find.text('EDS Terpel El Viaducto'), findsOneWidget);
      },
    );

    testWidgets(
      '3. Error de conexión muestra botón Reintentar y permite repetir la búsqueda',
      (tester) async {
        final fakeService = _FakeGeocodingService()
          ..shouldThrow = true
          ..searchReturn = [
            Destination(
              id: 'p1',
              title: 'Guadalupe Dosquebradas',
              subtitle: 'Risaralda',
              coordinates: Coordinates(4.836, -75.672),
            ),
          ];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DestinationSearchSheet(
                geocodingService: fakeService,
                userLocation: Coordinates(4.8133, -75.6961),
                onDestinationSelected: (_) {},
              ),
            ),
          ),
        );

        final searchField = find.byType(TextField);
        await tester.enterText(searchField, 'Guadalupe');

        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();

        // Debe mostrar error y botón Reintentar
        expect(find.text('Reintentar'), findsOneWidget);
        expect(fakeService.searchCalls, equals(1));

        // Resolver error y pulsar Reintentar
        fakeService.shouldThrow = false;
        await tester.tap(find.text('Reintentar'));
        await tester.pumpAndSettle();

        expect(fakeService.searchCalls, equals(2));
        expect(find.text('Guadalupe Dosquebradas'), findsOneWidget);
      },
    );
  });
}
