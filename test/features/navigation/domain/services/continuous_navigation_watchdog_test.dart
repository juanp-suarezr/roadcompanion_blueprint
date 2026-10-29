import 'dart:async';
import 'package:flutter_test/flutter_test.dart';

import 'package:road_companion/domain/entities/coordinates.dart';
import 'package:road_companion/domain/entities/maneuver.dart';
import 'package:road_companion/domain/entities/maneuver_type.dart';
import 'package:road_companion/features/navigation/domain/entities/simulated_maneuver_step.dart';
import 'package:road_companion/features/navigation/domain/entities/simulation_trace_event.dart';
import 'package:road_companion/features/navigation/domain/entities/tripper_connection_state.dart';
import 'package:road_companion/features/navigation/domain/entities/tripper_device.dart';
import 'package:road_companion/features/navigation/domain/entities/tripper_gatt_info.dart';
import 'package:road_companion/features/navigation/domain/entities/tripper_maneuver_payload.dart';
import 'package:road_companion/features/navigation/domain/services/navigation_simulator_service.dart';
import 'package:road_companion/features/navigation/domain/services/tripper_ble_service.dart';
import 'package:road_companion/features/navigation/domain/services/tripper_protocol.dart';

class _WatchdogFakeBleService implements TripperBleService {
  final TripperConnectionState _state = TripperConnectionState.authenticated;
  final List<List<int>> sentPackets = [];
  List<int>? activeNavPacket;
  int clearActiveNavPacketCalls = 0;
  int stopNavigationCalls = 0;
  int disconnectCalls = 0;

  @override
  TripperConnectionState get currentState => _state;

  @override
  Future<bool> sendRawPacket(List<int> bytes) async {
    sentPackets.add(List.from(bytes));
    if (bytes.length == 20 && bytes[0] == 0x10 && bytes[1] == 0x11) {
      activeNavPacket = List.from(bytes);
    }
    return true;
  }

  @override
  void clearActiveNavPacket({String? reason}) {
    clearActiveNavPacketCalls++;
    activeNavPacket = null;
  }

  @override
  Future<bool> stopNavigation() async {
    stopNavigationCalls++;
    activeNavPacket = null;
    return true;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
  }

  @override
  bool get isNavScreenActive => activeNavPacket != null;
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
  String? get lastPacketSentHex => sentPackets.isNotEmpty
      ? TripperProtocol.toHexString(sentPackets.last)
      : null;
  @override
  DateTime? get lastNavPacketSentTime => null;
  @override
  String? get lastNavPacketSentHex => lastPacketSentHex;
  @override
  DateTime? get lastKeepAliveSentTime => null;
  @override
  bool get isLocalDisconnectRequested => false;
  @override
  String? get lastScanError => null;
  @override
  String? get lastTransmissionResult => 'OK';
  @override
  TripperDevice? get connectedDevice => null;
  @override
  List<TripperDevice> get discoveredDevices => const [];
  @override
  Stream<List<TripperDevice>> get discoveredDevicesStream =>
      const Stream.empty();
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
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 15),
  }) async {}
  @override
  Future<void> stopScan() async {}
}

void main() {
  group('Navegación Continua, Curvas y Watchdog BLE (Objetivos A, B, C, D)', () {
    late _WatchdogFakeBleService bleService;
    late NavigationSimulatorService simulator;

    setUp(() {
      bleService = _WatchdogFakeBleService();
      simulator = NavigationSimulatorService(
        bleService: bleService,
        transmitToBleDefault: true,
      );
    });

    tearDown(() {
      simulator.dispose();
    });

    test(
      'Objetivo A: Transición de paso 3 a 4 no borra paquete activo ni provoca desconexión',
      () async {
        simulator.start();
        await simulator.syncCurrentManeuver();
        expect(simulator.currentStep.stepNumber, 1);
        expect(bleService.activeNavPacket, isNotNull);

        // Avanzar al paso 3 (índice 2, Aproximación a giro derecha 0x15)
        simulator.jumpToStep(2);
        await simulator.syncCurrentManeuver();
        expect(simulator.currentStep.stepNumber, 3);
        expect(
          simulator.currentStep.tripperManeuverCode,
          TripperProtocol.maneuverTurnRight,
        );
        expect(
          bleService.activeNavPacket![2],
          TripperProtocol.maneuverTurnRight,
        );

        // Avanzar el paso 3 hasta completar la distancia y pasar al paso 4
        final initialClears = bleService.clearActiveNavPacketCalls;
        simulator.advanceTime(100.0); // Recorrer toda la distancia del paso 3

        // Al entrar al paso 4 (Giro a la derecha en Calle 72)
        expect(simulator.currentStep.stepNumber, 4);
        expect(simulator.currentStep.isSupportedByTripper, isTrue);
        expect(
          simulator.currentStep.tripperManeuverCode,
          TripperProtocol.maneuverTurnRight,
        );

        // VERIFICACIÓN CRÍTICA: NO se debe haber invocado clearActiveNavPacket
        expect(bleService.clearActiveNavPacketCalls, initialClears);
        // El paquete activo debe seguir siendo una trama de pantalla 10 11 con opcode 0x15
        expect(bleService.activeNavPacket, isNotNull);
        expect(bleService.activeNavPacket![0], 0x10);
        expect(bleService.activeNavPacket![1], 0x11);
        expect(
          bleService.activeNavPacket![2],
          TripperProtocol.maneuverTurnRight,
        );
      },
    );

    test(
      'Objetivo A: Maniobra sin opcode específico envía trama segura 0x1C para alimentar watchdog',
      () async {
        // Crear un escenario con un paso sin opcode compatible
        final customSteps = [
          SimulatedManeuverStep(
            stepNumber: 1,
            maneuver: Maneuver(
              instructionText: 'Paso sin opcode',
              type: ManeuverType.unknown,
              location: Coordinates(4.65, -74.06),
              roadName: 'Vía rural no mapeada',
              distanceMeters: 300.0,
            ),
            initialDistanceMeters: 300,
            isSupportedByTripper: false,
            tripperManeuverCode: null,
            compatibilityNote: 'Sin código de icono asignado',
          ),
        ];

        final customBleService = _WatchdogFakeBleService();
        final customSim = NavigationSimulatorService(
          bleService: customBleService,
          customSteps: customSteps,
          transmitToBleDefault: true,
        );

        customSim.start();
        await customSim.syncCurrentManeuver();

        // Debe haber emitido la trama segura de transición 0x1C (re-routing)
        expect(customBleService.activeNavPacket, isNotNull);
        expect(customBleService.activeNavPacket![0], 0x10);
        expect(customBleService.activeNavPacket![1], 0x11);
        expect(
          customBleService.activeNavPacket![2],
          TripperProtocol.maneuverReRouting,
        );
        // clearActiveNavPacket NO debe haberse invocado
        expect(customBleService.clearActiveNavPacketCalls, 0);

        // Avanzar tiempo durante el paso sin opcode: sigue emitiendo refresco seguro con distancia
        customSim.advanceTime(2.0);
        expect(
          customBleService.activeNavPacket![2],
          TripperProtocol.maneuverReRouting,
        );

        customSim.dispose();
      },
    );

    test(
      'Objetivo A: Pausa mantiene el paquete activo para que keepalive refresque la pantalla',
      () async {
        simulator.start();
        await simulator.syncCurrentManeuver();
        expect(bleService.activeNavPacket, isNotNull);
        final lastActivePacket = List<int>.from(bleService.activeNavPacket!);

        simulator.pause();
        expect(simulator.status, SimulationStatus.paused);
        // En pausa, el paquete activo NO se limpia; el keepalive debe seguir enviándolo cada 2s
        expect(bleService.activeNavPacket, isNotNull);
        expect(bleService.activeNavPacket, equals(lastActivePacket));
        expect(bleService.clearActiveNavPacketCalls, 0);

        // Reanudar la simulación
        simulator.resume();
        expect(simulator.status, SimulationStatus.running);
        expect(bleService.activeNavPacket, isNotNull);
      },
    );

    test(
      'Objetivo A: Finalización real de ruta y Stop purgan la navegación formalmente',
      () async {
        simulator.start();
        await simulator.syncCurrentManeuver();
        expect(simulator.status, SimulationStatus.running);

        simulator.stop();
        expect(simulator.status, SimulationStatus.stopped);
        // stop() debe invocar stopNavigation() en el servicio BLE
        expect(bleService.stopNavigationCalls, 1);
        expect(bleService.activeNavPacket, isNull);

        // Reiniciar y avanzar hasta la meta
        simulator.reset();
        expect(bleService.stopNavigationCalls, 2);
        expect(simulator.currentStepIndex, 0);

        simulator.start();
        await simulator.syncCurrentManeuver();
        // Saltar al último paso (llegada al destino, índice 7 = paso 8)
        simulator.jumpToStep(7);
        await simulator.syncCurrentManeuver();
        expect(simulator.currentStep.maneuver.type, ManeuverType.arrive);

        // Avanzar hasta completar el recorrido
        simulator.advanceTime(50.0);
        expect(simulator.status, SimulationStatus.completed);
        // Al completar el recorrido se llama a stopNavigation()
        expect(bleService.stopNavigationCalls, greaterThanOrEqualTo(3));
      },
    );

    test(
      'Objetivo B: Diagnóstico de curvas — Estimador analiza geometría pero no inventa maniobras',
      () {
        // El estimador calcula la curvatura instantánea para la app
        expect(simulator.currentCurvature, isNotNull);
        expect(simulator.currentCurvature.type, isNotNull);

        // La lista de pasos de navegación contiene únicamente las maniobras de ruta
        for (final step in simulator.steps) {
          // Ningún paso tiene sustitución arbitraria de curva por recta
          if (step.maneuver.type == ManeuverType.right) {
            expect(step.tripperManeuverCode, TripperProtocol.maneuverTurnRight);
          } else if (step.maneuver.type == ManeuverType.left) {
            expect(step.tripperManeuverCode, TripperProtocol.maneuverTurnLeft);
          } else if (step.maneuver.type == ManeuverType.straight) {
            expect(step.tripperManeuverCode, TripperProtocol.maneuverStraight);
          }
        }
      },
    );

    test(
      'Objetivo C: Clasificación rigurosa de niveles de certeza de opcodes',
      () {
        // 1. Confirmados físicamente en el Tripper Pod
        expect(
          TripperProtocol.getOpcodeStatus(TripperProtocol.maneuverStraight),
          TripperOpcodeStatus.confirmedPhysical,
        );
        expect(
          TripperProtocol.getOpcodeStatus(TripperProtocol.maneuverDepart),
          TripperOpcodeStatus.confirmedPhysical,
        );
        expect(
          TripperProtocol.getOpcodeStatus(TripperProtocol.maneuverDestination),
          TripperOpcodeStatus.confirmedPhysical,
        );
        expect(
          TripperProtocol.getOpcodeStatus(TripperProtocol.maneuverTurnRight),
          TripperOpcodeStatus.confirmedPhysical,
        );

        // 2. Documentados en especificación comunitaria
        expect(
          TripperProtocol.getOpcodeStatus(TripperProtocol.maneuverTurnLeft),
          TripperOpcodeStatus.documented,
        );
        expect(
          TripperProtocol.getOpcodeStatus(TripperProtocol.maneuverSharpLeft),
          TripperOpcodeStatus.documented,
        );
        expect(
          TripperProtocol.getOpcodeStatus(TripperProtocol.maneuverSharpRight),
          TripperOpcodeStatus.documented,
        );
        expect(
          TripperProtocol.getOpcodeStatus(TripperProtocol.maneuverSlightLeft),
          TripperOpcodeStatus.documented,
        );
        expect(
          TripperProtocol.getOpcodeStatus(TripperProtocol.maneuverSlightRight),
          TripperOpcodeStatus.documented,
        );
        expect(
          TripperProtocol.getOpcodeStatus(TripperProtocol.maneuverReRouting),
          TripperOpcodeStatus.documented,
        );

        // 3. Probables
        expect(
          TripperProtocol.getOpcodeStatus(TripperProtocol.maneuverMergeRight),
          TripperOpcodeStatus.probable,
        );
        expect(
          TripperProtocol.getOpcodeStatus(TripperProtocol.maneuverForkLeft),
          TripperOpcodeStatus.probable,
        );

        // 4. Experimentales / desconocidos
        expect(
          TripperProtocol.getOpcodeStatus(0x42),
          TripperOpcodeStatus.experimental,
        );
        expect(
          TripperProtocol.getOpcodeStatus(0x99),
          TripperOpcodeStatus.experimental,
        );
      },
    );

    test(
      'Objetivo D: Trazabilidad completa con todos los campos obligatorios',
      () async {
        simulator.start();
        await simulator.syncCurrentManeuver();
        final lastTrace = simulator.lastTraceEvent;
        expect(lastTrace, isNotNull);

        // Validar presencia de todos los campos exigidos por Objetivo D
        expect(lastTrace!.timestamp, isNotNull);
        expect(lastTrace.stepNumber, 1);
        expect(lastTrace.nextStepNumber, 2);
        expect(lastTrace.distanceToManeuverMeters, greaterThan(0));
        expect(lastTrace.maneuverType, 'depart');
        expect(lastTrace.opcodeHex, '0x3C');
        expect(lastTrace.action, SimulationTraceAction.transmitted);
        expect(lastTrace.reason, isNotEmpty);
        expect(lastTrace.generatedPacketHex, startsWith('10 11 3C'));
        expect(lastTrace.bleConnectionState, isNotNull);

        final str = lastTrace.toString();
        expect(str, contains('Paso #1 -> Próx #2'));
        expect(str, contains('[Op: 0x3C]'));
        expect(str, contains('Trama: 10 11 3C'));
      },
    );
  });
}
