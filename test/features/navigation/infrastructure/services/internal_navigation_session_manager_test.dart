import 'dart:async';
import 'package:flutter_test/flutter_test.dart';

import 'package:road_companion/domain/entities/coordinates.dart';
import 'package:road_companion/domain/entities/maneuver.dart';
import 'package:road_companion/domain/entities/maneuver_type.dart';
import 'package:road_companion/domain/entities/route_plan.dart';
import 'package:road_companion/features/bridge/domain/entities/bridge_instruction_status.dart';
import 'package:road_companion/features/bridge/domain/entities/bridge_navigation_instruction.dart';
import 'package:road_companion/features/bridge/domain/entities/bridge_source_type.dart';
import 'package:road_companion/features/navigation/domain/entities/calculated_route.dart';
import 'package:road_companion/features/navigation/domain/entities/destination.dart';
import 'package:road_companion/features/navigation/domain/entities/gps_position.dart';
import 'package:road_companion/features/navigation/domain/entities/tripper_connection_state.dart';
import 'package:road_companion/features/navigation/domain/entities/tripper_maneuver_payload.dart';
import 'package:road_companion/features/navigation/domain/services/auto_navigation_source_arbiter.dart';
import 'package:road_companion/features/navigation/domain/services/location_service.dart';
import 'package:road_companion/features/navigation/domain/services/navigation_source.dart';
import 'package:road_companion/features/navigation/domain/services/tripper_ble_service.dart';
import 'package:road_companion/features/navigation/domain/services/voice_navigation_service.dart';
import 'package:road_companion/features/navigation/infrastructure/services/internal_navigation_session_manager.dart';

class FakeLocationService implements LocationService {
  final StreamController<GpsPosition> _gpsCtrl =
      StreamController<GpsPosition>.broadcast();

  bool get isGpsAvailable => true;

  Stream<GpsPosition> get positionStream => _gpsCtrl.stream;

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
  }) => _gpsCtrl.stream;

  @override
  Future<GpsPosition?> getCurrentPosition({
    Duration timeLimit = const Duration(seconds: 8),
  }) async => null;

  void dispose() {
    _gpsCtrl.close();
  }

  void emit(GpsPosition pos) => _gpsCtrl.add(pos);
}

class FakeTripperBleService implements TripperBleService {
  final _stateCtrl = StreamController<TripperConnectionState>.broadcast();
  final TripperConnectionState _currentState = TripperConnectionState.connected;
  final List<TripperManeuverPayload> sentManeuvers = [];
  bool stopNavigationCalled = false;
  bool clearPacketCalled = false;

  @override
  TripperConnectionState get currentState => _currentState;

  @override
  Stream<TripperConnectionState> get stateStream => _stateCtrl.stream;

  @override
  Future<bool> sendManeuver(TripperManeuverPayload payload) async {
    sentManeuvers.add(payload);
    return true;
  }

  @override
  Future<bool> stopNavigation() async {
    stopNavigationCalled = true;
    return true;
  }

  @override
  void clearActiveNavPacket({String? reason}) {
    clearPacketCalled = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeVoiceService implements VoiceNavigationService {
  @override
  Future<void> init() async {}
  @override
  Future<void> speak(String text, {bool interrupt = false}) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> processManeuverGuidance({
    required int maneuverIndex,
    required Maneuver maneuver,
    required double distanceToManeuverMeters,
    required double currentSpeedKmh,
  }) async {}
  @override
  Future<void> announceOffRoute() async {}
  @override
  Future<void> announceDestinationReached() async {}
  @override
  void resetGuidance() {}
  @override
  void dispose() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeLocationService fakeLocation;
  late FakeTripperBleService fakeBle;
  late FakeVoiceService fakeVoice;
  late AutoNavigationSourceArbiter arbiter;

  final sampleRoute = CalculatedRoute(
    routePlan: RoutePlan(
      origin: Coordinates(5.068, -75.517),
      destination: Coordinates(4.895, -75.322),
      estimatedDuration: const Duration(hours: 1),
      geometry: [
        Coordinates(5.068, -75.517),
        Coordinates(4.980, -75.410),
        Coordinates(4.895, -75.322),
      ],
      totalDistanceMeters: 20000.0,
      maneuvers: [
        Maneuver(
          instructionText: 'Inicia por Vía Principal',
          type: ManeuverType.depart,
          location: Coordinates(5.068, -75.517),
          distanceMeters: 5000.0,
          roadName: 'Vía Principal',
        ),
        Maneuver(
          instructionText: 'Gira a la derecha hacia Nevada',
          type: ManeuverType.right,
          location: Coordinates(4.980, -75.410),
          distanceMeters: 15000.0,
          roadName: 'Carretera Nevada',
        ),
        Maneuver(
          instructionText: 'Llegada al destino',
          type: ManeuverType.arrive,
          location: Coordinates(4.895, -75.322),
          distanceMeters: 0.0,
          roadName: 'Destino',
        ),
      ],
    ),
    summary: 'Vía Principal a Nevada',
  );

  setUp(() {
    InternalNavigationSessionManager.resetForTesting();
    fakeLocation = FakeLocationService();
    fakeBle = FakeTripperBleService();
    fakeVoice = FakeVoiceService();
    arbiter = AutoNavigationSourceArbiter();
    AutoNavigationSourceArbiter.setMockInstance(arbiter);
  });

  tearDown(() {
    InternalNavigationSessionManager.resetForTesting();
    AutoNavigationSourceArbiter.setMockInstance(null);
    fakeLocation.dispose();
  });

  group(
    'InternalNavigationSessionManager - Ciclo de vida desacoplado y Arbitraje',
    () {
      test(
        'Inicia sesión correctamente y otorga prioridad exclusiva sobre árbitro externo',
        () async {
          final manager = InternalNavigationSessionManager.instance;
          expect(manager.isNavigating, isFalse);
          expect(arbiter.isInternalNavigationActive, isFalse);

          final started = await manager.startSession(
            route: sampleRoute,
            destination: Destination(
              id: 'test_1',
              title: 'Nevada',
              coordinates: Coordinates(4.895, -75.322),
            ),
            locationService: fakeLocation,
            bleService: fakeBle,
            voiceService: fakeVoice,
            arbiter: arbiter,
            selectedSourceProvider: () => SelectedNavigationSourceType.auto,
          );

          expect(started, isTrue);
          expect(manager.isNavigating, isTrue);
          expect(manager.activeRoute, equals(sampleRoute));
          expect(arbiter.isInternalNavigationActive, isTrue);

          // Una notificación externa entrante de Waze debe ser ignorada por precedencia interna
          final wazeInstruction = BridgeNavigationInstruction(
            rawTitle: 'En 300 m',
            rawText: 'Gira a la izquierda',
            source: BridgeSourceType.waze,
            status: BridgeInstructionStatus.recognized,
            maneuverType: ManeuverType.left,
            distanceMeters: 300,
            receivedAt: DateTime.now(),
          );

          final arbitration = arbiter.processInstruction(
            wazeInstruction,
            correlationId: 'test_ext_1',
          );

          expect(arbitration.action, equals(AutoArbitrationAction.ignored));
          expect(arbitration.reason, contains('Navegación interna'));
        },
      );

      test(
        'Transmite maniobra al Tripper Pod en modo AUTO y respeta cadencia',
        () async {
          final manager = InternalNavigationSessionManager.instance;
          await manager.startSession(
            route: sampleRoute,
            destination: Destination(
              id: 'test_1',
              title: 'Nevada',
              coordinates: Coordinates(4.895, -75.322),
            ),
            locationService: fakeLocation,
            bleService: fakeBle,
            voiceService: fakeVoice,
            arbiter: arbiter,
            selectedSourceProvider: () => SelectedNavigationSourceType.auto,
          );

          // Emitir primera posición GPS
          fakeLocation.emit(
            GpsPosition(
              coordinates: Coordinates(5.068, -75.517),
              accuracyMeters: 5.0,
              speedMps: 10.0,
              timestamp: DateTime.now(),
            ),
          );

          // Pequeño ciclo de bombeo asíncrono
          await Future<void>.delayed(const Duration(milliseconds: 50));

          expect(fakeBle.sentManeuvers.isNotEmpty, isTrue);
          final firstTx = fakeBle.sentManeuvers.first;
          expect(firstTx.maneuverType, isNotNull);
          expect(manager.lastGpsPosition, isNotNull);
        },
      );

      test(
        'Detiene sesión limpiamente y restaura capacidad del árbitro externo',
        () async {
          final manager = InternalNavigationSessionManager.instance;
          await manager.startSession(
            route: sampleRoute,
            locationService: fakeLocation,
            bleService: fakeBle,
            voiceService: fakeVoice,
            arbiter: arbiter,
            selectedSourceProvider: () => SelectedNavigationSourceType.auto,
          );

          expect(manager.isNavigating, isTrue);
          expect(arbiter.isInternalNavigationActive, isTrue);

          await manager.stopSession();

          expect(manager.isNavigating, isFalse);
          expect(arbiter.isInternalNavigationActive, isFalse);
          expect(fakeBle.stopNavigationCalled, isTrue);
          expect(fakeBle.clearPacketCalled, isTrue);

          // Tras detener la sesión, las notificaciones externas vuelven a ser procesadas
          final wazeInstruction = BridgeNavigationInstruction(
            rawTitle: 'En 300 m',
            rawText: 'Gira a la izquierda',
            source: BridgeSourceType.waze,
            status: BridgeInstructionStatus.recognized,
            maneuverType: ManeuverType.left,
            distanceMeters: 300,
            receivedAt: DateTime.now(),
          );

          final arbitration = arbiter.processInstruction(
            wazeInstruction,
            correlationId: 'test_ext_2',
          );

          expect(arbitration.action, equals(AutoArbitrationAction.activated));
          expect(arbitration.shouldTransmitToBle, isTrue);
        },
      );
    },
  );
}
