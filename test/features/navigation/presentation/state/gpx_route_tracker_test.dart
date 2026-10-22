import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_companion/domain/entities/coordinates.dart';
import 'package:road_companion/features/navigation/domain/entities/gps_position.dart';
import 'package:road_companion/features/navigation/domain/entities/gpx_tracking_status.dart';
import 'package:road_companion/features/navigation/domain/entities/imported_gpx_route.dart';
import 'package:road_companion/features/navigation/domain/entities/navigation_session.dart';
import 'package:road_companion/features/navigation/domain/repositories/session_repository.dart';
import 'package:road_companion/features/navigation/domain/services/location_service.dart';
import 'package:road_companion/features/navigation/infrastructure/parsers/gpx_parser.dart';
import 'package:road_companion/features/navigation/presentation/state/gpx_route_tracker.dart';

class FakeLocationService implements LocationService {
  LocationPermissionResult permissionResult = LocationPermissionResult.granted;
  bool isServiceEnabled = true;

  final StreamController<GpsPosition> _controller =
      StreamController<GpsPosition>.broadcast();
  int activeListeners = 0;

  void emitPosition(GpsPosition pos) {
    _controller.add(pos);
  }

  void emitError(Object error) {
    _controller.addError(error);
  }

  @override
  Future<bool> isLocationServiceEnabled() async => isServiceEnabled;

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
  }) {
    return _controller.stream.transform(
      StreamTransformer<GpsPosition, GpsPosition>.fromHandlers(
        handleData: (data, sink) {
          sink.add(data);
        },
      ),
    );
  }

  @override
  Future<GpsPosition?> getCurrentPosition({
    Duration timeLimit = const Duration(seconds: 8),
  }) async => null;

  void dispose() {
    _controller.close();
  }
}

class FakeSessionRepository implements SessionRepository {
  final List<NavigationSession> savedSessions = [];

  @override
  Future<List<NavigationSession>> getSessions() async =>
      List.unmodifiable(savedSessions);

  @override
  Future<void> saveSession(NavigationSession session) async {
    savedSessions.removeWhere((s) => s.id == session.id);
    savedSessions.insert(0, session);
  }

  @override
  Future<void> deleteSession(String id) async {
    savedSessions.removeWhere((s) => s.id == id);
  }
}

void main() {
  late FakeLocationService fakeLocationService;
  late FakeSessionRepository fakeSessionRepository;
  late ImportedGpxRoute testRoute;
  late DateTime simulatedTime;

  const gpxContent = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="RoadCompanion">
  <metadata><name>Ruta de Prueba StormBlue</name></metadata>
  <trk>
    <trkseg>
      <trkpt lat="5.0000" lon="-75.0000"><ele>1000.0</ele></trkpt>
      <trkpt lat="5.0050" lon="-75.0000"><ele>1020.0</ele></trkpt>
      <trkpt lat="5.0100" lon="-75.0000"><ele>1040.0</ele></trkpt>
      <trkpt lat="5.0150" lon="-75.0000"><ele>1060.0</ele></trkpt>
    </trkseg>
  </trk>
</gpx>''';

  setUp(() {
    fakeLocationService = FakeLocationService();
    fakeSessionRepository = FakeSessionRepository();
    testRoute = const GpxParser().parse(gpxContent);
    simulatedTime = DateTime(2026, 10, 20, 10, 0, 0);
  });

  tearDown(() {
    fakeLocationService.dispose();
  });

  GpxRouteTracker createTracker({
    double offRouteThreshold = 40.0,
    int offRouteFilter = 2,
    double maxAccuracyThreshold = 30.0,
    double destinationProximity = 50.0,
  }) {
    return GpxRouteTracker(
      route: testRoute,
      locationService: fakeLocationService,
      sessionRepository: fakeSessionRepository,
      clock: () => simulatedTime,
      offRouteThresholdMeters: offRouteThreshold,
      offRouteFilterSamples: offRouteFilter,
      maxAccuracyThresholdMeters: maxAccuracyThreshold,
      destinationProximityMeters: destinationProximity,
      gpsTimeoutDuration: const Duration(seconds: 10),
    );
  }

  group('GpxRouteTracker - Máquina de estados y seguimiento GPS (T2.1 MVP)', () {
    test(
      '1. Inicio exitoso de seguimiento solicita permisos y entra en searchingGps',
      () async {
        final tracker = createTracker();
        expect(tracker.status, equals(GpxTrackingStatus.idle));

        final started = await tracker.startTracking();

        expect(started, isTrue);
        expect(tracker.status, equals(GpxTrackingStatus.searchingGps));
        expect(tracker.permissionError, isNull);

        tracker.dispose();
      },
    );

    test(
      '2. Permiso denegado detiene el seguimiento con mensaje explicativo',
      () async {
        fakeLocationService.permissionResult = LocationPermissionResult.denied;
        final tracker = createTracker();

        final started = await tracker.startTracking();

        expect(started, isFalse);
        expect(tracker.status, equals(GpxTrackingStatus.stopped));
        expect(tracker.permissionError, contains('denegado'));

        tracker.dispose();
      },
    );

    test(
      '3. GPS desactivado detiene el seguimiento con aviso de sensor apagado',
      () async {
        fakeLocationService.permissionResult =
            LocationPermissionResult.serviceDisabled;
        final tracker = createTracker();

        final started = await tracker.startTracking();

        expect(started, isFalse);
        expect(tracker.status, equals(GpxTrackingStatus.stopped));
        expect(tracker.permissionError, contains('desactivado'));

        tracker.dispose();
      },
    );

    test(
      '4. Posición con precisión deficiente entra en lowAccuracy y no avanza la ruta',
      () async {
        final tracker = createTracker(maxAccuracyThreshold: 25.0);
        await tracker.startTracking();

        // Emitir lectura con precisión mala (±45 m > 25 m)
        fakeLocationService.emitPosition(
          GpsPosition(
            coordinates: Coordinates(5.0000, -75.0000),
            accuracyMeters: 45.0,
            timestamp: simulatedTime,
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(tracker.status, equals(GpxTrackingStatus.lowAccuracy));
        expect(tracker.validSamplesCount, equals(0));
        expect(tracker.distanceTraveledMeters, equals(0.0));

        tracker.dispose();
      },
    );

    test(
      '5. Posiciones válidas avanzan sobre la ruta y preservan monotonía',
      () async {
        final tracker = createTracker();
        await tracker.startTracking();

        // Punto inicial en el origen
        fakeLocationService.emitPosition(
          GpsPosition(
            coordinates: Coordinates(5.0000, -75.0000),
            accuracyMeters: 5.0,
            speedMps: 12.0, // ~43.2 km/h
            timestamp: simulatedTime,
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(tracker.status, equals(GpxTrackingStatus.tracking));
        expect(tracker.validSamplesCount, equals(1));
        expect(tracker.currentSpeedKmh, closeTo(43.2, 0.1));
        expect(tracker.distanceTraveledMeters, closeTo(0.0, 1.0));

        // Avanzar al punto 1 (5.0050, -75.0000)
        fakeLocationService.emitPosition(
          GpsPosition(
            coordinates: Coordinates(5.0050, -75.0000),
            accuracyMeters: 4.0,
            speedMps: 14.0, // ~50.4 km/h
            timestamp: simulatedTime.add(const Duration(seconds: 10)),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(tracker.distanceTraveledMeters, greaterThan(500.0));
        expect(
          tracker.remainingDistanceMeters,
          lessThan(testRoute.totalGeographicDistanceMeters),
        );
        expect(tracker.maxSpeedKmh, closeTo(50.4, 0.1));

        // Ruido leve hacia atrás no reduce la distancia recorrida acumulada (monotonía)
        final traveledBefore = tracker.distanceTraveledMeters;
        fakeLocationService.emitPosition(
          GpsPosition(
            coordinates: Coordinates(5.0049, -75.0000),
            accuracyMeters: 8.0,
            timestamp: simulatedTime.add(const Duration(seconds: 12)),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(tracker.distanceTraveledMeters, equals(traveledBefore));

        tracker.dispose();
      },
    );

    test(
      '6. Detección de desvío (off-route) con filtrado y auto-recuperación',
      () async {
        final tracker = createTracker(
          offRouteThreshold: 30.0,
          offRouteFilter: 2,
        );
        await tracker.startTracking();

        // Punto en la ruta
        fakeLocationService.emitPosition(
          GpsPosition(
            coordinates: Coordinates(5.0000, -75.0000),
            accuracyMeters: 5.0,
            timestamp: simulatedTime,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(tracker.status, equals(GpxTrackingStatus.tracking));

        // Primera muestra desviada 100m hacia el este
        fakeLocationService.emitPosition(
          GpsPosition(
            coordinates: Coordinates(5.0000, -74.9990), // ~111m lateral
            accuracyMeters: 5.0,
            timestamp: simulatedTime.add(const Duration(seconds: 2)),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        // Con filtro de 2 muestras, la primera no declara offRoute de golpe (evita rebotes)
        expect(tracker.status, equals(GpxTrackingStatus.tracking));

        // Segunda muestra consecutiva desviada
        fakeLocationService.emitPosition(
          GpsPosition(
            coordinates: Coordinates(5.0000, -74.9990),
            accuracyMeters: 5.0,
            timestamp: simulatedTime.add(const Duration(seconds: 4)),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(tracker.status, equals(GpxTrackingStatus.offRoute));
        expect(tracker.offRouteDistanceMeters, greaterThan(30.0));

        // Regresar al trazado (auto-recuperación)
        fakeLocationService.emitPosition(
          GpsPosition(
            coordinates: Coordinates(5.0050, -75.0000),
            accuracyMeters: 5.0,
            timestamp: simulatedTime.add(const Duration(seconds: 6)),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(tracker.status, equals(GpxTrackingStatus.tracking));
        expect(tracker.offRouteDistanceMeters, lessThan(10.0));

        tracker.dispose();
      },
    );

    test(
      '7. Finalización de ruta cerca del destino con progreso alto',
      () async {
        final tracker = createTracker(destinationProximity: 60.0);
        await tracker.startTracking();

        // Iniciar en punto medio
        fakeLocationService.emitPosition(
          GpsPosition(
            coordinates: Coordinates(5.0100, -75.0000),
            accuracyMeters: 5.0,
            timestamp: simulatedTime,
          ),
        );
        await Future<void>.delayed(Duration.zero);

        // Llegada exactamente al destino (5.0150, -75.0000)
        simulatedTime = simulatedTime.add(const Duration(minutes: 5));
        fakeLocationService.emitPosition(
          GpsPosition(
            coordinates: Coordinates(5.0150, -75.0000),
            accuracyMeters: 5.0,
            timestamp: simulatedTime,
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(tracker.status, equals(GpxTrackingStatus.completed));
        expect(tracker.progressPercentage, equals(100.0));
        expect(tracker.lastSavedSession, isNotNull);
        expect(tracker.lastSavedSession!.isCompleted, isTrue);

        // Comprobar persistencia de la sesión en el repositorio
        final sessions = await fakeSessionRepository.getSessions();
        expect(sessions.length, equals(1));
        expect(sessions.first.isCompleted, isTrue);

        tracker.dispose();
      },
    );

    test('8. Finalización anticipada registra sesión interrumpida', () async {
      final tracker = createTracker();
      await tracker.startTracking();

      fakeLocationService.emitPosition(
        GpsPosition(
          coordinates: Coordinates(5.0050, -75.0000),
          accuracyMeters: 5.0,
          timestamp: simulatedTime,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      // Detener manualmente
      await tracker.stopTracking(isCompleted: false);

      expect(tracker.status, equals(GpxTrackingStatus.stopped));
      expect(tracker.lastSavedSession, isNotNull);
      expect(tracker.lastSavedSession!.isCompleted, isFalse);

      final sessions = await fakeSessionRepository.getSessions();
      expect(sessions.first.isCompleted, isFalse);

      tracker.dispose();
    });

    test(
      '9. Cancelación de stream y ausencia de suscripciones duplicadas',
      () async {
        final tracker = createTracker();

        await tracker.startTracking();
        await tracker.startTracking(); // Doble inicio consecutivo

        // Emitir posición
        fakeLocationService.emitPosition(
          GpsPosition(
            coordinates: Coordinates(5.0000, -75.0000),
            accuracyMeters: 5.0,
            timestamp: simulatedTime,
          ),
        );
        await Future<void>.delayed(Duration.zero);

        // Las muestras no deben duplicarse por dobles suscripciones
        expect(tracker.validSamplesCount, equals(1));

        // Detener cancela el flujo
        await tracker.stopTracking();

        fakeLocationService.emitPosition(
          GpsPosition(
            coordinates: Coordinates(5.0050, -75.0000),
            accuracyMeters: 5.0,
            timestamp: simulatedTime,
          ),
        );
        await Future<void>.delayed(Duration.zero);

        // No procesa nada tras detener
        expect(tracker.validSamplesCount, equals(1));

        tracker.dispose();
      },
    );

    test(
      'startTracking con enableBackgroundTracking activa bandera y guarda telemetría en recordedPositions',
      () async {
        final fakeLocationService = FakeLocationService();
        final sessionRepo = FakeSessionRepository();

        final tracker = GpxRouteTracker(
          route: testRoute,
          locationService: fakeLocationService,
          sessionRepository: sessionRepo,
          clock: () => simulatedTime,
        );

        final started = await tracker.startTracking(
          enableBackgroundTracking: true,
        );
        expect(started, isTrue);
        expect(tracker.isBackgroundEnabled, isTrue);

        final pos = GpsPosition(
          coordinates: Coordinates(5.0000, -75.0000),
          accuracyMeters: 4.5,
          speedMps: 12.0,
          timestamp: simulatedTime,
        );

        fakeLocationService.emitPosition(pos);
        await Future<void>.delayed(Duration.zero);

        expect(tracker.recordedPositions.length, equals(1));
        expect(tracker.recordedPositions.first.accuracyMeters, equals(4.5));
        expect(tracker.recordedPositions.first.speedMps, equals(12.0));
        expect(
          tracker.recordedPositions.first.coordinates.latitude,
          equals(5.0000),
        );

        await tracker.stopTracking();
        expect(sessionRepo.savedSessions.length, equals(1));

        tracker.dispose();
      },
    );

    test(
      'Telemetría de posición en tiempo real: conteo, intervalo y detección de señal obsoleta (>10s)',
      () async {
        final tracker = GpxRouteTracker(
          route: testRoute,
          locationService: fakeLocationService,
          clock: () => simulatedTime,
        );

        await tracker.startTracking();
        expect(tracker.totalPositionsReceived, equals(0));
        expect(tracker.isPositionStale, isTrue);

        // 1. Primera posición
        final pos1 = GpsPosition(
          coordinates: Coordinates(5.0000, -75.0000),
          accuracyMeters: 5.0,
          timestamp: simulatedTime,
        );
        fakeLocationService.emitPosition(pos1);
        await Future<void>.delayed(Duration.zero);

        expect(tracker.totalPositionsReceived, equals(1));
        expect(tracker.lastPositionAgeSeconds, equals(0));
        expect(tracker.isPositionStale, isFalse);

        // 2. Segunda posición 2 segundos después
        simulatedTime = simulatedTime.add(const Duration(seconds: 2));
        final pos2 = GpsPosition(
          coordinates: Coordinates(5.0010, -75.0000),
          accuracyMeters: 6.0,
          timestamp: simulatedTime,
        );
        fakeLocationService.emitPosition(pos2);
        await Future<void>.delayed(Duration.zero);

        expect(tracker.totalPositionsReceived, equals(2));
        expect(tracker.lastPositionInterval?.inSeconds, equals(2));
        expect(tracker.isPositionStale, isFalse);

        // 3. Simular transcurso de 12 segundos sin nuevas posiciones (stale warning)
        simulatedTime = simulatedTime.add(const Duration(seconds: 12));
        expect(tracker.lastPositionAgeSeconds, equals(12));
        expect(tracker.isPositionStale, isTrue);

        // 4. Emisión de error en el proveedor GPS registra lastGpsError
        fakeLocationService.emitError('GPS_PROVIDER_DISABLED');
        await Future<void>.delayed(Duration.zero);
        expect(tracker.lastGpsError, contains('GPS_PROVIDER_DISABLED'));
        expect(tracker.status, equals(GpxTrackingStatus.gpsLost));

        tracker.dispose();
      },
    );
  });
}
