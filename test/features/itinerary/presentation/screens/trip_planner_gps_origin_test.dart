import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_companion/road_companion.dart';

class FakeLocationServiceForTripPlanner implements LocationService {
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

class FakeGeocodingServiceForPlanner implements GeocodingService {
  @override
  Future<List<Destination>> search(
    String query, {
    Coordinates? proximityHint,
    int limit = 10,
  }) async {
    return [
      Destination(
        id: 'dest_manual',
        title: 'Chía, Cundinamarca',
        subtitle: 'Cundinamarca, Colombia',
        coordinates: Coordinates(4.8631, -74.0583),
      ),
    ];
  }

  @override
  Future<List<Destination>> searchNearbyCategory({
    required String category,
    required Coordinates center,
    int limit = 15,
  }) async => [];

  @override
  Future<Destination?> reverseGeocode(Coordinates coordinates) async => null;
}

void main() {
  group('TripPlannerScreen — Origen GPS Automático y Estados (Fase 3C)', () {
    late FakeLocationServiceForTripPlanner fakeLocation;
    late FakeGeocodingServiceForPlanner fakeGeocoding;

    setUp(() {
      fakeLocation = FakeLocationServiceForTripPlanner();
      fakeGeocoding = FakeGeocodingServiceForPlanner();
    });

    Widget buildPlanner({Coordinates? userCurrentLocation}) {
      return MaterialApp(
        home: TripPlannerScreen(
          locationService: fakeLocation,
          geocodingService: fakeGeocoding,
          userCurrentLocation: userCurrentLocation,
        ),
      );
    }

    testWidgets(
      'Origen automático se fija cuando el GPS retorna lectura válida',
      (tester) async {
        fakeLocation.positionToReturn = GpsPosition(
          coordinates: Coordinates(4.7110, -74.0721),
          accuracyMeters: 8.0,
          timestamp: DateTime.now(),
        );

        await tester.pumpWidget(buildPlanner());
        await tester.pumpAndSettle();

        expect(find.text('Mi ubicación actual'), findsOneWidget);
        expect(find.textContaining('GPS disponible (±8 m)'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('refresh_gps_button')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Muestra estado "GPS desactivado" cuando el sensor está apagado',
      (tester) async {
        fakeLocation.isEnabled = false;

        await tester.pumpWidget(buildPlanner());
        await tester.pumpAndSettle();

        expect(find.text('GPS desactivado'), findsOneWidget);
        expect(
          find.text('Activa el sensor de ubicación del teléfono'),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('retry_gps_button')), findsOneWidget);
      },
    );

    testWidgets(
      'Muestra estado "Permiso de ubicación denegado" cuando falta permiso',
      (tester) async {
        fakeLocation.isEnabled = true;
        fakeLocation.permission = LocationPermissionResult.denied;

        await tester.pumpWidget(buildPlanner());
        await tester.pumpAndSettle();

        expect(find.text('Permiso de ubicación denegado'), findsOneWidget);
        expect(
          find.text('Concede permiso o define el origen manualmente'),
          findsOneWidget,
        );
      },
    );

    testWidgets('Muestra advertencia cuando la precisión es reducida (> 50m)', (
      tester,
    ) async {
      fakeLocation.positionToReturn = GpsPosition(
        coordinates: Coordinates(4.7110, -74.0721),
        accuracyMeters: 75.0,
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(buildPlanner());
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('gps_warning_banner')), findsOneWidget);
      expect(
        find.textContaining('Precisión GPS reducida (±75 m)'),
        findsOneWidget,
      );
    });

    testWidgets(
      'Muestra advertencia cuando la posición GPS es desactualizada (> 2 min)',
      (tester) async {
        fakeLocation.positionToReturn = GpsPosition(
          coordinates: Coordinates(4.7110, -74.0721),
          accuracyMeters: 10.0,
          timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
        );

        await tester.pumpWidget(buildPlanner());
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('gps_warning_banner')),
          findsOneWidget,
        );
        expect(find.textContaining('Lectura GPS antigua'), findsOneWidget);
      },
    );

    testWidgets(
      'Edición manual del origen respeta la selección y ofrece "Usar mi ubicación"',
      (tester) async {
        fakeLocation.positionToReturn = GpsPosition(
          coordinates: Coordinates(4.7110, -74.0721),
          accuracyMeters: 8.0,
          timestamp: DateTime.now(),
        );

        await tester.pumpWidget(buildPlanner());
        await tester.pumpAndSettle();

        // Abrir cambio de origen
        await tester.tap(find.byKey(const ValueKey('edit_origin_button')));
        await tester.pumpAndSettle();

        // Escribir búsqueda y pulsar buscar
        final searchField = find.byType(TextField);
        await tester.enterText(searchField, 'Chía');
        await tester.tap(find.byIcon(Icons.search));
        await tester.pumpAndSettle();

        // Seleccionar resultado manual
        await tester.tap(find.text('Chía, Cundinamarca'));
        await tester.pumpAndSettle();

        // Verificar que ahora el origen es manual
        expect(find.text('Chía, Cundinamarca'), findsOneWidget);
        expect(find.textContaining('Origen manual'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('use_my_location_button')),
          findsOneWidget,
        );

        // Restaurar explícitamente GPS pulsando "Usar mi ubicación"
        await tester.tap(find.byKey(const ValueKey('use_my_location_button')));
        await tester.pumpAndSettle();

        expect(find.text('Mi ubicación actual'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('use_my_location_button')),
          findsNothing,
        );
      },
    );

    testWidgets('Botón de refrescar invoca lectura fresca del sensor GPS', (
      tester,
    ) async {
      fakeLocation.positionToReturn = GpsPosition(
        coordinates: Coordinates(4.7110, -74.0721),
        accuracyMeters: 12.0,
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(buildPlanner());
      await tester.pumpAndSettle();

      final initialCalls = fakeLocation.getCurrentPositionCalls;
      expect(initialCalls, greaterThanOrEqualTo(1));

      // Tocar botón refrescar
      await tester.tap(find.byKey(const ValueKey('refresh_gps_button')));
      await tester.pumpAndSettle();

      expect(fakeLocation.getCurrentPositionCalls, initialCalls + 1);
    });
  });
}
