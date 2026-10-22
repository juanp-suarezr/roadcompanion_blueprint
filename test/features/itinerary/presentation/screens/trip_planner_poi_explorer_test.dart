import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:road_companion/road_companion.dart';

void main() {
  final origin = Destination(
    id: 'orig',
    title: 'Bogotá',
    subtitle: 'Bogotá, Colombia',
    coordinates: Coordinates(4.6000, -74.0800),
  );

  final destination = Destination(
    id: 'dest',
    title: 'Chía',
    subtitle: 'Cundinamarca, Colombia',
    coordinates: Coordinates(4.8600, -74.0500),
  );

  final s1 = TripStop(
    id: 's1',
    name: 'Parada Previa',
    coordinates: Coordinates(4.7000, -74.0700),
    type: TripStopType.custom,
    orderIndex: 0,
  );

  final now = DateTime(2026, 10, 22, 10, 0, 0);

  // Ruta con geometría simulada (4 puntos rectos norte)
  final routeGeometry = [
    Coordinates(4.6000, -74.0800),
    Coordinates(4.7000, -74.0700),
    Coordinates(4.8000, -74.0600),
    Coordinates(4.8600, -74.0500),
  ];

  final calculatedRoute = CalculatedRoute(
    routePlan: RoutePlan(
      origin: routeGeometry.first,
      destination: routeGeometry.last,
      geometry: routeGeometry,
      totalDistanceMeters: 30000.0,
      estimatedDuration: const Duration(minutes: 40),
      maneuvers: const [],
    ),
    summary: 'Ruta hacia Chía',
  );

  group('TripPlannerScreen - POI Explorer (Fase 3B)', () {
    testWidgets('explica que primero debe calcular la ruta si no hay geometría', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final itineraryWithoutRoute = TripItinerary(
        id: 'trip_no_route',
        title: 'Viaje sin calcular',
        origin: origin,
        destination: destination,
        createdAt: now,
        updatedAt: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: TripPlannerScreen(
            initialItinerary: itineraryWithoutRoute,
            navigationLauncher: UrlExternalNavigationLauncher(
              urlOpener: (_) async => true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          'Calcula primero la ruta en REstelar para habilitar la búsqueda inteligente',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'muestra controles de exploración y busca POIs a lo largo de la ruta',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final mockClient = MockClient((request) async {
          final jsonResponse = {
            'elements': [
              {
                'type': 'node',
                'id': 1001,
                'lat': 4.7500,
                'lon': -74.0650,
                'tags': {
                  'name': 'Terpel Autopista Norte',
                  'amenity': 'fuel',
                  'addr:street': 'Autopista Norte km 19',
                },
              },
            ],
          };
          return http.Response(jsonEncode(jsonResponse), 200);
        });

        final explorer = RoutePoiExplorerService(
          osmPoiService: OsmPoiService(client: mockClient),
        );

        final itineraryWithRoute = TripItinerary(
          id: 'trip_with_route',
          title: 'Viaje con ruta',
          origin: origin,
          destination: destination,
          stops: [s1],
          calculatedRoute: calculatedRoute,
          createdAt: now,
          updatedAt: now,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: TripPlannerScreen(
              initialItinerary: itineraryWithRoute,
              poiExplorerService: explorer,
              navigationLauncher: UrlExternalNavigationLauncher(
                urlOpener: (_) async => true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('EXPLORADOR DE POIS EN RUTA'), findsOneWidget);
        expect(find.text('Buscar POIs en Ruta'), findsOneWidget);

        // Presionar buscar
        await tester.tap(find.text('Buscar POIs en Ruta'));
        await tester.pumpAndSettle();

        // Debe mostrar el POI encontrado
        expect(find.text('Terpel Autopista Norte'), findsOneWidget);
        expect(find.text('Añadir como parada'), findsOneWidget);
        expect(find.textContaining('Dist. perpendicular: ~'), findsOneWidget);
        expect(find.text('Desvío por carretera no calculado'), findsOneWidget);
        expect(
          find.textContaining('Aprox. geométrica teórica: ~'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'añade un POI descubierto como parada intermedia preservando paradas existentes',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final mockClient = MockClient((request) async {
          final jsonResponse = {
            'elements': [
              {
                'type': 'node',
                'id': 1001,
                'lat': 4.7500,
                'lon': -74.0650,
                'tags': {
                  'name': 'Terpel Autopista Norte',
                  'amenity': 'fuel',
                  'addr:street': 'Autopista Norte km 19',
                },
              },
            ],
          };
          return http.Response(jsonEncode(jsonResponse), 200);
        });

        final explorer = RoutePoiExplorerService(
          osmPoiService: OsmPoiService(client: mockClient),
        );

        final itineraryWithRoute = TripItinerary(
          id: 'trip_with_route',
          title: 'Viaje con ruta',
          origin: origin,
          destination: destination,
          stops: [s1],
          calculatedRoute: calculatedRoute,
          createdAt: now,
          updatedAt: now,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: TripPlannerScreen(
              initialItinerary: itineraryWithRoute,
              poiExplorerService: explorer,
              navigationLauncher: UrlExternalNavigationLauncher(
                urlOpener: (_) async => true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Buscar
        await tester.tap(find.text('Buscar POIs en Ruta'));
        await tester.pumpAndSettle();

        expect(find.text('Terpel Autopista Norte'), findsOneWidget);

        // Tocar "Añadir como parada"
        await tester.tap(find.text('Añadir como parada'));
        await tester.pumpAndSettle();

        // Debe confirmar adición en el banner de estado
        expect(
          find.textContaining('Parada añadida: "Terpel Autopista Norte"'),
          findsOneWidget,
        );

        // Debe reflejar ahora 2 paradas intermedias
        expect(find.text('PARADAS INTERMEDIAS (2)'), findsOneWidget);
        expect(find.text('Parada Previa'), findsOneWidget);
        // El nombre del POI debe figurar en la lista de paradas
        expect(find.text('Terpel Autopista Norte'), findsWidgets);
      },
    );

    testWidgets(
      'muestra mensaje amigable cuando no se encuentran resultados en el corredor',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final mockClient = MockClient((request) async {
          final jsonResponse = {'elements': <Map<String, dynamic>>[]};
          return http.Response(jsonEncode(jsonResponse), 200);
        });

        final explorer = RoutePoiExplorerService(
          osmPoiService: OsmPoiService(client: mockClient),
        );

        final itineraryWithRoute = TripItinerary(
          id: 'trip_with_route',
          title: 'Viaje con ruta',
          origin: origin,
          destination: destination,
          calculatedRoute: calculatedRoute,
          createdAt: now,
          updatedAt: now,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: TripPlannerScreen(
              initialItinerary: itineraryWithRoute,
              poiExplorerService: explorer,
              navigationLauncher: UrlExternalNavigationLauncher(
                urlOpener: (_) async => true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Buscar
        await tester.tap(find.text('Buscar POIs en Ruta'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining(
            'No se encontraron POIs de esta categoría dentro del corredor',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('muestra mensaje de error cuando el servicio de POI falla', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockClient = MockClient((request) async {
        return http.Response('Server error', 503);
      });

      final explorer = RoutePoiExplorerService(
        osmPoiService: OsmPoiService(client: mockClient),
      );

      final itineraryWithRoute = TripItinerary(
        id: 'trip_with_route',
        title: 'Viaje con ruta',
        origin: origin,
        destination: destination,
        calculatedRoute: calculatedRoute,
        createdAt: now,
        updatedAt: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: TripPlannerScreen(
            initialItinerary: itineraryWithRoute,
            poiExplorerService: explorer,
            navigationLauncher: UrlExternalNavigationLauncher(
              urlOpener: (_) async => true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Buscar
      await tester.tap(find.text('Buscar POIs en Ruta'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Error de conexión al consultar puntos de interés'),
        findsOneWidget,
      );
    });
  });
}
