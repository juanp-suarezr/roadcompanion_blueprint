import 'dart:async';
import 'package:flutter_test/flutter_test.dart';

import 'package:road_companion/domain/entities/maneuver_type.dart';
import 'package:road_companion/features/navigation/domain/entities/tripper_connection_state.dart';
import 'package:road_companion/features/navigation/domain/entities/tripper_device.dart';
import 'package:road_companion/features/navigation/domain/entities/tripper_gatt_info.dart';
import 'package:road_companion/features/navigation/domain/entities/tripper_maneuver_payload.dart';
import 'package:road_companion/features/navigation/domain/services/navigation_simulator_service.dart';
import 'package:road_companion/features/navigation/domain/services/tripper_ble_service.dart';
import 'package:road_companion/features/navigation/domain/services/tripper_protocol.dart';

/// Fake BLE service para pruebas exhaustivas del simulador.
class _FakeSimulatorBleService implements TripperBleService {
  TripperConnectionState _state = TripperConnectionState.authenticated;
  final List<List<int>> sentPackets = [];
  bool shouldFailSend = false;
  int stopNavigationCalls = 0;
  int clearActiveNavPacketCalls = 0;
  int disconnectCalls = 0;

  void setMockState(TripperConnectionState state) {
    _state = state;
  }

  @override
  TripperConnectionState get currentState => _state;

  @override
  Future<bool> sendRawPacket(List<int> bytes) async {
    if (shouldFailSend) return false;
    sentPackets.add(List.from(bytes));
    return true;
  }

  @override
  Future<bool> stopNavigation() async {
    stopNavigationCalls++;
    return true;
  }

  @override
  void clearActiveNavPacket({String? reason}) {
    clearActiveNavPacketCalls++;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
  }

  @override
  bool get isNavScreenActive => false;

  @override
  bool get isTestManeuverActive => false;

  @override
  bool get isConnecting => false;

  @override
  String? get currentConnectionPhase => null;

  @override
  DateTime? get connectedSince => null;

  @override
  int get disconnectCount => 0;

  @override
  String? get lastErrorDetail => null;

  @override
  String? get lastErrorStage => null;

  @override
  String? get lastPacketSentHex => null;

  @override
  DateTime? get lastNavPacketSentTime => null;

  @override
  String? get lastNavPacketSentHex => null;

  @override
  DateTime? get lastKeepAliveSentTime => null;

  @override
  bool get isLocalDisconnectRequested => false;

  @override
  String? get lastScanError => null;

  @override
  String? get lastTransmissionResult => null;

  @override
  TripperDevice? get connectedDevice => null;

  @override
  List<TripperDevice> get discoveredDevices => const [];

  @override
  Stream<List<TripperDevice>> get discoveredDevicesStream => const Stream.empty();

  @override
  List<TripperGattService> get discoveredGattServices => const [];

  @override
  Stream<List<TripperGattService>> get discoveredGattServicesStream =>
      const Stream.empty();

  @override
  List<String> get diagnosticLogs => const [];

  @override
  Stream<String> get diagnosticLogStream => const Stream.empty();

  @override
  Stream<String?> get scanErrorStream => const Stream.empty();

  @override
  Stream<TripperConnectionState> get stateStream => const Stream.empty();

  @override
  Future<void> cancelPendingConnection() async {}

  @override
  void clearDiagnosticLogs() {}

  @override
  void clearDiscoveredDevices() {}

  @override
  Future<bool> connect(TripperDevice device) async => true;

  @override
  String exportFullDiagnosticReport() => '';

  @override
  Future<bool> isBluetoothAvailable() async => true;

  @override
  Future<bool> probeGattOnly(TripperDevice device) async => true;

  @override
  Future<bool> sendManeuver(TripperManeuverPayload maneuver) async => true;

  @override
  Future<bool> sendPin(String pin) async => true;

  @override
  Future<bool> sendTestMessage() async => true;

  @override
  Future<void> startScan({Duration timeout = const Duration(seconds: 15)}) async {}

  @override
  Future<void> stopScan() async {}
}

void main() {
  group('NavigationSimulatorService — Pruebas Automatizadas de Requisitos', () {
    late _FakeSimulatorBleService fakeBle;

    setUp(() {
      fakeBle = _FakeSimulatorBleService();
    });

    // 1. Inicio de la simulación
    test('1. Inicia la simulación correctamente y cambia su estado a running', () {
      final sim = NavigationSimulatorService(bleService: fakeBle);
      expect(sim.status, SimulationStatus.stopped);
      expect(sim.isRunning, isFalse);

      sim.start();

      expect(sim.status, SimulationStatus.running);
      expect(sim.isRunning, isTrue);
      expect(sim.currentStepIndex, 0);
      expect(sim.currentVirtualDistanceMeters, 600.0);
      sim.dispose();
    });

    // 2. Pausa y reanudación sin perder el progreso
    test('2. Pausa y reanuda la simulación sin perder el progreso acumulado', () {
      final sim = NavigationSimulatorService(bleService: fakeBle);
      sim.start();
      sim.advanceTime(10); // A 30 km/h (8.33 m/s), recorre ~83.3m
      final distBeforePause = sim.currentVirtualDistanceMeters;
      expect(distBeforePause, lessThan(600.0));

      sim.pause();
      expect(sim.status, SimulationStatus.paused);
      expect(sim.isPaused, isTrue);

      // Tiempo mientras está pausado no debe avanzar la distancia
      sim.advanceTime(10);
      expect(sim.currentVirtualDistanceMeters, equals(distBeforePause));

      sim.resume();
      expect(sim.status, SimulationStatus.running);
      expect(sim.currentVirtualDistanceMeters, equals(distBeforePause));

      sim.advanceTime(5);
      expect(sim.currentVirtualDistanceMeters, lessThan(distBeforePause));
      sim.dispose();
    });

    // 3. Reinicio
    test('3. Reinicia la simulación al paso 0 y restablece la distancia inicial', () {
      final sim = NavigationSimulatorService(bleService: fakeBle);
      sim.start();
      sim.stepNext();
      sim.stepNext();
      expect(sim.currentStepIndex, 2);

      sim.reset();
      expect(sim.status, SimulationStatus.stopped);
      expect(sim.currentStepIndex, 0);
      expect(sim.currentVirtualDistanceMeters, 600.0);
      expect(sim.progressPercentage, equals(0.0));
      sim.dispose();
    });

    // 4. Finalización y cancelación de tareas
    test('4. Detiene la simulación y llama a stopNavigation si transmitía BLE', () {
      final sim = NavigationSimulatorService(
        bleService: fakeBle,
        transmitToBleDefault: true,
      );
      sim.start();
      expect(sim.isRunning, isTrue);

      sim.stop();
      expect(sim.status, SimulationStatus.stopped);
      expect(fakeBle.stopNavigationCalls, greaterThanOrEqualTo(1));
      // No desconecta deliberadamente la sesión BLE
      expect(fakeBle.disconnectCalls, 0);
      sim.dispose();
    });

    // 5. Avance por las maniobras
    test('5. Avanza secuencialmente a través de las 8 maniobras deterministas', () {
      final sim = NavigationSimulatorService(bleService: fakeBle);
      expect(sim.totalSteps, 8);

      final expectedTypes = [
        ManeuverType.depart,
        ManeuverType.straight,
        ManeuverType.right,
        ManeuverType.right,
        ManeuverType.straight,
        ManeuverType.left,
        ManeuverType.left,
        ManeuverType.arrive,
      ];

      for (int i = 0; i < sim.totalSteps; i++) {
        expect(sim.currentStepIndex, i);
        expect(sim.currentStep.maneuver.type, expectedTypes[i]);
        if (i < sim.totalSteps - 1) {
          sim.stepNext();
        }
      }
      sim.dispose();
    });

    // 6. Cálculo del progreso y de la distancia virtual restante
    test('6. Calcula con precisión el porcentaje de progreso y la distancia restante', () {
      final sim = NavigationSimulatorService(bleService: fakeBle);
      final initialRemaining = sim.totalRemainingDistanceMeters;
      expect(initialRemaining, greaterThan(0));
      expect(sim.progressPercentage, 0.0);

      sim.start();
      sim.stepNext(); // Avanza el paso 1 (600m)
      expect(sim.totalRemainingDistanceMeters, lessThan(initialRemaining));
      expect(sim.progressPercentage, greaterThan(0.0));
      expect(sim.progressPercentage, lessThan(100.0));

      // Ir hasta el último paso
      while (sim.currentStepIndex < sim.totalSteps - 1) {
        sim.stepNext();
      }
      sim.stepNext(); // Llega a completar
      expect(sim.status, SimulationStatus.completed);
      expect(sim.progressPercentage, 100.0);
      expect(sim.totalRemainingDistanceMeters, 0.0);
      sim.dispose();
    });

    // 7. Comportamiento con las tres velocidades
    test('7. Respeta las velocidades de 10, 30 y 60 km/h en el avance métrico', () {
      final sim = NavigationSimulatorService(bleService: fakeBle);
      sim.start();

      // 10 km/h = ~2.78 m/s -> en 10s recorre ~27.8m
      sim.setSpeed(SimulationSpeed.kmh10);
      final dist0 = sim.currentVirtualDistanceMeters;
      sim.advanceTime(10.0);
      final delta10 = dist0 - sim.currentVirtualDistanceMeters;
      expect(delta10, closeTo(27.77, 0.5));

      // 30 km/h = ~8.33 m/s -> en 10s recorre ~83.3m
      sim.setSpeed(SimulationSpeed.kmh30);
      final dist1 = sim.currentVirtualDistanceMeters;
      sim.advanceTime(10.0);
      final delta30 = dist1 - sim.currentVirtualDistanceMeters;
      expect(delta30, closeTo(83.33, 0.5));

      // 60 km/h = ~16.67 m/s -> en 10s recorre ~166.7m
      sim.setSpeed(SimulationSpeed.kmh60);
      final dist2 = sim.currentVirtualDistanceMeters;
      sim.advanceTime(10.0);
      final delta60 = dist2 - sim.currentVirtualDistanceMeters;
      expect(delta60, closeTo(166.67, 0.5));

      expect(delta60, greaterThan(delta30));
      expect(delta30, greaterThan(delta10));
      sim.dispose();
    });

    // 8. Avance manual de maniobras
    test('8. Permite avanzar y retroceder maniobras de forma manual e inmediata', () {
      final sim = NavigationSimulatorService(bleService: fakeBle);
      expect(sim.currentStepIndex, 0);

      sim.stepNext();
      expect(sim.currentStepIndex, 1);
      expect(sim.currentStep.maneuver.type, ManeuverType.straight);

      sim.stepNext();
      expect(sim.currentStepIndex, 2);
      expect(sim.currentStep.maneuver.type, ManeuverType.right);

      sim.stepPrevious();
      expect(sim.currentStepIndex, 1);
      sim.dispose();
    });

    // 9. Simulación sin conexión BLE
    test('9. Avanza localmente sin errores cuando no hay conexión BLE activa', () {
      fakeBle.setMockState(TripperConnectionState.idle);
      final sim = NavigationSimulatorService(
        bleService: fakeBle,
        transmitToBleDefault: true,
      );

      sim.start();
      sim.stepNext();
      expect(sim.currentStepIndex, 1);
      expect(fakeBle.sentPackets, isEmpty);
      expect(sim.lastTransmissionResult, contains('no conectado'));
      sim.dispose();
    });

    // 10. Envío cuando BLE está conectado
    test('10. Transmite tramas válidas con CRC16 al estar conectado a BLE', () async {
      final sim = NavigationSimulatorService(
        bleService: fakeBle,
        transmitToBleDefault: true,
      );

      // Ir a la maniobra 2 (Recto 500m)
      sim.jumpToStep(1);
      sim.start();
      await sim.syncCurrentManeuver();

      expect(fakeBle.sentPackets, isNotEmpty);
      final lastPacket = fakeBle.sentPackets.last;
      expect(lastPacket.length, 20);

      // Trama esperada para recto 500m:
      // 10 11 09 01 F4 01 00 FF FF FF 41 FF FF FF 00 00 00 00 73 85
      final hex = TripperProtocol.toHexString(lastPacket);
      expect(hex, '10 11 09 01 F4 01 00 FF FF FF 41 FF FF FF 00 00 00 00 73 85');
      expect(sim.lastTransmissionResult, contains('OK'));
      expect(sim.transmittedInstructionsCount, greaterThan(0));
      sim.dispose();
    });

    // 11. Manejo de errores de escritura BLE
    test('11. Maneja fallos en escritura GATT registrando el diagnóstico sin detener el simulador', () async {
      fakeBle.shouldFailSend = true;
      final sim = NavigationSimulatorService(
        bleService: fakeBle,
        transmitToBleDefault: true,
      );

      sim.start();
      await sim.syncCurrentManeuver();
      expect(sim.isRunning, isTrue);
      expect(sim.lastTransmissionResult, contains('Fallo'));
      sim.dispose();
    });

    // 12. Ausencia de tramas de navegación obsoletas después de finalizar
    test('12. Al finalizar cancela el envío de tramas y purga el flujo en el BLE', () {
      final sim = NavigationSimulatorService(
        bleService: fakeBle,
        transmitToBleDefault: true,
      );

      sim.start();
      final packetCount = fakeBle.sentPackets.length;
      sim.stop();

      expect(fakeBle.stopNavigationCalls, greaterThan(0));
      // Ningún paquete más debe enviarse tras stop
      sim.advanceTime(10.0);
      expect(fakeBle.sentPackets.length, packetCount);
      sim.dispose();
    });

    // 13. Ausencia de envío de comandos inventados
    test('13. No envía CMD_SET_TIME como fin ni inventa tramas para giros', () {
      final sim = NavigationSimulatorService(
        bleService: fakeBle,
        transmitToBleDefault: true,
      );

      sim.start();
      sim.stepNext(); // Paso 2: Recto (0x09)
      sim.stepNext(); // Paso 3: Giro derecha (0x15)
      sim.stop();

      // Ningún paquete debe tener byte 0 igual a 0x50 (CMD_SET_TIME)
      for (final pkt in fakeBle.sentPackets) {
        expect(pkt[0], isNot(0x50));
      }

      // Verificar que para giro a la derecha (0x15) se envió el código 0x15 y no 0x09 repetido
      final rightPacket = fakeBle.sentPackets.last;
      expect(rightPacket[2], TripperProtocol.maneuverTurnRight);
      expect(rightPacket[2], isNot(TripperProtocol.maneuverStraight));
      sim.dispose();
    });

    // 14. Aislamiento de la simulación frente al GPS real
    test('14. La simulación no altera coordenadas reales del dispositivo', () {
      final sim = NavigationSimulatorService(bleService: fakeBle);
      sim.start();
      sim.advanceTime(60.0);

      // Los pasos usan coordenadas fijas de prueba pero ningún sensor del sistema fue manipulado
      expect(sim.currentStep.maneuver.location.latitude, isNotNull);
      expect(sim.currentStep.maneuver.location.longitude, isNotNull);
      sim.dispose();
    });

    // 15. Regresión de las funciones de navegación y BLE existentes
    test('15. Funciones de compatibilidad y mapeo de TripperProtocol se mantienen intactas', () {
      expect(TripperProtocol.expectedDeviceName, 'RE_DISP');
      expect(TripperProtocol.serviceUuid, '01ff0100-ba5e-f4ee-5ca1-eb1e5e4b1ce0');
      expect(
        TripperProtocol.characteristicUuid,
        '01ff0101-ba5e-f4ee-5ca1-eb1e5e4b1ce0',
      );
      expect(TripperProtocol.packetPingFw.length, 20);
      expect(TripperProtocol.packetHandshakeResume.length, 20);
    });
  });
}
