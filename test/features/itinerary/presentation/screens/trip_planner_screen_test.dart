import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_companion/road_companion.dart';

void main() {
  final origin = Destination(
    id: 'orig',
    title: 'Bogotá',
    subtitle: 'Bogotá, Colombia',
    coordinates: Coordinates(4.5981, -74.0758),
  );

  final destination = Destination(
    id: 'dest',
    title: 'Villa de Leyva',
    subtitle: 'Boyacá, Colombia',
    coordinates: Coordinates(5.6322, -73.5244),
  );

  final s1 = TripStop(
    id: 's1',
    name: 'Parada Briceño',
    coordinates: Coordinates(4.9351, -73.9921),
    type: TripStopType.fuel,
    orderIndex: 0,
  );

  final now = DateTime(2026, 10, 22, 10, 0, 0);

  group('TripPlannerScreen - Widget Tests', () {
    testWidgets('renderiza origen, destino y paradas del itinerario inicial', (
      tester,
    ) async {
      final itinerary = TripItinerary(
        id: 'trip_1',
        title: 'Mi Viaje',
        origin: origin,
        destination: destination,
        stops: [s1],
        createdAt: now,
        updatedAt: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: TripPlannerScreen(
            initialItinerary: itinerary,
            navigationLauncher: UrlExternalNavigationLauncher(
              urlOpener: (_) async => true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Planificador de Viaje REstelar'), findsOneWidget);
      expect(find.text('Bogotá'), findsOneWidget);
      expect(find.text('Villa de Leyva'), findsOneWidget);
      expect(find.text('Parada Briceño'), findsOneWidget);
      expect(find.text('PARADAS INTERMEDIAS (1)'), findsOneWidget);
      expect(find.text('Google Maps'), findsOneWidget);
      expect(find.text('Waze'), findsOneWidget);
    });

    testWidgets('marca parada como visitada al tocar el icono de check', (
      tester,
    ) async {
      final itinerary = TripItinerary(
        id: 'trip_1',
        title: 'Mi Viaje',
        origin: origin,
        destination: destination,
        stops: [s1],
        createdAt: now,
        updatedAt: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: TripPlannerScreen(
            initialItinerary: itinerary,
            navigationLauncher: UrlExternalNavigationLauncher(
              urlOpener: (_) async => true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Inicialmente el icono es check_circle_outline
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);

      // Tocar para marcar como visitada
      await tester.tap(find.byIcon(Icons.check_circle_outline));
      await tester.pumpAndSettle();

      // Ahora el icono es check_circle (relleno)
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('exporta a Google Maps al presionar el botón correspondiente', (
      tester,
    ) async {
      String? launchedUrl;
      final launcher = UrlExternalNavigationLauncher(
        urlOpener: (url) async {
          launchedUrl = url;
          return true;
        },
      );

      final itinerary = TripItinerary(
        id: 'trip_1',
        title: 'Mi Viaje',
        origin: origin,
        destination: destination,
        stops: [s1],
        createdAt: now,
        updatedAt: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: TripPlannerScreen(
            initialItinerary: itinerary,
            navigationLauncher: launcher,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Google Maps'));
      await tester.pumpAndSettle();

      expect(launchedUrl, isNotNull);
      expect(launchedUrl, contains('https://www.google.com/maps/dir/'));
      expect(find.text('Itinerario enviado a Google Maps.'), findsOneWidget);
    });

    testWidgets(
      'exporta siguiente parada a Waze al presionar el botón de Waze',
      (tester) async {
        String? launchedUrl;
        final launcher = UrlExternalNavigationLauncher(
          urlOpener: (url) async {
            launchedUrl = url;
            return true;
          },
        );

        final itinerary = TripItinerary(
          id: 'trip_1',
          title: 'Mi Viaje',
          origin: origin,
          destination: destination,
          stops: [s1],
          createdAt: now,
          updatedAt: now,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: TripPlannerScreen(
              initialItinerary: itinerary,
              navigationLauncher: launcher,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Waze'));
        await tester.pumpAndSettle();

        expect(launchedUrl, isNotNull);
        expect(launchedUrl, contains('https://waze.com/ul'));
        expect(find.text('Aviso de Waze'), findsOneWidget);
      },
    );
  });
}
