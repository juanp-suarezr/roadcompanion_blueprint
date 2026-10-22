import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_companion/domain/entities/maneuver_type.dart';
import 'package:road_companion/features/bridge/domain/entities/bridge_instruction_status.dart';
import 'package:road_companion/features/bridge/domain/entities/bridge_navigation_instruction.dart';
import 'package:road_companion/features/bridge/domain/entities/bridge_source_type.dart';
import 'package:road_companion/features/bridge/infrastructure/services/bridge_navigation_source.dart';
import 'package:road_companion/features/navigation/domain/entities/tripper_connection_state.dart';
import 'package:road_companion/features/navigation/domain/entities/tripper_device.dart';
import 'package:road_companion/features/navigation/domain/entities/tripper_gatt_info.dart';
import 'package:road_companion/features/navigation/domain/entities/tripper_maneuver_payload.dart';
import 'package:road_companion/features/navigation/domain/services/tripper_ble_service.dart';
import 'package:road_companion/features/navigation/domain/services/tripper_navigation_adapter.dart';
import 'package:road_companion/features/navigation/infrastructure/services/navigation_instruction_bridge.dart';

class _FakeBleService implements TripperBleService {
  TripperConnectionState _state = TripperConnectionState.idle;
  List<int>? lastRawPacket;
  bool returnSuccess = true;

  void setState(TripperConnectionState state) {
    _state = state;
  }

  @override
  TripperConnectionState get currentState => _state;

  @override
  Future<bool> sendRawPacket(List<int> bytes) async {
    lastRawPacket = bytes;
    return returnSuccess;
  }

  @override
  Future<bool> sendManeuver(TripperManeuverPayload maneuver) async => true;

  @override
  Future<bool> sendPin(String pin) async => true;

  @override
  Future<bool> sendTestMessage() async => true;

  @override
  Future<void> cancelPendingConnection() async {}

  @override
  void clearDiagnosticLogs() {}

  @override
  void clearDiscoveredDevices() {}

  @override
  TripperDevice? get connectedDevice => null;

  @override
  DateTime? get connectedSince => null;

  @override
  String? get currentConnectionPhase => null;

  @override
  List<String> get diagnosticLogs => [];

  @override
  Stream<String> get diagnosticLogStream => const Stream.empty();

  @override
  int get disconnectCount => 0;

  @override
  List<TripperDevice> get discoveredDevices => [];

  @override
  Stream<List<TripperDevice>> get discoveredDevicesStream => const Stream.empty();

  @override
  List<TripperGattService> get discoveredGattServices => [];

  @override
  Stream<List<TripperGattService>> get discoveredGattServicesStream =>
      const Stream.empty();

  @override
  Future<void> disconnect() async {}

  @override
  String exportFullDiagnosticReport() => '';

  @override
  bool get isConnecting => false;

  @override
  String? get lastErrorDetail => null;

  @override
  String? get lastErrorStage => null;

  @override
  String? get lastPacketSentHex => null;

  @override
  String? get lastScanError => null;

  @override
  String? get lastTransmissionResult => null;

  @override
  Stream<String?> get scanErrorStream => const Stream.empty();

  @override
  Stream<TripperConnectionState> get stateStream => const Stream.empty();

  @override
  Future<void> startScan({Duration timeout = const Duration(seconds: 15)}) async {}

  @override
  Future<void> stopScan() async {}

  @override
  Future<bool> isBluetoothAvailable() async => true;

  @override
  Future<bool> connect(TripperDevice device) async => true;
}

class _FakeNavSource extends BridgeNavigationSource {
  final _controller = StreamController<BridgeNavigationInstruction>.broadcast();

  @override
  Stream<BridgeNavigationInstruction> get instructions => _controller.stream;

  void emit(BridgeNavigationInstruction instruction) {
    _controller.add(instruction);
  }

  @override
  void start() {}

  @override
  void stop() {}
}

void main() {
  group('NavigationInstructionBridge - Flujo desacoplado Waze a Tripper', () {
    late _FakeBleService fakeBle;
    late _FakeNavSource fakeSource;
    late NavigationInstructionBridge bridge;

    setUp(() {
      fakeBle = _FakeBleService();
      fakeSource = _FakeNavSource();
      bridge = NavigationInstructionBridge(
        navigationSource: fakeSource,
        bleService: fakeBle,
        adapter: const TripperNavigationAdapter(),
      );
    });

    tearDown(() {
      bridge.dispose();
    });

    test('Instrucción válida de Waze retenida si BLE no está autenticado', () async {
      fakeBle.setState(TripperConnectionState.idle);
      bridge.start();

      final instruction = BridgeNavigationInstruction(
        source: BridgeSourceType.waze,
        maneuverType: ManeuverType.left,
        distanceMeters: 300,
        rawText: 'Gira a la izquierda en 300 m',
        receivedAt: DateTime(2026, 10, 22, 11, 0),
        status: BridgeInstructionStatus.recognized,
      );

      final eventFuture = bridge.eventsStream.first;
      fakeSource.emit(instruction);
      final event = await eventFuture;

      expect(event.adaptationResult.isSupported, isTrue);
      expect(event.transmittedToTripper, isFalse);
      expect(fakeBle.lastRawPacket, isNull);
    });

    test('Instrucción válida de Waze transmitida al Pod cuando BLE está autenticado',
        () async {
      fakeBle.setState(TripperConnectionState.authenticated);
      bridge.start();

      final instruction = BridgeNavigationInstruction(
        source: BridgeSourceType.waze,
        maneuverType: ManeuverType.right,
        distanceMeters: 450,
        rawText: 'Gira a la derecha en 450 m',
        receivedAt: DateTime(2026, 10, 22, 11, 0),
        status: BridgeInstructionStatus.recognized,
      );

      final eventFuture = bridge.eventsStream.first;
      fakeSource.emit(instruction);
      final event = await eventFuture;

      expect(event.adaptationResult.isSupported, isTrue);
      expect(event.transmittedToTripper, isTrue);
      expect(fakeBle.lastRawPacket, isNotNull);
      expect(fakeBle.lastRawPacket!.length, 20);
      expect(fakeBle.lastRawPacket![2], 0x15); // Turn right
    });

    test('Instrucción incompleta de Waze marcada como no compatible', () async {
      fakeBle.setState(TripperConnectionState.authenticated);
      bridge.start();

      final instruction = BridgeNavigationInstruction(
        source: BridgeSourceType.waze,
        maneuverType: ManeuverType.left,
        distanceMeters: null, // Falta distancia
        rawText: 'Gira a la izquierda',
        receivedAt: DateTime(2026, 10, 22, 11, 0),
        status: BridgeInstructionStatus.incomplete,
      );

      final eventFuture = bridge.eventsStream.first;
      fakeSource.emit(instruction);
      final event = await eventFuture;

      expect(event.adaptationResult.isSupported, isFalse);
      expect(event.transmittedToTripper, isFalse);
      expect(fakeBle.lastRawPacket, isNull);
    });
  });
}
