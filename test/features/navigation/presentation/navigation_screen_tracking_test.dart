import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_companion/app/theme/app_theme.dart';
import 'package:road_companion/domain/entities/coordinates.dart';
import 'package:road_companion/features/navigation/domain/entities/gps_position.dart';
import 'package:road_companion/features/navigation/domain/entities/navigation_session.dart';
import 'package:road_companion/features/navigation/domain/repositories/session_repository.dart';
import 'package:road_companion/features/navigation/domain/services/location_service.dart';
import 'package:road_companion/features/navigation/infrastructure/parsers/gpx_parser.dart';
import 'package:road_companion/features/navigation/presentation/navigation_screen.dart';
import 'package:road_companion/features/navigation/presentation/state/imported_route_state.dart';
import 'package:road_companion/features/navigation/presentation/widgets/gpx_live_tracking_panel.dart';
import 'package:road_companion/features/navigation/presentation/widgets/session_summary_dialog.dart';

class MockLocationService implements LocationService {
  LocationPermissionResult permissionResult = LocationPermissionResult.granted;
  final StreamController<GpsPosition> _controller =
      StreamController<GpsPosition>.broadcast();

  void emitPosition(GpsPosition pos) => _controller.add(pos);

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermissionResult> checkPermission() async => permissionResult;

  @override
  Future<LocationPermissionResult> requestPermission() async =>
      permissionResult;

  @override
  Future<bool> checkBackgroundPermission() async => true;

  @override
  Future<LocationPermissionResult> requestBackgroundPermission() async =>
      permissionResult;

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

  void dispose() => _controller.close();
}

class MockSessionRepository implements SessionRepository {
  final List<NavigationSession> sessions = [];

  @override
  Future<List<NavigationSession>> getSessions() async => sessions;

  @override
  Future<void> saveSession(NavigationSession session) async {
    sessions.removeWhere((s) => s.id == session.id);
    sessions.insert(0, session);
  }

  @override
  Future<void> deleteSession(String id) async {
    sessions.removeWhere((s) => s.id == id);
  }
}

void main() {
  late MockLocationService mockLocationService;
  late MockSessionRepository mockSessionRepository;
  late ImportedRouteState routeState;

  const sampleGpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="RoadCompanion">
  <metadata><name>Ruta Caldas Aventura</name></metadata>
  <trk>
    <trkseg>
      <trkpt lat="5.0000" lon="-75.0000"><ele>1200.0</ele></trkpt>
      <trkpt lat="5.0100" lon="-75.0000"><ele>1250.0</ele></trkpt>
      <trkpt lat="5.0200" lon="-75.0000"><ele>1300.0</ele></trkpt>
    </trkseg>
  </trk>
</gpx>''';

  setUp(() {
    mockLocationService = MockLocationService();
    mockSessionRepository = MockSessionRepository();
    routeState = ImportedRouteState();
    final parsed = const GpxParser().parse(sampleGpx);
    routeState.setRoute(parsed);
  });

  tearDown(() {
    mockLocationService.dispose();
  });

  testWidgets(
    'Flujo interactivo de seguimiento GPS, pausa y finalización con diálogo de resumen',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: ImportedRouteScope(
            routeState: routeState,
            child: NavigationScreen(
              routeState: routeState,
              locationService: mockLocationService,
              sessionRepository: mockSessionRepository,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Validar presencia del panel de telemetría y botón de inicio
      expect(find.byType(GpxLiveTrackingPanel), findsOneWidget);
      expect(find.text('INICIAR SEGUIMIENTO GPS'), findsOneWidget);
      expect(find.text('LISTO PARA SEGUIR'), findsOneWidget);

      // 1. Tocar "INICIAR SEGUIMIENTO GPS"
      await tester.tap(find.text('INICIAR SEGUIMIENTO GPS'));
      await tester.pump();

      expect(find.text('BUSCANDO GPS...'), findsOneWidget);

      // 2. Emitir lectura GPS válida
      mockLocationService.emitPosition(
        GpsPosition(
          coordinates: Coordinates(5.0050, -75.0000),
          accuracyMeters: 6.0,
          speedMps: 15.0, // 54 km/h
          timestamp: DateTime.now(),
        ),
      );
      await tester.pump();

      expect(find.text('SIGUIENDO RUTA'), findsOneWidget);
      expect(find.text('54'), findsOneWidget);
      expect(find.text('±6 m'), findsOneWidget);
      expect(find.text('Pausar'), findsOneWidget);
      expect(find.text('Finalizar'), findsOneWidget);

      // 3. Pausar el seguimiento
      await tester.tap(find.text('Pausar'));
      await tester.pump();

      expect(find.text('PAUSADO'), findsOneWidget);
      expect(find.text('Reanudar'), findsOneWidget);

      // 4. Finalizar el seguimiento (diálogo de confirmación)
      await tester.tap(
        find.descendant(
          of: find.byType(GpxLiveTrackingPanel),
          matching: find.text('Finalizar'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('¿Finalizar sesión de seguimiento?'), findsOneWidget);

      // Confirmar en el diálogo
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Finalizar'),
        ),
      );
      await tester.pumpAndSettle();

      // Debe emerger el diálogo de resumen de la sesión
      expect(find.byType(SessionSummaryDialog), findsOneWidget);
      expect(find.text('Sesión finalizada'), findsOneWidget);
      expect(find.text('INTERRUMPIDA'), findsOneWidget);

      // Cerrar diálogo de resumen
      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();

      expect(find.byType(SessionSummaryDialog), findsNothing);
    },
  );
}
