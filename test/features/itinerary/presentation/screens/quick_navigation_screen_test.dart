import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_companion/road_companion.dart';

class FakeLocationServiceForQuickNav implements LocationService {
  bool isEnabled = true;
  LocationPermissionResult permission = LocationPermissionResult.granted;
  GpsPosition? positionToReturn;
  int getCurrentPositionCalls = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => isEnabled;

  @override
  Future<LocationPermissionResult> checkPermission() async => permission;

  @override
  Future<LocationPermissionResult> requestPermission() async => permission;

  @override
  Future<bool> checkBackgroundPermission() async => true;

  @override
  Future<LocationPermissionResult> requestBackgroundPermission() async =>
      permission;

  @override
  Stream<GpsPosition> getPositionStream({
    int distanceFilterMeters = 2,
    int intervalDurationMs = 1000,
    bool enableBackgroundNotification = false,
    String? notificationTitle,
    String? notificationText,
  }) => const Stream.empty();

  @override
  Future<GpsPosition?> getCurrentPosition({
    Duration timeLimit = const Duration(seconds: 8),
  }) async {
    getCurrentPositionCalls++;
    return positionToReturn;
  }
}

class FakeGeocodingServiceForQuickNav implements GeocodingService {
  String? lastSearchQuery;
  String? lastCategorySearched;
  List<Destination> searchResultsToReturn = [];
  List<Destination> categoryResultsToReturn = [];
  bool throwErrorOnSearch = false;

  @override
  Future<List<Destination>> search(
    String query, {
    Coordinates? proximityHint,
    int limit = 10,
  }) async {
    if (throwErrorOnSearch) throw Exception('Fallo de red en Nominatim');
    lastSearchQuery = query;
    return searchResultsToReturn;
  }

  @override
  Future<List<Destination>> searchNearbyCategory({
    required String category,
    required Coordinates center,
    int limit = 15,
  }) async {
    lastCategorySearched = category;
    return categoryResultsToReturn;
  }

  @override
  Future<Destination?> reverseGeocode(Coordinates coordinates) async => null;
}

class FakeLauncherForQuickNav implements ExternalNavigationLauncher {
  Coordinates? lastQuickGmapsDestCoords;
  String? lastQuickGmapsDestQuery;
  Coordinates? lastQuickWazeDestCoords;
  String? lastQuickWazeDestQuery;
  bool shouldSucceed = true;

  @override
  String buildGoogleMapsUrl(TripItinerary itinerary, {int maxWaypoints = 3}) =>
      '';

  @override
  String buildWazeUrl(TripItinerary itinerary) => '';

  @override
  String buildQuickGoogleMapsUrl({
    Coordinates? destinationCoordinates,
    String? destinationQuery,
    Coordinates? origin,
  }) => '';

  @override
  String buildQuickWazeUrl({
    Coordinates? destinationCoordinates,
    String? destinationQuery,
  }) => '';

  @override
  Future<NavigationExportResult> launchGoogleMaps(
    TripItinerary itinerary, {
    int maxWaypoints = 3,
    bool launchExternal = true,
  }) async => const NavigationExportResult(success: true);

  @override
  Future<NavigationExportResult> launchWaze(
    TripItinerary itinerary, {
    bool launchExternal = true,
  }) async => const NavigationExportResult(success: true);

  @override
  Future<NavigationExportResult> launchQuickGoogleMaps({
    Coordinates? destinationCoordinates,
    String? destinationQuery,
    Coordinates? origin,
    String targetName = '',
    bool launchExternal = true,
  }) async {
    lastQuickGmapsDestCoords = destinationCoordinates;
    lastQuickGmapsDestQuery = destinationQuery;
    if (!shouldSucceed) {
      return const NavigationExportResult(
        success: false,
        errorMessage: 'Fallo al abrir Google Maps en Android',
      );
    }
    return NavigationExportResult(success: true, targetName: targetName);
  }

  @override
  Future<NavigationExportResult> launchQuickWaze({
    Coordinates? destinationCoordinates,
    String? destinationQuery,
    String targetName = '',
    bool launchExternal = true,
  }) async {
    lastQuickWazeDestCoords = destinationCoordinates;
    lastQuickWazeDestQuery = destinationQuery;
    if (!shouldSucceed) {
      return const NavigationExportResult(
        success: false,
        errorMessage: 'Fallo al abrir Waze en Android',
      );
    }
    return NavigationExportResult(success: true, targetName: targetName);
  }
}

void main() {
  group('QuickNavigationScreen — Ir ahora (Fase 3C)', () {
    late FakeLocationServiceForQuickNav fakeLocation;
    late FakeGeocodingServiceForQuickNav fakeGeocoding;
    late FakeLauncherForQuickNav fakeLauncher;

    setUp(() {
      fakeLocation = FakeLocationServiceForQuickNav();
      fakeGeocoding = FakeGeocodingServiceForQuickNav();
      fakeLauncher = FakeLauncherForQuickNav();

      fakeLocation.positionToReturn = GpsPosition(
        coordinates: Coordinates(4.5981, -74.0758),
        accuracyMeters: 6.0,
        timestamp: DateTime.now(),
      );
    });

    Widget buildScreen(WidgetTester tester) {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      return MaterialApp(
        home: QuickNavigationScreen(
          locationService: fakeLocation,
          geocodingService: fakeGeocoding,
          navigationLauncher: fakeLauncher,
          enableMapTiles: false,
        ),
      );
    }

    testWidgets('Muestra "Mi ubicación actual" como origen predeterminado', (
      tester,
    ) async {
      await tester.pumpWidget(buildScreen(tester));
      await tester.pumpAndSettle();

      expect(find.text('Ir ahora'), findsOneWidget);
      expect(find.text('Mi ubicación actual'), findsOneWidget);
      expect(find.textContaining('GPS disponible (±6 m)'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('quick_nav_destination_input')),
        findsOneWidget,
      );
    });

    testWidgets(
      'Destino por coordenadas numéricas directas es detectado y seleccionado',
      (tester) async {
        await tester.pumpWidget(buildScreen(tester));
        await tester.pumpAndSettle();

        final input = find.byKey(const ValueKey('quick_nav_destination_input'));
        await tester.enterText(input, '5.6322, -73.5244');
        await tester.tap(find.byKey(const ValueKey('quick_nav_search_button')));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Coordenadas (5.63220, -73.52440)'),
          findsWidgets,
        );
        expect(
          find.textContaining('Destino: Coordenadas (5.63220, -73.52440)'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Búsqueda textual de destino muestra lista de resultados seleccionables',
      (tester) async {
        fakeGeocoding.searchResultsToReturn = [
          Destination(
            id: 'poi_1',
            title: 'Villa de Leyva',
            subtitle: 'Boyacá, Colombia',
            coordinates: Coordinates(5.6322, -73.5244),
          ),
          Destination(
            id: 'poi_2',
            title: 'Villa de Leyva Plaza Mayor',
            subtitle: 'Centro Histórico',
            coordinates: Coordinates(5.6325, -73.5250),
          ),
        ];

        await tester.pumpWidget(buildScreen(tester));
        await tester.pumpAndSettle();

        final input = find.byKey(const ValueKey('quick_nav_destination_input'));
        await tester.enterText(input, 'Villa de Leyva');
        await tester.tap(find.byKey(const ValueKey('quick_nav_search_button')));
        await tester.pumpAndSettle();

        expect(fakeGeocoding.lastSearchQuery, 'Villa de Leyva');
        expect(find.text('Villa de Leyva Plaza Mayor'), findsOneWidget);

        // Seleccionar el segundo resultado
        await tester.tap(find.byKey(const ValueKey('destination_tile_poi_2')));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Destino: Villa de Leyva Plaza Mayor'),
          findsOneWidget,
        );
      },
    );

    testWidgets('Accesos rápidos de categoría consultan POIs cercanos', (
      tester,
    ) async {
      fakeGeocoding.categoryResultsToReturn = [
        Destination(
          id: 'fuel_1',
          title: 'Terpel Boyacá',
          subtitle: 'Estación de servicio',
          coordinates: Coordinates(5.5000, -73.6000),
          category: 'fuel',
        ),
      ];

      await tester.pumpWidget(buildScreen(tester));
      await tester.pumpAndSettle();

      // Tocar chip de gasolineras
      await tester.tap(find.byKey(const ValueKey('chip_cat_fuel')));
      await tester.pumpAndSettle();

      expect(fakeGeocoding.lastCategorySearched, 'fuel');
      expect(find.text('Terpel Boyacá'), findsOneWidget);
    });

    testWidgets(
      'Lanza navegación rápida hacia Google Maps sin requerir itinerario formal',
      (tester) async {
        fakeGeocoding.searchResultsToReturn = [
          Destination(
            id: 'poi_tunja',
            title: 'Plaza de Bolívar Tunja',
            subtitle: 'Boyacá',
            coordinates: Coordinates(5.5353, -73.3678),
          ),
        ];

        await tester.pumpWidget(buildScreen(tester));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('quick_nav_destination_input')),
          'Tunja',
        );
        await tester.tap(find.byKey(const ValueKey('quick_nav_search_button')));
        await tester.pumpAndSettle();

        // Pulsar Google Maps
        await tester.tap(
          find.byKey(const ValueKey('launch_google_maps_button')),
        );
        await tester.pumpAndSettle();

        expect(fakeLauncher.lastQuickGmapsDestCoords, isNotNull);
        expect(
          fakeLauncher.lastQuickGmapsDestCoords!.latitude,
          closeTo(5.5353, 0.001),
        );
        expect(
          find.text('Navegación rápida abierta en Google Maps.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Lanza navegación rápida hacia Waze sin requerir itinerario formal',
      (tester) async {
        fakeGeocoding.searchResultsToReturn = [
          Destination(
            id: 'poi_tunja',
            title: 'Plaza de Bolívar Tunja',
            subtitle: 'Boyacá',
            coordinates: Coordinates(5.5353, -73.3678),
          ),
        ];

        await tester.pumpWidget(buildScreen(tester));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('quick_nav_destination_input')),
          'Tunja',
        );
        await tester.tap(find.byKey(const ValueKey('quick_nav_search_button')));
        await tester.pumpAndSettle();

        // Pulsar Waze
        await tester.tap(find.byKey(const ValueKey('launch_waze_button')));
        await tester.pumpAndSettle();

        expect(fakeLauncher.lastQuickWazeDestCoords, isNotNull);
        expect(
          fakeLauncher.lastQuickWazeDestCoords!.latitude,
          closeTo(5.5353, 0.001),
        );
        expect(find.text('Navegación rápida abierta en Waze.'), findsOneWidget);
      },
    );

    testWidgets('Maneja fallo de apertura externa y ofrece alternativa', (
      tester,
    ) async {
      fakeLauncher.shouldSucceed = false;
      fakeGeocoding.searchResultsToReturn = [
        Destination(
          id: 'poi_tunja',
          title: 'Tunja',
          subtitle: 'Boyacá',
          coordinates: Coordinates(5.5353, -73.3678),
        ),
      ];

      await tester.pumpWidget(buildScreen(tester));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('quick_nav_destination_input')),
        'Tunja',
      );
      await tester.tap(find.byKey(const ValueKey('quick_nav_search_button')));
      await tester.pumpAndSettle();

      // Pulsar Waze
      await tester.tap(find.byKey(const ValueKey('launch_waze_button')));
      await tester.pumpAndSettle();

      expect(find.text('Waze no disponible'), findsOneWidget);
      expect(find.text('Abrir con Google Maps'), findsOneWidget);
    });

    testWidgets(
      'Muestra mensaje de error cuando falla la red al buscar destino',
      (tester) async {
        fakeGeocoding.throwErrorOnSearch = true;

        await tester.pumpWidget(buildScreen(tester));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('quick_nav_destination_input')),
          'Leticia',
        );
        await tester.tap(find.byKey(const ValueKey('quick_nav_search_button')));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Error de conexión al buscar destino'),
          findsOneWidget,
        );
      },
    );
  });
}
