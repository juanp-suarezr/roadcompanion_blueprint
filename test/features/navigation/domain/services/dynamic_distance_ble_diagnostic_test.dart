import 'dart:async';
import 'package:flutter_test/flutter_test.dart';

import 'package:road_companion/domain/entities/coordinates.dart';
import 'package:road_companion/domain/entities/maneuver.dart';
import 'package:road_companion/domain/entities/maneuver_type.dart';
import 'package:road_companion/features/navigation/domain/entities/road_curvature.dart';
import 'package:road_companion/features/navigation/domain/entities/simulated_maneuver_step.dart';
import 'package:road_companion/features/navigation/domain/entities/simulation_trace_event.dart';
import 'package:road_companion/features/navigation/domain/entities/tripper_connection_state.dart';
import 'package:road_companion/features/navigation/domain/entities/tripper_device.dart';
import 'package:road_companion/features/navigation/domain/entities/tripper_gatt_info.dart';
import 'package:road_companion/features/navigation/domain/entities/tripper_maneuver_payload.dart';
import 'package:road_companion/features/navigation/domain/services/navigation_simulator_service.dart';
import 'package:road_companion/features/navigation/domain/services/tripper_ble_service.dart';
import 'package:road_companion/features/navigation/domain/services/tripper_protocol.dart';

class _DiagnosticFakeBleService implements TripperBleService {
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
  group('REStelar — Diagnóstico y Corrección de Metraje Dinámico en Tripper Pod', () {
    late _DiagnosticFakeBleService fakeBle;

    setUp(() {
      fakeBle = _DiagnosticFakeBleService();
    });

    test(
      '1. Aproximación métrica dinámica a curva (250m -> 200m -> 100m -> 50m -> 10m): distancia interna decrece continuamente',
      () async {
        final curveStep = SimulatedManeuverStep(
          stepNumber: 1,
          maneuver: Maneuver(
            instructionText: 'Curva a la derecha en 250 metros',
            location: Coordinates(4.8150, -75.6940),
            type: ManeuverType.right,
            distanceMeters: 250.0,
          ),
          initialDistanceMeters: 250,
          isSupportedByTripper: true,
          tripperManeuverCode: TripperProtocol.maneuverTurnRight,
          compatibilityNote:
              'Giro a la derecha con opcode 0x15 validado en protocolo',
        );

        final sim = NavigationSimulatorService(
          bleService: fakeBle,
          customSteps: [curveStep],
          transmitToBleDefault: true,
        );

        expect(sim.currentVirtualDistanceMeters, 250.0);
        sim.start();
        await sim.syncCurrentManeuver();

        expect(fakeBle.sentPackets, isNotEmpty);
        var lastPkt = fakeBle.sentPackets.last;
        expect((lastPkt[3] << 8) | lastPkt[4], 250);
        expect(lastPkt[2], TripperProtocol.maneuverTurnRight);

        // Simular avance a 200m (avanzar 3 segundos a 60 km/h = 16.67 m/s * 3s = 50m)
        sim.setSpeed(SimulationSpeed.kmh60);
        sim.advanceTime(3.0);
        expect(sim.currentVirtualDistanceMeters, closeTo(200.0, 0.5));
        expect(sim.trafficLight, ProximityTrafficLight.yellow);

        // Avanzar a 100m (avanzar 6 segundos adicionales = 100m)
        sim.advanceTime(6.0);
        expect(sim.currentVirtualDistanceMeters, closeTo(100.0, 0.5));
        expect(sim.trafficLight, ProximityTrafficLight.yellow);

        // Avanzar a 50m (avanzar 3 segundos adicionales = 50m)
        sim.advanceTime(3.0);
        expect(sim.currentVirtualDistanceMeters, closeTo(50.0, 0.5));
        expect(sim.trafficLight, ProximityTrafficLight.red);

        // Avanzar a 10m (avanzar 2.4 segundos adicionales = 40m)
        sim.advanceTime(2.4);
        expect(sim.currentVirtualDistanceMeters, closeTo(10.0, 0.5));
        expect(sim.trafficLight, ProximityTrafficLight.red);

        sim.dispose();
      },
    );

    test(
      '2. Trama binaria y CRC-16 cambian dinámicamente con la distancia y no quedan congelados',
      () async {
        final curveStep = SimulatedManeuverStep(
          stepNumber: 1,
          maneuver: Maneuver(
            instructionText: 'Curva suave a la derecha',
            location: Coordinates(4.8150, -75.6940),
            type: ManeuverType.slightRight,
            distanceMeters: 250.0,
          ),
          initialDistanceMeters: 250,
          isSupportedByTripper: true,
          tripperManeuverCode: TripperProtocol.maneuverSlightRight,
          compatibilityNote: 'Curva suave derecha 0x19',
        );

        final distances = [250, 200, 100, 50, 10];
        final packets = <List<int>>[];

        for (final dist in distances) {
          final pkt = curveStep.buildProtocolPacket(distanceMeters: dist)!;
          expect(pkt.length, 20);
          expect(pkt[0], 0x10);
          expect(pkt[1], 0x11);
          expect(pkt[2], TripperProtocol.maneuverSlightRight);

          // Byte 3-4 distancia
          final encodedDist = (pkt[3] << 8) | pkt[4];
          expect(encodedDist, dist);

          // Byte 5 unidad (1 = metros)
          expect(pkt[5], 0x01);

          // Byte 6 intensidad: para <= 10m debe ser 0x50, para <= 50m debe ser 0x20 o 0x30
          if (dist == 10) {
            expect(pkt[6], 0x50);
          } else if (dist == 50) {
            expect(pkt[6], 0x20); // 45 < 50 <= 70 -> 0x20
          }

          // CRC-16 estricto verificado
          final expectedCrc = TripperProtocol.crc16CcittFalse(
            pkt.sublist(0, 18),
          );
          final actualCrc = (pkt[18] << 8) | pkt[19];
          expect(
            actualCrc,
            expectedCrc,
            reason: 'CRC incorrecto para distancia $dist m',
          );

          packets.add(pkt);
        }

        // Confirmar que todas las tramas generadas son distintas entre sí
        final hexStrings = packets.map(TripperProtocol.toHexString).toSet();
        expect(
          hexStrings.length,
          distances.length,
          reason:
              'Cada distancia debe producir una trama HEX distinta y CRC único',
        );
      },
    );

    test(
      '3. El mecanismo de refresco actualiza activeNavPacket y no retransmite la trama de 500m obsoleta',
      () async {
        final stepStraight = SimulatedManeuverStep(
          stepNumber: 1,
          maneuver: Maneuver(
            instructionText: 'Recto 500m',
            location: Coordinates(4.8150, -75.6940),
            type: ManeuverType.straight,
            distanceMeters: 500.0,
          ),
          initialDistanceMeters: 500,
          isSupportedByTripper: true,
          tripperManeuverCode: TripperProtocol.maneuverStraight,
          compatibilityNote: 'Recto 0x09',
        );

        final sim = NavigationSimulatorService(
          bleService: fakeBle,
          customSteps: [stepStraight],
          transmitToBleDefault: true,
        );

        sim.start();
        await sim.syncCurrentManeuver();

        // Inicialmente en 500m
        expect(
          (fakeBle.activeNavPacket![3] << 8) | fakeBle.activeNavPacket![4],
          500,
        );

        // Avanzar virtualmente 300m (quedan 200m)
        sim.setSpeed(SimulationSpeed.kmh60); // 16.67 m/s
        // 18 segundos a 16.67 m/s = 300 metros
        sim.advanceTime(18.0);

        expect(sim.currentVirtualDistanceMeters, closeTo(200.0, 1.0));

        // La trama activa en BLE debe haberse actualizado a ~200m, NO mantenerse en 500m
        expect(fakeBle.activeNavPacket, isNotNull);
        final currentBleDist =
            (fakeBle.activeNavPacket![3] << 8) | fakeBle.activeNavPacket![4];
        expect(
          currentBleDist,
          closeTo(200, 2),
          reason:
              'activeNavPacket debe reflejar la distancia decreciente dinámica (~200m), no los 500m iniciales',
        );

        sim.dispose();
      },
    );

    test(
      '4. Al entrar a una maniobra no soportada (curva sin opcode validado), se limpia activeNavPacket y se registra [OMITIDO_HARDWARE]',
      () async {
        final step1Supported = SimulatedManeuverStep(
          stepNumber: 1,
          maneuver: Maneuver(
            instructionText: 'Recto 500m',
            location: Coordinates(4.8150, -75.6940),
            type: ManeuverType.straight,
            distanceMeters: 500.0,
          ),
          initialDistanceMeters: 500,
          isSupportedByTripper: true,
          tripperManeuverCode: TripperProtocol.maneuverStraight,
          compatibilityNote: 'Recto 0x09',
        );

        final step2Unsupported = SimulatedManeuverStep(
          stepNumber: 2,
          maneuver: Maneuver(
            instructionText: 'Curva pronunciada en montaña',
            location: Coordinates(4.8200, -75.6900),
            type: ManeuverType.sharpLeft,
            distanceMeters: 300.0,
          ),
          initialDistanceMeters: 300,
          isSupportedByTripper: false,
          tripperManeuverCode: null,
          compatibilityNote:
              'Solo simulación local: curva no validada en display',
        );

        final sim = NavigationSimulatorService(
          bleService: fakeBle,
          customSteps: [step1Supported, step2Unsupported],
          transmitToBleDefault: true,
        );

        sim.start();
        await sim.syncCurrentManeuver();
        expect(fakeBle.activeNavPacket, isNotNull);

        // Avanzar al paso 2 (curva no soportada)
        sim.stepNext();
        await sim.syncCurrentManeuver();

        // Debe emitir la trama de resguardo 0x1C (re-routing) para mantener alimentado
        // el watchdog de 5s del Tripper Pod sin mostrar una flecha de giro falsa
        expect(fakeBle.activeNavPacket, isNotNull);
        expect(fakeBle.activeNavPacket![0], 0x10);
        expect(fakeBle.activeNavPacket![1], 0x11);
        expect(fakeBle.activeNavPacket![2], TripperProtocol.maneuverReRouting);
        expect(
          sim.lastTransmissionResult,
          contains('Pantalla segura 0x1C emitida'),
        );

        // Verificar trazabilidad
        expect(sim.lastTraceEvent, isNotNull);
        expect(sim.lastTraceEvent!.action, SimulationTraceAction.transmitted);
        expect(
          sim.lastTraceEvent!.reason,
          contains('PANTALLA_TRANSICION_SEGURA'),
        );

        sim.dispose();
      },
    );

    test(
      '5. No envía trama de recta (0x09) como sustituto de una curva o giro',
      () {
        final sim = NavigationSimulatorService(
          bleService: fakeBle,
          transmitToBleDefault: true,
        );

        // El paso 6 del escenario determinista es una aproximación a giro a la izquierda
        sim.jumpToStep(5); // Paso 6 (índice 5)
        expect(sim.currentStep.maneuver.type, ManeuverType.left);

        // No debe ser tratada como recta 0x09, sino como giro a la izquierda 0x14 documentado
        expect(
          sim.currentStep.tripperManeuverCode,
          isNot(TripperProtocol.maneuverStraight),
        );
        expect(
          sim.currentStep.tripperManeuverCode,
          TripperProtocol.maneuverTurnLeft,
        );
        expect(sim.currentStep.isSupportedByTripper, isTrue);

        sim.dispose();
      },
    );

    test(
      '6. Trazabilidad completa por cada actualización: almacena campos de diagnóstico requeridos',
      () async {
        final step = SimulatedManeuverStep(
          stepNumber: 1,
          maneuver: Maneuver(
            instructionText: 'Recto hacia Viaducto',
            location: Coordinates(4.8142, -75.6946),
            type: ManeuverType.straight,
            distanceMeters: 300.0,
          ),
          initialDistanceMeters: 300,
          isSupportedByTripper: true,
          tripperManeuverCode: TripperProtocol.maneuverStraight,
          compatibilityNote: 'Código validado 0x09',
        );

        final sim = NavigationSimulatorService(
          bleService: fakeBle,
          customSteps: [step],
          transmitToBleDefault: true,
        );

        sim.start();
        await sim.syncCurrentManeuver();

        expect(sim.traceHistory, isNotEmpty);
        final event = sim.lastTraceEvent!;

        expect(event.timestamp, isNotNull);
        expect(event.stepNumber, 1);
        expect(event.maneuverType, 'straight');
        expect(event.distanceToManeuverMeters, 300);
        expect(event.generatedPacketHex, contains('10 11 09'));
        expect(event.action, SimulationTraceAction.transmitted);
        expect(event.reason, isNotEmpty);

        // Avanzar y verificar nuevo evento en la traza
        sim.advanceTime(2.0);
        expect(sim.traceHistory.length, greaterThan(1));

        sim.dispose();
      },
    );

    test(
      '7. Pausa, reanudación y cambio de velocidad mantienen consistencia estricta de posición y metraje',
      () {
        final step = SimulatedManeuverStep(
          stepNumber: 1,
          maneuver: Maneuver(
            instructionText: 'Recto 500m',
            location: Coordinates(4.8142, -75.6946),
            type: ManeuverType.straight,
            distanceMeters: 500.0,
          ),
          initialDistanceMeters: 500,
          isSupportedByTripper: true,
          tripperManeuverCode: TripperProtocol.maneuverStraight,
          compatibilityNote: 'Recto 0x09',
        );

        final sim = NavigationSimulatorService(
          bleService: fakeBle,
          customSteps: [step],
          transmitToBleDefault: true,
        );

        sim.start();
        sim.setSpeed(SimulationSpeed.kmh30); // 8.33 m/s
        sim.advanceTime(6.0); // Avanzar 50m
        expect(sim.currentVirtualDistanceMeters, closeTo(450.0, 0.5));

        // Pausar
        sim.pause();
        final frozenDist = sim.currentVirtualDistanceMeters;
        final frozenTraveled = sim.traveledDistanceMeters;

        // El tiempo no debe avanzar mientras está pausado
        sim.advanceTime(10.0);
        expect(sim.currentVirtualDistanceMeters, frozenDist);
        expect(sim.traveledDistanceMeters, frozenTraveled);

        // Cambiar velocidad mientras está pausado no debe alterar posición ni distancia
        sim.setSpeed(SimulationSpeed.kmh60);
        expect(sim.currentVirtualDistanceMeters, frozenDist);
        expect(sim.traveledDistanceMeters, frozenTraveled);

        // Reanudar
        sim.resume();
        sim.advanceTime(3.0); // A 60 km/h (16.67 m/s) * 3s = 50m
        expect(
          sim.currentVirtualDistanceMeters,
          closeTo(frozenDist - 50.0, 0.5),
        );

        sim.dispose();
      },
    );

    test(
      '8. Semáforo reactivo con histéresis anti-parpadeo: evaluación basada en distancia dinámica',
      () {
        var light = ProximityTrafficLight.evaluate(distanceMeters: 250.0);
        expect(light, ProximityTrafficLight.green);

        // Al aproximarse a 200m
        light = ProximityTrafficLight.evaluate(
          distanceMeters: 200.0,
          previousState: light,
        );
        expect(light, ProximityTrafficLight.yellow);

        // Al descender a 50m
        light = ProximityTrafficLight.evaluate(
          distanceMeters: 50.0,
          previousState: light,
        );
        expect(light, ProximityTrafficLight.red);

        // Al subir a 52m (dentro del margen de histéresis de 5m <= 55m), se mantiene ROJO
        light = ProximityTrafficLight.evaluate(
          distanceMeters: 52.0,
          previousState: light,
        );
        expect(
          light,
          ProximityTrafficLight.red,
          reason: 'Debe permanecer en ROJO dentro de la banda de histéresis',
        );

        // Al superar 55.1m, pasa a AMARILLO
        light = ProximityTrafficLight.evaluate(
          distanceMeters: 56.0,
          previousState: light,
        );
        expect(light, ProximityTrafficLight.yellow);

        // Al subir a 203m (dentro del margen de histéresis de 5m <= 205m), se mantiene AMARILLO
        light = ProximityTrafficLight.evaluate(
          distanceMeters: 203.0,
          previousState: light,
        );
        expect(light, ProximityTrafficLight.yellow);

        // Al superar 205.1m, pasa a VERDE
        light = ProximityTrafficLight.evaluate(
          distanceMeters: 206.0,
          previousState: light,
        );
        expect(light, ProximityTrafficLight.green);
      },
    );
  });
}
