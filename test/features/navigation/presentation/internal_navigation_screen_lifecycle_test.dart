import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:road_companion/app/state/app_settings_service.dart';
import 'package:road_companion/app/state/app_settings_state.dart';
import 'package:road_companion/domain/entities/coordinates.dart';
import 'package:road_companion/domain/entities/maneuver.dart';
import 'package:road_companion/domain/entities/maneuver_type.dart';
import 'package:road_companion/domain/entities/route_plan.dart';
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
import 'package:road_companion/features/navigation/presentation/navigation_screen.dart';

class _LifecycleFakeLocationService implements LocationService {
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

  void emit(GpsPosition pos) => _gpsCtrl.add(pos);

  void dispose() {
    _gpsCtrl.close();
  }
}

class _LifecycleFakeBleService implements TripperBleService {
  final _stateCtrl = StreamController<TripperConnectionState>.broadcast();
  final TripperConnectionState _currentState = TripperConnectionState.connected;
  final List<TripperManeuverPayload> dispatchedManeuvers = [];
  bool stopNavigationCalled = false;
  bool clearPacketCalled = false;

  @override
  TripperConnectionState get currentState => _currentState;

  @override
  Stream<TripperConnectionState> get stateStream => _stateCtrl.stream;

  @override
  Future<bool> sendManeuver(TripperManeuverPayload payload) async {
    dispatchedManeuvers.add(payload);
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

class _LifecycleFakeVoiceService implements VoiceNavigationService {
  bool _muted = false;

  @override
  bool get isMuted => _muted;

  @override
  set isMuted(bool value) => _muted = value;

  @override
  void toggleMute() => _muted = !_muted;

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

class _InMemorySettingsService extends AppSettingsService {
  SelectedNavigationSourceType source = SelectedNavigationSourceType.auto;

  _InMemorySettingsService() : super(null);

  @override
  SelectedNavigationSourceType loadSelectedNavigationSource() => source;

  @override
  Future<bool> saveSelectedNavigationSource(
    SelectedNavigationSourceType s,
  ) async {
    source = s;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _LifecycleFakeLocationService fakeLocation;
  late _LifecycleFakeBleService fakeBle;
  late _LifecycleFakeVoiceService fakeVoice;
  late AutoNavigationSourceArbiter arbiter;
  late AppSettingsState settingsState;

  final sampleRoute = CalculatedRoute(
    routePlan: RoutePlan(
      origin: Coordinates(5.0680, -75.5170),
      destination: Coordinates(5.0750, -75.5100),
      estimatedDuration: const Duration(minutes: 15),
      geometry: [
        Coordinates(5.0680, -75.5170),
        Coordinates(5.0700, -75.5150),
        Coordinates(5.0720, -75.5130),
        Coordinates(5.0750, -75.5100),
      ],
      totalDistanceMeters: 1200.0,
      maneuvers: [
        Maneuver(
          instructionText: 'Sal por Avenida Central',
          type: ManeuverType.depart,
          location: Coordinates(5.0680, -75.5170),
          distanceMeters: 300.0,
          roadName: 'Avenida Central',
        ),
        Maneuver(
          instructionText: 'Gira a la derecha por Calle 50',
          type: ManeuverType.right,
          location: Coordinates(5.0700, -75.5150),
          distanceMeters: 500.0,
          roadName: 'Calle 50',
        ),
        Maneuver(
          instructionText: 'Llegada a destino',
          type: ManeuverType.arrive,
          location: Coordinates(5.0750, -75.5100),
          distanceMeters: 0.0,
          roadName: 'Destino Final',
        ),
      ],
    ),
    summary: 'Avenida Central a Calle 50',
  );

  setUp(() {
    InternalNavigationSessionManager.resetForTesting();
    fakeLocation = _LifecycleFakeLocationService();
    fakeBle = _LifecycleFakeBleService();
    fakeVoice = _LifecycleFakeVoiceService();
    arbiter = AutoNavigationSourceArbiter();
    AutoNavigationSourceArbiter.setMockInstance(arbiter);
    settingsState = AppSettingsState(_InMemorySettingsService());
  });

  tearDown(() {
    InternalNavigationSessionManager.resetForTesting();
    AutoNavigationSourceArbiter.setMockInstance(null);
    fakeLocation.dispose();
  });

  Widget buildTestHost(Widget child) {
    return MaterialApp(
      home: AppSettingsScope(settings: settingsState, child: child),
    );
  }

  group('InternalNavigationSessionManager - Validación de Ciclo de Vida Desacoplado', () {
    testWidgets(
      'Demuestra que el tracker y el despacho BLE sobreviven a la destrucción de NavigationScreen',
      (tester) async {
        final manager = InternalNavigationSessionManager.instance;

        // 1. Montar pantalla de navegación inicial
        await tester.pumpWidget(
          buildTestHost(
            NavigationScreen(
              locationService: fakeLocation,
              tripperBleService: fakeBle,
              voiceService: fakeVoice,
            ),
          ),
        );
        await tester.pump();

        // Iniciar sesión activa de navegación interna
        final started = await manager.startSession(
          route: sampleRoute,
          destination: Destination(
            id: 'dest_test_1',
            title: 'Calle 50',
            coordinates: Coordinates(5.0750, -75.5100),
          ),
          locationService: fakeLocation,
          bleService: fakeBle,
          voiceService: fakeVoice,
          arbiter: arbiter,
          selectedSourceProvider: () => SelectedNavigationSourceType.auto,
        );

        expect(started, isTrue);
        expect(manager.isNavigating, isTrue);
        expect(arbiter.isInternalNavigationActive, isTrue);
        final initialTracker = manager.activeTracker;
        expect(initialTracker, isNotNull);

        // 2. Recibir primera posición GPS simulada
        fakeLocation.emit(
          GpsPosition(
            coordinates: Coordinates(5.0680, -75.5170),
            accuracyMeters: 4.0,
            speedMps: 8.0,
            timestamp: DateTime.now(),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        // 3. Comprobar primera maniobra generada y despachada a BLE
        expect(fakeBle.dispatchedManeuvers, isNotEmpty);
        final firstBleCount = fakeBle.dispatchedManeuvers.length;
        final firstManeuver = fakeBle.dispatchedManeuvers.first;
        expect(firstManeuver.isSupported, isTrue);

        // 4. DESTRUIR / REEMPLAZAR NavigationScreen (simulando cambio a Settings o Home)
        await tester.pumpWidget(
          buildTestHost(
            const Scaffold(
              body: Center(child: Text('Pantalla Home o Ajustes')),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 5. Verificar que la sesión permanece activa en el manager tras destruir el widget
        expect(manager.isNavigating, isTrue);
        expect(manager.activeTracker, equals(initialTracker));
        expect(manager.activeTracker!.isDisposed, isFalse);

        // 6. Recibir nueva posición GPS mientras NavigationScreen NO existe en el árbol
        // Se avanza sobre la geometría hacia Coordinates(5.0700, -75.5150)
        // Se emite la posición confirmada
        final newPos = GpsPosition(
          coordinates: Coordinates(5.0690, -75.5160),
          accuracyMeters: 3.5,
          speedMps: 11.0,
          timestamp: DateTime.now().add(const Duration(seconds: 3)),
        );
        fakeLocation.emit(newPos);
        fakeLocation.emit(newPos);
        await tester.pump(const Duration(milliseconds: 100));

        // 7. Generar segunda actualización de maniobra
        // 8. Comprobar que la segunda instrucción llegó al pipeline BLE sin depender de la pantalla
        expect(fakeBle.dispatchedManeuvers.length, greaterThan(firstBleCount));
        final secondManeuver = fakeBle.dispatchedManeuvers.last;
        expect(secondManeuver.isSupported, isTrue);

        // 9. Reabrir NavigationScreen y comprobar que se enlaza sin duplicar trackers ni suscripciones
        await tester.pumpWidget(
          buildTestHost(
            NavigationScreen(
              locationService: fakeLocation,
              tripperBleService: fakeBle,
              voiceService: fakeVoice,
            ),
          ),
        );
        await tester.pump();

        expect(manager.activeTracker, equals(initialTracker));
        expect(manager.isNavigating, isTrue);

        // 10. Finalización explícita cancela recursos limpia y completamente
        await manager.stopSession();
        expect(manager.isNavigating, isFalse);
        expect(arbiter.isInternalNavigationActive, isFalse);
        expect(fakeBle.stopNavigationCalled, isTrue);
        expect(fakeBle.clearPacketCalled, isTrue);

        await tester.pumpWidget(const SizedBox());
      },
    );
  });
}
