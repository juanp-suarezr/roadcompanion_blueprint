import 'package:flutter_test/flutter_test.dart';
import 'package:road_companion/road_companion.dart';

void main() {
  group('UrlExternalNavigationLauncher — Navegación Rápida (Fase 3C)', () {
    late UrlExternalNavigationLauncher launcher;
    String? lastOpenedUrl;
    bool openerShouldSucceed = true;

    setUp(() {
      lastOpenedUrl = null;
      openerShouldSucceed = true;
      launcher = UrlExternalNavigationLauncher(
        urlOpener: (url) async {
          lastOpenedUrl = url;
          return openerShouldSucceed;
        },
      );
    });

    group('buildQuickGoogleMapsUrl', () {
      test(
        'omite origen y añade dir_action=navigate cuando origin es null (navegación desde GPS actual)',
        () {
          final url = launcher.buildQuickGoogleMapsUrl(
            destinationCoordinates: Coordinates(5.6322, -73.5244),
          );

          final uri = Uri.parse(url);
          expect(uri.scheme, 'https');
          expect(uri.host, 'www.google.com');
          expect(uri.path, '/maps/dir/');
          expect(uri.queryParameters['api'], '1');
          expect(uri.queryParameters['travelmode'], 'driving');
          expect(uri.queryParameters['dir_action'], 'navigate');
          expect(uri.queryParameters['destination'], '5.632200,-73.524400');
          expect(uri.queryParameters.containsKey('origin'), isFalse);
        },
      );

      test('soporta destino por consulta textual codificada', () {
        final url = launcher.buildQuickGoogleMapsUrl(
          destinationQuery: 'Mirador La Calera, Bogotá',
        );

        final uri = Uri.parse(url);
        expect(uri.queryParameters['destination'], 'Mirador La Calera, Bogotá');
        expect(uri.queryParameters['dir_action'], 'navigate');
      });

      test('incluye origen explícito cuando es suministrado', () {
        final url = launcher.buildQuickGoogleMapsUrl(
          destinationCoordinates: Coordinates(5.6322, -73.5244),
          origin: Coordinates(4.5981, -74.0758),
        );

        final uri = Uri.parse(url);
        expect(uri.queryParameters['origin'], '4.598100,-74.075800');
        expect(uri.queryParameters['destination'], '5.632200,-73.524400');
        expect(uri.queryParameters.containsKey('dir_action'), isFalse);
      });

      test(
        'lanza ArgumentError si no se proporciona coordenadas ni texto de destino',
        () {
          expect(() => launcher.buildQuickGoogleMapsUrl(), throwsArgumentError);
        },
      );
    });

    group('buildQuickWazeUrl', () {
      test(
        'genera Deep Link con ll=LAT,LON&navigate=yes para destino con coordenadas',
        () {
          final url = launcher.buildQuickWazeUrl(
            destinationCoordinates: Coordinates(5.6322, -73.5244),
          );

          final uri = Uri.parse(url);
          expect(uri.scheme, 'https');
          expect(uri.host, 'waze.com');
          expect(uri.path, '/ul');
          expect(uri.queryParameters['ll'], '5.632200,-73.524400');
          expect(uri.queryParameters['navigate'], 'yes');
          expect(uri.queryParameters.containsKey('q'), isFalse);
        },
      );

      test(
        'genera Deep Link con q=QUERY&navigate=yes para búsqueda textual',
        () {
          final url = launcher.buildQuickWazeUrl(
            destinationQuery: 'Gasolinera Terpel Tunja',
          );

          final uri = Uri.parse(url);
          expect(uri.queryParameters['q'], 'Gasolinera Terpel Tunja');
          expect(uri.queryParameters['navigate'], 'yes');
          expect(uri.queryParameters.containsKey('ll'), isFalse);
        },
      );

      test(
        'lanza ArgumentError si no se suministran coordenadas ni consulta textual',
        () {
          expect(() => launcher.buildQuickWazeUrl(), throwsArgumentError);
        },
      );
    });

    group('Lanzamiento hacia apps externas y manejo de errores', () {
      test('launchQuickGoogleMaps abre URL con éxito', () async {
        final result = await launcher.launchQuickGoogleMaps(
          destinationCoordinates: Coordinates(5.6322, -73.5244),
          targetName: 'Villa de Leyva',
        );

        expect(result.success, isTrue);
        expect(result.targetName, 'Villa de Leyva');
        expect(lastOpenedUrl, contains('destination=5.632200%2C-73.524400'));
      });

      test(
        'launchQuickGoogleMaps maneja fallo de apertura del lanzador nativo',
        () async {
          openerShouldSucceed = false;

          final result = await launcher.launchQuickGoogleMaps(
            destinationCoordinates: Coordinates(5.6322, -73.5244),
            targetName: 'Villa de Leyva',
          );

          expect(result.success, isFalse);
          expect(result.errorMessage, isNotNull);
          expect(
            result.errorMessage,
            contains('No fue posible abrir Google Maps'),
          );
        },
      );

      test('launchQuickWaze abre URL con éxito', () async {
        final result = await launcher.launchQuickWaze(
          destinationCoordinates: Coordinates(5.6322, -73.5244),
          targetName: 'Villa de Leyva',
        );

        expect(result.success, isTrue);
        expect(result.targetName, 'Villa de Leyva');
        expect(lastOpenedUrl, contains('ll=5.632200%2C-73.524400'));
      });

      test(
        'launchQuickWaze maneja fallo de apertura del lanzador nativo',
        () async {
          openerShouldSucceed = false;

          final result = await launcher.launchQuickWaze(
            destinationCoordinates: Coordinates(5.6322, -73.5244),
            targetName: 'Villa de Leyva',
          );

          expect(result.success, isFalse);
          expect(result.errorMessage, isNotNull);
          expect(result.errorMessage, contains('No fue posible abrir Waze'));
        },
      );
    });
  });
}
