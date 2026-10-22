import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_companion/app/theme/app_theme.dart';
import 'package:road_companion/domain/entities/coordinates.dart';
import 'package:road_companion/domain/entities/maneuver.dart';
import 'package:road_companion/domain/entities/maneuver_type.dart';
import 'package:road_companion/domain/services/route_progress_calculator.dart';
import 'package:road_companion/features/navigation/domain/entities/gps_position.dart';
import 'package:road_companion/features/navigation/domain/entities/gpx_point.dart';
import 'package:road_companion/features/navigation/domain/entities/gpx_segment.dart';
import 'package:road_companion/features/navigation/domain/entities/imported_gpx_route.dart';
import 'package:road_companion/features/navigation/domain/services/location_service.dart';
import 'package:road_companion/features/navigation/presentation/state/gpx_route_tracker.dart';
import 'package:road_companion/features/navigation/presentation/widgets/active_turn_by_turn_hud.dart';
import 'package:road_companion/features/navigation/presentation/widgets/real_map_widget.dart';

class _FakeLocationService implements LocationService {
  final _controller = StreamController<GpsPosition>.broadcast();

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermissionResult> checkPermission() async =>
      LocationPermissionResult.granted;

  @override
  Future<LocationPermissionResult> requestPermission() async =>
      LocationPermissionResult.granted;

  @override
  Future<bool> checkBackgroundPermission() async => true;

  @override
  Future<LocationPermissionResult> requestBackgroundPermission() async =>
      LocationPermissionResult.granted;

  @override
  Stream<GpsPosition> getPositionStream({
    int distanceFilterMeters = 2,
    int intervalDurationMs = 1000,
    bool enableBackgroundNotification = false,
    String? notificationTitle,
    String? notificationText,
  }) => _controller.stream;

  @override
  Future<GpsPosition?> getCurrentPosition({
    Duration timeLimit = const Duration(seconds: 8),
  }) async => null;

  void emitPosition(GpsPosition pos) => _controller.add(pos);

  void dispose() => _controller.close();
}

void main() {
  group('Samsung Galaxy A35 (Android 16) — HUD y Accesibilidad de Controles', () {
    late _FakeLocationService locationService;
    late GpxRouteTracker tracker;
    late ImportedGpxRoute testRoute;
    late MapController mapController;

    setUp(() {
      locationService = _FakeLocationService();
      mapController = MapController();
      testRoute = ImportedGpxRoute(
        name: 'Ruta 5km Pereira - Dosquebradas',
        segments: [
          GpxSegment([
            GpxPoint(coordinates: Coordinates(4.8133, -75.6961)),
            GpxPoint(coordinates: Coordinates(4.8200, -75.6900)),
            GpxPoint(coordinates: Coordinates(4.8300, -75.6800)),
          ]),
        ],
      );

      tracker = GpxRouteTracker(
        route: testRoute,
        locationService: locationService,
        calculator: RouteProgressCalculator(),
      );
    });

    tearDown(() {
      tracker.dispose();
      locationService.dispose();
      mapController.dispose();
    });

    testWidgets('ActiveTurnByTurnHud se adapta a pantalla Samsung A35 sin solapamientos', (
      tester,
    ) async {
      // Dimensiones de pantalla Samsung Galaxy A35: 1080 x 2340 píxeles físicos (~411.4 x 891.4 dp)
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      bool pauseTapped = false;
      bool stopTapped = false;
      bool voiceMuteToggled = false;

      final maneuver = Maneuver(
        instructionText: 'Gire a la derecha hacia Av. Simón Bolívar',
        distanceMeters: 350,
        type: ManeuverType.right,
        location: Coordinates(4.8150, -75.6930),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Stack(
              children: [
                // Mapa de fondo con controles flotantes elevados a controlsBottomOffset 230
                RealMapWidget(
                  mapController: mapController,
                  riderPosition: Coordinates(4.8133, -75.6961),
                  onRecenter: () {},
                  routeGeometry: testRoute.allCoordinates,
                  controlsBottomOffset: 230.0,
                ),
                // HUD Activo Turn-by-Turn
                ActiveTurnByTurnHud(
                  tracker: tracker,
                  currentManeuver: maneuver,
                  distanceToManeuverMeters: 350.0,
                  isVoiceMuted: false,
                  onToggleVoiceMute: () => voiceMuteToggled = true,
                  onPause: () => pauseTapped = true,
                  onResume: () {},
                  onStop: () => stopTapped = true,
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 1. Verificar presencia de la maniobra superior
      expect(
        find.text('Gire a la derecha hacia Av. Simón Bolívar'),
        findsOneWidget,
      );
      expect(find.textContaining('350 m'), findsOneWidget);

      // 2. Verificar telemetría inferior (velocímetro, distancia restante, progreso)
      expect(find.text('km/h'), findsOneWidget);
      expect(find.text('RESTANTE'), findsOneWidget);
      expect(find.text('PROGRESO'), findsOneWidget);

      // 3. Verificar que los botones flotantes del mapa (Centrar en mi ubicación, zoom)
      // están posicionados arriba del panel inferior (> 200 dp desde el borde inferior)
      final recenterFinder = find.byTooltip('Centrar en mi ubicación');
      expect(recenterFinder, findsOneWidget);
      final recenterBottomOffset = tester.getBottomLeft(recenterFinder).dy;
      final screenHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final distanceFromScreenBottom = screenHeight - recenterBottomOffset;

      // El botón debe estar a más de 200 dp del fondo para no ser tapado por el panel
      expect(distanceFromScreenBottom, greaterThanOrEqualTo(200.0));

      // 4. Verificar interacción con los controles de navegación
      final pauseBtn = find.text('Pausar');
      expect(pauseBtn, findsOneWidget);
      await tester.tap(pauseBtn);
      expect(pauseTapped, isTrue);

      final finishBtn = find.text('Finalizar');
      expect(finishBtn, findsOneWidget);
      await tester.tap(finishBtn);
      await tester.pumpAndSettle();

      // Confirmar en el diálogo de finalización
      final confirmBtn = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Finalizar'),
      );
      expect(confirmBtn, findsOneWidget);
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();
      expect(stopTapped, isTrue);

      final muteBtn = find.byType(IconButton);
      expect(muteBtn, findsOneWidget);
      await tester.tap(muteBtn);
      expect(voiceMuteToggled, isTrue);
    });

    testWidgets(
      'ActiveTurnByTurnHud muestra chip BUSCANDO GPS sin fix y GPS REAL tras recibir señal',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2340);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: ListenableBuilder(
                listenable: tracker,
                builder: (context, _) => ActiveTurnByTurnHud(
                  tracker: tracker,
                  onPause: () {},
                  onResume: () {},
                  onStop: () {},
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Sin fix inicial
        expect(find.text('BUSCANDO GPS'), findsOneWidget);

        // Iniciar tracker y emitir posición válida
        await tracker.startTracking();
        locationService.emitPosition(
          GpsPosition(
            coordinates: Coordinates(4.8133, -75.6961),
            accuracyMeters: 4.2,
            speedMps: 12.5,
            timestamp: DateTime.now(),
          ),
        );
        await tester.pumpAndSettle();

        // Debe mostrar origen de datos GPS REAL con precisión
        expect(find.text('GPS REAL'), findsOneWidget);
        expect(find.textContaining('±4m'), findsOneWidget);

        // Detener tracking para cancelar timers activos del tracker
        await tracker.stopTracking();
        await tester.pumpAndSettle();
      },
    );
  });
}
