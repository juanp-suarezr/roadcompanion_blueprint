import 'package:road_companion/road_companion.dart';
import 'package:test/test.dart';

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

  final now = DateTime(2026, 10, 22, 10, 0, 0);

  group('UrlExternalNavigationLauncher - Google Maps URLs Oficiales', () {
    test('genera URL directa para Google Maps sin paradas intermedias', () {
      final launcher = UrlExternalNavigationLauncher(
        urlOpener: (_) async => true,
      );
      final itinerary = TripItinerary(
        id: 'trip_1',
        title: 'Viaje Directo',
        origin: origin,
        destination: destination,
        createdAt: now,
        updatedAt: now,
      );

      final url = launcher.buildGoogleMapsUrl(itinerary);
      final uri = Uri.parse(url);

      expect(uri.scheme, equals('https'));
      expect(uri.host, equals('www.google.com'));
      expect(uri.path, equals('/maps/dir/'));
      expect(uri.queryParameters['api'], equals('1'));
      expect(uri.queryParameters['origin'], equals('4.598100,-74.075800'));
      expect(uri.queryParameters['destination'], equals('5.632200,-73.524400'));
      expect(uri.queryParameters['travelmode'], equals('driving'));
      expect(uri.queryParameters.containsKey('waypoints'), isFalse);
    });

    test(
      'incluye waypoints codificados para paradas intermedias pendientes',
      () {
        final launcher = UrlExternalNavigationLauncher(
          urlOpener: (_) async => true,
        );
        final s1 = TripStop(
          id: 's1',
          name: 'Briceño',
          coordinates: Coordinates(4.9351, -73.9921),
          orderIndex: 0,
        );
        final s2 = TripStop(
          id: 's2',
          name: 'Ubaté',
          coordinates: Coordinates(5.3101, -73.8151),
          orderIndex: 1,
        );

        final itinerary = TripItinerary(
          id: 'trip_1',
          title: 'Viaje con Paradas',
          origin: origin,
          destination: destination,
          stops: [s1, s2],
          createdAt: now,
          updatedAt: now,
        );

        final url = launcher.buildGoogleMapsUrl(itinerary, maxWaypoints: 3);
        final uri = Uri.parse(url);

        expect(uri.queryParameters.containsKey('waypoints'), isTrue);
        final waypoints = uri.queryParameters['waypoints']!;
        expect(waypoints, contains('4.935100,-73.992100'));
        expect(waypoints, contains('5.310100,-73.815100'));
      },
    );

    test('omite paradas ya visitadas al generar waypoints', () {
      final launcher = UrlExternalNavigationLauncher(
        urlOpener: (_) async => true,
      );
      final s1 = TripStop(
        id: 's1',
        name: 'Briceño',
        coordinates: Coordinates(4.9351, -73.9921),
        orderIndex: 0,
        isVisited: true,
      );
      final s2 = TripStop(
        id: 's2',
        name: 'Ubaté',
        coordinates: Coordinates(5.3101, -73.8151),
        orderIndex: 1,
        isVisited: false,
      );

      final itinerary = TripItinerary(
        id: 'trip_1',
        title: 'Viaje en Progreso',
        origin: origin,
        destination: destination,
        stops: [s1, s2],
        createdAt: now,
        updatedAt: now,
      );

      final url = launcher.buildGoogleMapsUrl(itinerary, maxWaypoints: 3);
      final uri = Uri.parse(url);

      final waypoints = uri.queryParameters['waypoints']!;
      expect(
        waypoints.contains('4.935100'),
        isFalse,
      ); // Briceño (visitado) se omite
      expect(
        waypoints,
        contains('5.310100,-73.815100'),
      ); // Ubaté (pendiente) se incluye
    });

    test(
      'gestiona límite de waypoints móviles (max 3) y advierte omisiones',
      () async {
        String? launchedUrl;
        final launcher = UrlExternalNavigationLauncher(
          urlOpener: (url) async {
            launchedUrl = url;
            return true;
          },
        );

        final stops = List.generate(
          5,
          (i) => TripStop(
            id: 's$i',
            name: 'Parada $i',
            coordinates: Coordinates(4.6 + (i * 0.1), -74.0),
            orderIndex: i,
          ),
        );

        final itinerary = TripItinerary(
          id: 'trip_1',
          title: 'Viaje Largo',
          origin: origin,
          destination: destination,
          stops: stops,
          createdAt: now,
          updatedAt: now,
        );

        final result = await launcher.launchGoogleMaps(
          itinerary,
          maxWaypoints: 3,
        );

        expect(result.success, isTrue);
        expect(result.exportedStopsCount, equals(3));
        expect(result.omittedStopsCount, equals(2));
        expect(result.hasOmittedStops, isTrue);
        expect(
          result.warningMessage,
          contains('admite un número acotado de paradas intermedias (hasta 3)'),
        );
        expect(launchedUrl, isNotNull);
      },
    );
  });

  group('UrlExternalNavigationLauncher - Waze Deep Links Oficiales', () {
    test(
      'genera Deep Link hacia la siguiente parada activa con advertencia de tramo único',
      () async {
        String? launchedUrl;
        final launcher = UrlExternalNavigationLauncher(
          urlOpener: (url) async {
            launchedUrl = url;
            return true;
          },
        );

        final s1 = TripStop(
          id: 's1',
          name: 'Primera Parada',
          coordinates: Coordinates(4.7501, -74.0501),
          orderIndex: 0,
        );
        final s2 = TripStop(
          id: 's2',
          name: 'Segunda Parada',
          coordinates: Coordinates(5.1201, -73.9001),
          orderIndex: 1,
        );

        final itinerary = TripItinerary(
          id: 'trip_1',
          title: 'Viaje Waze',
          origin: origin,
          destination: destination,
          stops: [s1, s2],
          createdAt: now,
          updatedAt: now,
        );

        final result = await launcher.launchWaze(itinerary);

        expect(result.success, isTrue);
        expect(result.targetName, equals('Primera Parada'));
        expect(
          result.warningMessage,
          contains(
            'Waze no admite paradas intermedias múltiples vía enlace externo',
          ),
        );
        expect(launchedUrl, contains('https://waze.com/ul'));
        expect(launchedUrl, contains('ll=4.750100%2C-74.050100'));
        expect(launchedUrl, contains('navigate=yes'));
      },
    );

    test(
      'apunta al destino final en Waze si no hay paradas o todas fueron visitadas',
      () async {
        String? launchedUrl;
        final launcher = UrlExternalNavigationLauncher(
          urlOpener: (url) async {
            launchedUrl = url;
            return true;
          },
        );

        final s1 = TripStop(
          id: 's1',
          name: 'Parada Hecha',
          coordinates: Coordinates(4.75, -74.05),
          orderIndex: 0,
          isVisited: true,
        );

        final itinerary = TripItinerary(
          id: 'trip_1',
          title: 'Viaje Completado',
          origin: origin,
          destination: destination,
          stops: [s1],
          createdAt: now,
          updatedAt: now,
        );

        final result = await launcher.launchWaze(itinerary);

        expect(result.success, isTrue);
        expect(result.targetName, equals('Villa de Leyva')); // Destino final
        expect(launchedUrl, contains('ll=5.632200%2C-73.524400'));
      },
    );

    test(
      'maneja fallos cuando el navegador o la aplicación externa no pueden abrirse',
      () async {
        final launcher = UrlExternalNavigationLauncher(
          urlOpener: (_) async => false, // Falla la apertura del intent
        );

        final itinerary = TripItinerary(
          id: 'trip_1',
          title: 'Viaje',
          origin: origin,
          destination: destination,
          createdAt: now,
          updatedAt: now,
        );

        final result = await launcher.launchGoogleMaps(itinerary);
        expect(result.success, isFalse);
        expect(
          result.errorMessage,
          contains('No fue posible abrir Google Maps'),
        );
      },
    );
  });
}
