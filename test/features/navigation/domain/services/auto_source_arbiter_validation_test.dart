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

class _MockBleService implements TripperBleService {
  final List<TripperManeuverPayload> sentManeuvers = [];
  bool stopNavigationCalled = false;
  bool clearPacketCalled = false;

  @override
  TripperConnectionState get currentState => TripperConnectionState.connected;

  @override
  Stream<TripperConnectionState> get stateStream => const Stream.empty();

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

class _MockLocationService implements LocationService {
  final Stream<GpsPosition> stream;
  _MockLocationService(this.stream);

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
  }) => stream;
  @override
  Future<GpsPosition?> getCurrentPosition({
    Duration timeLimit = const Duration(seconds: 8),
  }) async => null;
}

class _MockVoiceService implements VoiceNavigationService {
  @override
  bool get isMuted => false;
  @override
  set isMuted(bool value) {}
  @override
  void toggleMute() {}
  @override
  bool get isAvailable => true;
  @override
  VoiceServiceStatus get status => VoiceServiceStatus.ready;
  @override
  String? get statusMessage => null;
  @override
  String? get lastSpokenText => null;
  @override
  Stream<VoiceServiceStatus> get statusStream => const Stream.empty();
  @override
  Future<void> init() async {}
  @override
  Future<bool> testVoice({String? sampleText}) async => true;
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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AutoNavigationSourceArbiter arbiter;
  final baseTime = DateTime(2026, 11, 3, 10, 0, 0);

  final sampleRoute = CalculatedRoute(
    routePlan: RoutePlan(
      origin: Coordinates(4.60, -74.08),
      destination: Coordinates(4.65, -74.05),
      estimatedDuration: const Duration(minutes: 20),
      geometry: [
        Coordinates(4.60, -74.08),
        Coordinates(4.62, -74.07),
        Coordinates(4.65, -74.05),
      ],
      totalDistanceMeters: 5000.0,
      maneuvers: [
        Maneuver(
          instructionText: 'Sal hacia el norte',
          type: ManeuverType.depart,
          location: Coordinates(4.60, -74.08),
          distanceMeters: 1000.0,
          roadName: 'Vía Central',
        ),
        Maneuver(
          instructionText: 'Gira a la derecha por Calle 100',
          type: ManeuverType.right,
          location: Coordinates(4.62, -74.07),
          distanceMeters: 4000.0,
          roadName: 'Calle 100',
        ),
      ],
    ),
    summary: 'Ruta Central',
  );

  BridgeNavigationInstruction makeInstruction({
    required BridgeSourceType source,
    required ManeuverType maneuver,
    required int distanceMeters,
    required String rawText,
    DateTime? timestamp,
    BridgeInstructionStatus status = BridgeInstructionStatus.recognized,
    bool isRemoved = false,
  }) {
    return BridgeNavigationInstruction(
      source: source,
      maneuverType: maneuver,
      distanceMeters: distanceMeters,
      rawText: rawText,
      receivedAt: timestamp ?? baseTime,
      status: status,
    );
  }

  setUp(() {
    InternalNavigationSessionManager.resetForTesting();
    arbiter = AutoNavigationSourceArbiter(
      stalenessTimeout: const Duration(seconds: 45),
    );
    AutoNavigationSourceArbiter.setMockInstance(arbiter);
  });

  tearDown(() {
    InternalNavigationSessionManager.resetForTesting();
    AutoNavigationSourceArbiter.setMockInstance(null);
  });

  group('Pruebas Obligatorias de Selección AUTO y Source Arbiter (Sección 2)', () {
    // 1. AUTO sin fuentes externas
    test(
      '1. AUTO sin fuentes externas permanece en reposo sin transmisión BLE no solicitada',
      () {
        expect(arbiter.activeSource, isNull);
        expect(arbiter.currentActiveInstruction, isNull);
        expect(arbiter.isInternalNavigationActive, isFalse);
      },
    );

    // 2. AUTO con navegación interna activa
    test(
      '2. AUTO con navegación interna activa despacha al Tripper y bloquea notificaciones externas',
      () async {
        final ble = _MockBleService();
        final manager = InternalNavigationSessionManager.instance;

        final started = await manager.startSession(
          route: sampleRoute,
          destination: Destination(
            id: 'd1',
            title: 'Calle 100',
            coordinates: Coordinates(4.65, -74.05),
          ),
          locationService: _MockLocationService(
            Stream.value(
              GpsPosition(
                coordinates: Coordinates(4.60, -74.08),
                accuracyMeters: 3.0,
                timestamp: baseTime,
              ),
            ),
          ),
          bleService: ble,
          voiceService: _MockVoiceService(),
          arbiter: arbiter,
          selectedSourceProvider: () => SelectedNavigationSourceType.auto,
        );

        expect(started, isTrue);
        expect(manager.isNavigating, isTrue);
        expect(arbiter.isInternalNavigationActive, isTrue);

        // Esperar breve microtask
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Verificación: la instrucción interna llegó a BLE en modo AUTO
        expect(ble.sentManeuvers, isNotEmpty);
        expect(
          ble.sentManeuvers.first.maneuverType,
          equals(TripperManeuverType.depart),
        );

        // Notificación externa entrante durante navegación interna es ignorada
        final ext = makeInstruction(
          source: BridgeSourceType.waze,
          maneuver: ManeuverType.left,
          distanceMeters: 200,
          rawText: 'Gira a la izquierda en 200 m',
        );
        final res = arbiter.processInstruction(
          ext,
          correlationId: 'auto_ext_during_internal',
        );
        expect(res.action, equals(AutoArbitrationAction.ignored));
        expect(arbiter.activeSource, isNull);
      },
    );

    // 3. AUTO con Waze activo
    test(
      '3. AUTO con Waze activo selecciona Waze y despacha sus maniobras a BLE',
      () {
        final waze = makeInstruction(
          source: BridgeSourceType.waze,
          maneuver: ManeuverType.right,
          distanceMeters: 400,
          rawText: 'En 400 m gira a la derecha',
          timestamp: baseTime,
        );

        final res = arbiter.processInstruction(
          waze,
          correlationId: 'waze_active_1',
        );

        expect(res.action, equals(AutoArbitrationAction.activated));
        expect(res.shouldTransmitToBle, isTrue);
        expect(arbiter.activeSource, equals(BridgeSourceType.waze));
        expect(arbiter.currentActiveInstruction, equals(waze));
      },
    );

    // 4. AUTO con Google Maps activo
    test(
      '4. AUTO con Google Maps activo selecciona Maps y despacha sus maniobras a BLE',
      () {
        final maps = makeInstruction(
          source: BridgeSourceType.googleMaps,
          maneuver: ManeuverType.left,
          distanceMeters: 300,
          rawText: 'En 300 m gira a la izquierda',
          timestamp: baseTime,
        );

        final res = arbiter.processInstruction(
          maps,
          correlationId: 'maps_active_1',
        );

        expect(res.action, equals(AutoArbitrationAction.activated));
        expect(res.shouldTransmitToBle, isTrue);
        expect(arbiter.activeSource, equals(BridgeSourceType.googleMaps));
        expect(arbiter.currentActiveInstruction, equals(maps));
      },
    );

    // 5. Expiración de Waze
    test(
      '5. Expiración de Waze por inactividad (>45s) permite fallback o estado sin navegación',
      () {
        final waze = makeInstruction(
          source: BridgeSourceType.waze,
          maneuver: ManeuverType.right,
          distanceMeters: 400,
          rawText: 'En 400 m gira a la derecha',
          timestamp: baseTime,
        );
        arbiter.processInstruction(waze, correlationId: 'waze_exp_1');
        expect(arbiter.activeSource, equals(BridgeSourceType.waze));

        // Verificar que el estado de Waze expira pasados 46 segundos
        final wazeState = arbiter.getSourceState(BridgeSourceType.waze);
        expect(
          wazeState?.isUnexpired(
            now: baseTime.add(const Duration(seconds: 46)),
            maxAge: const Duration(seconds: 45),
          ),
          isFalse,
        );
      },
    );

    // 6. Cancelación de Maps
    test(
      '6. Cancelación de Maps elimina su instrucción anterior y detiene la navegación',
      () {
        final maps = makeInstruction(
          source: BridgeSourceType.googleMaps,
          maneuver: ManeuverType.left,
          distanceMeters: 500,
          rawText: 'En 500 m gira a la izquierda',
          timestamp: baseTime,
        );
        arbiter.processInstruction(maps, correlationId: 'maps_cancel_1');
        expect(arbiter.activeSource, equals(BridgeSourceType.googleMaps));

        // Cancelar Maps
        final removal = makeInstruction(
          source: BridgeSourceType.googleMaps,
          maneuver: ManeuverType.unknown,
          distanceMeters: 0,
          rawText: '',
          status: BridgeInstructionStatus.stale,
          timestamp: baseTime.add(const Duration(seconds: 5)),
          isRemoved: true,
        );

        final res = arbiter.processInstruction(
          removal,
          correlationId: 'maps_cancel_2',
          isRemoved: true,
        );

        expect(res.action, equals(AutoArbitrationAction.sourceEnded));
        expect(res.shouldStopBleNavigation, isTrue);
        expect(arbiter.activeSource, isNull);
        expect(arbiter.currentActiveInstruction, isNull);
      },
    );

    // 7. Recuperación de navegación interna
    test(
      '7. Recuperación de navegación interna tras finalizar fuente externa',
      () async {
        final ble = _MockBleService();
        final manager = InternalNavigationSessionManager.instance;

        // 1. Waze estaba activo
        final waze = makeInstruction(
          source: BridgeSourceType.waze,
          maneuver: ManeuverType.right,
          distanceMeters: 600,
          rawText: 'En 600 m gira a la derecha',
          timestamp: baseTime,
        );
        arbiter.processInstruction(waze, correlationId: 'waze_before_internal');
        expect(arbiter.activeSource, equals(BridgeSourceType.waze));

        // 2. Waze finaliza su ruta
        final wazeEnd = makeInstruction(
          source: BridgeSourceType.waze,
          maneuver: ManeuverType.unknown,
          distanceMeters: 0,
          rawText: '',
          status: BridgeInstructionStatus.stale,
          timestamp: baseTime.add(const Duration(seconds: 5)),
          isRemoved: true,
        );
        arbiter.processInstruction(
          wazeEnd,
          correlationId: 'waze_ended',
          isRemoved: true,
        );
        expect(arbiter.activeSource, isNull);

        // 3. El usuario inicia navegación interna
        final started = await manager.startSession(
          route: sampleRoute,
          locationService: _MockLocationService(
            Stream.value(
              GpsPosition(
                coordinates: Coordinates(4.60, -74.08),
                accuracyMeters: 3.0,
                timestamp: baseTime.add(const Duration(seconds: 10)),
              ),
            ),
          ),
          bleService: ble,
          voiceService: _MockVoiceService(),
          arbiter: arbiter,
          selectedSourceProvider: () => SelectedNavigationSourceType.auto,
        );

        expect(started, isTrue);
        expect(arbiter.isInternalNavigationActive, isTrue);

        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(ble.sentManeuvers, isNotEmpty);
      },
    );

    // 8. Cambio de fuente sin instrucciones duplicadas
    test(
      '8. Cambio de fuente sin instrucciones duplicadas ignora eventos repetidos consecutivos',
      () {
        final maps = makeInstruction(
          source: BridgeSourceType.googleMaps,
          maneuver: ManeuverType.right,
          distanceMeters: 400,
          rawText: 'En 400 m gira a la derecha',
          timestamp: baseTime,
        );
        final res1 = arbiter.processInstruction(
          maps,
          correlationId: 'maps_dup_1',
        );
        expect(res1.action, equals(AutoArbitrationAction.activated));

        // Misma instrucción consecutiva recibida 1 segundo después
        final dup = makeInstruction(
          source: BridgeSourceType.googleMaps,
          maneuver: ManeuverType.right,
          distanceMeters: 400,
          rawText: 'En 400 m gira a la derecha',
          timestamp: baseTime.add(const Duration(seconds: 1)),
        );
        final res2 = arbiter.processInstruction(
          dup,
          correlationId: 'maps_dup_2',
        );

        expect(res2.action, equals(AutoArbitrationAction.duplicate));
        expect(res2.shouldTransmitToBle, isFalse);

        // Cambio a Waze con nueva instrucción más reciente
        final waze = makeInstruction(
          source: BridgeSourceType.waze,
          maneuver: ManeuverType.left,
          distanceMeters: 250,
          rawText: 'En 250 m gira a la izquierda',
          timestamp: baseTime.add(const Duration(seconds: 4)),
        );
        final res3 = arbiter.processInstruction(
          waze,
          correlationId: 'waze_switch_3',
        );

        expect(res3.action, equals(AutoArbitrationAction.switched));
        expect(res3.newSource, equals(BridgeSourceType.waze));
        expect(res3.shouldTransmitToBle, isTrue);
      },
    );
  });
}
