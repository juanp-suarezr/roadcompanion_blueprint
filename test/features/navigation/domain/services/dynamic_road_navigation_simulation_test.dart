import 'dart:async';
import 'package:flutter_test/flutter_test.dart';

import 'package:road_companion/domain/entities/coordinates.dart';
import 'package:road_companion/domain/entities/maneuver.dart';
import 'package:road_companion/domain/entities/maneuver_type.dart';
import 'package:road_companion/features/navigation/domain/entities/calculated_route.dart';
import 'package:road_companion/features/navigation/domain/entities/pereira_santa_rosa_route.dart';
import 'package:road_companion/features/navigation/domain/entities/road_curvature.dart';
import 'package:road_companion/features/navigation/domain/entities/simulated_maneuver_step.dart';
import 'package:road_companion/features/navigation/domain/entities/tripper_connection_state.dart';
import 'package:road_companion/features/navigation/domain/entities/tripper_device.dart';
import 'package:road_companion/features/navigation/domain/entities/tripper_gatt_info.dart';
import 'package:road_companion/features/navigation/domain/entities/tripper_maneuver_payload.dart';
import 'package:road_companion/features/navigation/domain/services/navigation_simulator_service.dart';
import 'package:road_companion/features/navigation/domain/services/routing_service.dart';
import 'package:road_companion/features/navigation/domain/services/tripper_ble_service.dart';
import 'package:road_companion/features/navigation/domain/services/tripper_protocol.dart';

class _FakeTripperBleService implements TripperBleService {
  TripperConnectionState _state = TripperConnectionState.authenticated;
  final List<List<int>> sentPackets = [];
  bool shouldFailSend = false;
  int stopNavigationCalls = 0;
  int clearActiveNavPacketCalls = 0;
  int disconnectCalls = 0;

  void setMockState(TripperConnectionState state) => _state = state;

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
  Stream<List<TripperGattService>> get discoveredGattServicesStream => const Stream.empty();
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

class _FailingRoutingService implements RoutingService {
  @override
  Future<CalculatedRoute> calculateRoute({
    required Coordinates origin,
    required Coordinates destination,
  }) async {
    throw Exception('Servidor OSRM no alcanzable / Sin conexión');
  }

  @override
  Future<List<CalculatedRoute>> calculateRoutesWithAlternatives({
    required Coordinates origin,
    required Coordinates destination,
  }) async {
    throw Exception('Servidor OSRM no alcanzable / Sin conexión');
  }

  @override
  Future<CalculatedRoute> calculateMultistopRoute({
    required Coordinates origin,
    required List<Coordinates> waypoints,
    required Coordinates destination,
  }) async {
    throw Exception('Servidor OSRM no alcanzable');
  }
}

void main() {
  group('Evolución del Simulador — Navegación Dinámica por Carretera y Curvas', () {
    late _FakeTripperBleService fakeBle;

    setUp(() {
      fakeBle = _FakeTripperBleService();
    });

    // 1. Avance de posición virtual sobre una polilínea
    test('1. Avance de posición virtual sobre la polilínea vial', () {
      final sim = NavigationSimulatorService(bleService: fakeBle);
      final initialPos = sim.currentVirtualPosition;
      expect(sim.geometry, isNotEmpty);
      expect(sim.traveledDistanceMeters, 0.0);

      sim.start();
      sim.advanceTime(20.0); // Avanza 20 s a 30 km/h (8.33 m/s) = ~166 m

      expect(sim.traveledDistanceMeters, greaterThan(0.0));
      expect(sim.currentVirtualPosition, isNot(equals(initialPos)));
      sim.dispose();
    });

    // 2. Interpolación entre puntos de la geometría
    test('2. Interpolación matemática continua entre vértices de calzada', () {
      final sim = NavigationSimulatorService(bleService: fakeBle);
      sim.start();

      final p0 = sim.currentVirtualPosition;
      sim.advanceTime(5.0);
      final p1 = sim.currentVirtualPosition;
      sim.advanceTime(5.0);
      final p2 = sim.currentVirtualPosition;

      // La distancia entre puntos interpolados debe ser suave y continua
      expect(p0.distanceTo(p1), greaterThan(0.0));
      expect(p1.distanceTo(p2), greaterThan(0.0));
      expect(p0.distanceTo(p2), greaterThan(p0.distanceTo(p1)));
      sim.dispose();
    });

    // 3. Distancia restante decreciente durante el avance
    test('3. Distancia restante decrece continuamente tick a tick', () {
      final sim = NavigationSimulatorService(bleService: fakeBle);
      sim.start();

      final dist0 = sim.currentVirtualDistanceMeters;
      sim.advanceTime(2.0);
      final dist1 = sim.currentVirtualDistanceMeters;
      sim.advanceTime(2.0);
      final dist2 = sim.currentVirtualDistanceMeters;

      expect(dist1, lessThan(dist0));
      expect(dist2, lessThan(dist1));
      sim.dispose();
    });

    // 4. Detección del siguiente punto de maniobra
    test('4. Detección y transición a la siguiente maniobra sin distancias negativas', () {
      final sim = NavigationSimulatorService(bleService: fakeBle);
      sim.start();
      expect(sim.currentStepIndex, 0);

      // Avanzamos hasta agotar la distancia del paso inicial (600 m)
      // A 60 km/h = 16.66 m/s, 600m toma ~36s
      sim.setSpeed(SimulationSpeed.kmh60);
      sim.advanceTime(40.0);

      expect(sim.currentStepIndex, greaterThan(0));
      expect(sim.currentVirtualDistanceMeters, greaterThanOrEqualTo(0.0));
      sim.dispose();
    });

    // 5. Cambio verde -> amarillo -> rojo según los umbrales
    test('5. Cambio reactivo de semáforo Verde -> Amarillo -> Rojo según umbrales', () {
      // Direct evaluate test with exact thresholds
      expect(
        ProximityTrafficLight.evaluate(distanceMeters: 350.0),
        equals(ProximityTrafficLight.green),
      );
      expect(
        ProximityTrafficLight.evaluate(distanceMeters: 180.0),
        equals(ProximityTrafficLight.yellow),
      );
      expect(
        ProximityTrafficLight.evaluate(distanceMeters: 45.0),
        equals(ProximityTrafficLight.red),
      );

      // On simulator with quick approach test
      final sim = NavigationSimulatorService(bleService: fakeBle);
      sim.start();
      sim.approachQuickCurveTest(); // Fija a 300 m

      expect(sim.currentVirtualDistanceMeters, equals(300.0));
      expect(sim.trafficLight, equals(ProximityTrafficLight.green));

      // Avanza 150m -> queda 150m (Amarillo: <= 200m)
      sim.advanceTime(150.0 / sim.speed.metersPerSecond);
      expect(sim.currentVirtualDistanceMeters, closeTo(150.0, 1.0));
      expect(sim.trafficLight, equals(ProximityTrafficLight.yellow));

      // Avanza 110m más -> queda ~40m (Rojo: <= 50m)
      sim.advanceTime(110.0 / sim.speed.metersPerSecond);
      expect(sim.currentVirtualDistanceMeters, closeTo(40.0, 1.0));
      expect(sim.trafficLight, equals(ProximityTrafficLight.red));

      sim.dispose();
    });

    // 6. Cambio de color al avanzar a la siguiente maniobra
    test('6. Cambio de color a Verde al saltar a la siguiente maniobra lejana', () {
      final sim = NavigationSimulatorService(bleService: fakeBle);
      sim.start();
      sim.approachQuickCurveTest(); // 300m
      sim.advanceTime(270.0 / sim.speed.metersPerSecond); // queda 30m -> Rojo
      expect(sim.trafficLight, equals(ProximityTrafficLight.red));

      // Al avanzar manualmente a la siguiente maniobra (que está a 500m)
      sim.stepNext();
      expect(sim.currentVirtualDistanceMeters, greaterThan(200.0));
      expect(sim.trafficLight, equals(ProximityTrafficLight.green));
      sim.dispose();
    });

    // 7. Clasificación de curvas a izquierda y derecha
    test('7. Clasificación geométrica de curvas a izquierda y derecha', () {
      final origin = Coordinates(4.8143, -75.6946);
      final straightPoint = origin.project(0.0, 100.0);
      final rightCurvePoint = straightPoint.project(45.0, 100.0); // +45° derecha
      final leftCurvePoint = straightPoint.project(315.0, 100.0); // -45° izquierda

      // Geometría con giro a la derecha
      final geomRight = [origin, straightPoint, rightCurvePoint];
      final cumRight = [0.0, 100.0, 200.0];
      final infoRight = RoadCurvatureEstimator.estimate(
        geometry: geomRight,
        traveledDistanceMeters: 50.0,
        cumulativeDistances: cumRight,
      );
      expect(infoRight.type.isRight, isTrue);

      // Geometría con giro a la izquierda
      final geomLeft = [origin, straightPoint, leftCurvePoint];
      final cumLeft = [0.0, 100.0, 200.0];
      final infoLeft = RoadCurvatureEstimator.estimate(
        geometry: geomLeft,
        traveledDistanceMeters: 50.0,
        cumulativeDistances: cumLeft,
      );
      expect(infoLeft.type.isLeft, isTrue);
    });

    // 8. Diferenciación entre curvas suaves y pronunciadas
    test('8. Diferenciación de curvas suaves (10°-35°) y pronunciadas (> 35°)', () {
      final p0 = Coordinates(4.8143, -75.6946);
      final p1 = p0.project(0.0, 50.0);

      // Curva suave a la derecha (20°)
      final pGentleRight = p1.project(20.0, 50.0);
      final infoGentle = RoadCurvatureEstimator.estimate(
        geometry: [p0, p1, pGentleRight],
        traveledDistanceMeters: 25.0,
        cumulativeDistances: [0.0, 50.0, 100.0],
      );
      expect(infoGentle.type, equals(RoadCurvatureType.gentleRight));

      // Curva pronunciada a la derecha (60°)
      final pSharpRight = p1.project(60.0, 50.0);
      final infoSharp = RoadCurvatureEstimator.estimate(
        geometry: [p0, p1, pSharpRight],
        traveledDistanceMeters: 25.0,
        cumulativeDistances: [0.0, 50.0, 100.0],
      );
      expect(infoSharp.type, equals(RoadCurvatureType.sharpRight));

      // Tramo recto (< 10°)
      final pStraight = p1.project(3.0, 50.0);
      final infoStraight = RoadCurvatureEstimator.estimate(
        geometry: [p0, p1, pStraight],
        traveledDistanceMeters: 25.0,
        cumulativeDistances: [0.0, 50.0, 100.0],
      );
      expect(infoStraight.type, equals(RoadCurvatureType.straight));
    });

    // 9. Pausa y reanudación sin alterar el progreso
    test('9. Pausa y reanudación congelan y conservan métricas', () {
      final sim = NavigationSimulatorService(bleService: fakeBle);
      sim.start();
      sim.advanceTime(10.0);

      final traveled = sim.traveledDistanceMeters;
      final dist = sim.currentVirtualDistanceMeters;
      final light = sim.trafficLight;

      sim.pause();
      sim.advanceTime(10.0); // No debe avanzar

      expect(sim.traveledDistanceMeters, equals(traveled));
      expect(sim.currentVirtualDistanceMeters, equals(dist));
      expect(sim.trafficLight, equals(light));

      sim.resume();
      sim.advanceTime(5.0);
      expect(sim.traveledDistanceMeters, greaterThan(traveled));
      sim.dispose();
    });

    // 10. Cambio de velocidad sin saltos de posición
    test('10. Cambio de velocidad modifica tasa de avance sin alterar posición instantánea', () {
      final sim = NavigationSimulatorService(bleService: fakeBle);
      sim.start();
      sim.advanceTime(5.0);

      final posBefore = sim.currentVirtualPosition;
      final distBefore = sim.currentVirtualDistanceMeters;

      sim.setSpeed(SimulationSpeed.kmh60);
      expect(sim.currentVirtualPosition, equals(posBefore));
      expect(sim.currentVirtualDistanceMeters, equals(distBefore));

      sim.setSpeed(SimulationSpeed.kmh10);
      expect(sim.currentVirtualPosition, equals(posBefore));
      expect(sim.currentVirtualDistanceMeters, equals(distBefore));
      sim.dispose();
    });

    // 11. Reinicio correcto
    test('11. Reinicio restablece posición, semáforo verde y métricas a cero', () {
      final sim = NavigationSimulatorService(bleService: fakeBle);
      sim.start();
      sim.advanceTime(30.0);
      expect(sim.traveledDistanceMeters, greaterThan(0.0));

      sim.reset();
      expect(sim.status, equals(SimulationStatus.stopped));
      expect(sim.traveledDistanceMeters, equals(0.0));
      expect(sim.trafficLight, equals(ProximityTrafficLight.green));
      expect(sim.currentStepIndex, equals(0));
      sim.dispose();
    });

    // 12. Fin de ruta
    test('12. Finalización automática al completar la distancia de la ruta', () {
      final sim = NavigationSimulatorService(bleService: fakeBle);
      sim.start();

      // Avanzamos tiempo suficiente para completar todos los pasos
      sim.setSpeed(SimulationSpeed.kmh60);
      while (sim.currentStepIndex < sim.totalSteps - 1) {
        sim.stepNext();
      }
      sim.stepNext(); // Arribo

      expect(sim.status, equals(SimulationStatus.completed));
      expect(sim.currentVirtualDistanceMeters, equals(0.0));
      expect(sim.totalRemainingDistanceMeters, equals(0.0));
      expect(sim.progressPercentage, equals(100.0));
      sim.dispose();
    });

    // 13. Funcionamiento sin GPS real
    test('13. Simulación puramente virtual desacoplada del sensor GPS físico', () {
      final sim = NavigationSimulatorService(bleService: fakeBle);
      sim.start();
      sim.advanceTime(15.0);

      // La posición virtual avanza sin invocar ningún sensor GPS
      expect(sim.currentVirtualPosition.latitude.isFinite, isTrue);
      expect(sim.currentVirtualPosition.longitude.isFinite, isTrue);
      sim.dispose();
    });

    // 14. Comportamiento sin Internet usando ruta determinista Pereira -> Santa Rosa
    test('14. Operación sin Internet con ruta canónica Pereira -> Santa Rosa', () {
      final sim = NavigationSimulatorService(bleService: fakeBle);
      sim.loadPereiraSantaRosaScenario();

      expect(sim.routeName, equals(PereiraSantaRosaRoute.routeName));
      expect(sim.geometry.length, equals(PereiraSantaRosaRoute.geometry.length));
      expect(sim.totalRouteDistanceMeters, closeTo(15527.0, 5000.0));
      sim.start();
      sim.advanceTime(10.0);
      expect(sim.traveledDistanceMeters, greaterThan(0.0));
      sim.dispose();
    });

    // 15. Transmisión BLE solo para maniobras validadas
    test('15. Transmisión BLE únicamente para maniobras validadas con hardware', () async {
      final sim = NavigationSimulatorService(
        bleService: fakeBle,
        transmitToBleDefault: true,
      );
      sim.start();
      fakeBle.sentPackets.clear();

      // Paso 2: Recto (0x09) validado en hardware
      sim.stepNext();
      await sim.syncCurrentManeuver();
      expect(fakeBle.sentPackets, isNotEmpty);
      expect(fakeBle.sentPackets.last[2], equals(TripperProtocol.maneuverStraight));
      sim.dispose();
    });

    // 16. Ausencia de tramas inventadas para curvas no compatibles
    test('16. Curvas sin opcode validado no se envían a ciegas por BLE', () async {
      final unsupportedCurve = SimulatedManeuverStep(
        stepNumber: 1,
        maneuver: Maneuver(
          instructionText: 'Curva peligrosa no documentada',
          location: Coordinates(4.8150, -75.6940),
          type: ManeuverType.sharpLeft,
          distanceMeters: 250.0,
        ),
        initialDistanceMeters: 250,
        isSupportedByTripper: false,
        tripperManeuverCode: null,
        compatibilityNote: 'Opcode no confirmado en display',
      );

      final sim = NavigationSimulatorService(
        bleService: fakeBle,
        customSteps: [unsupportedCurve],
        transmitToBleDefault: true,
      );
      sim.start();
      fakeBle.sentPackets.clear();

      final sent = await sim.syncCurrentManeuver();
      expect(sent, isTrue);
      // No inventa un giro ciego ni una recta (0x09)
      expect(fakeBle.sentPackets, isNotEmpty);
      expect(fakeBle.sentPackets.last[2], equals(TripperProtocol.maneuverReRouting));
      expect(fakeBle.sentPackets.last[2], isNot(equals(TripperProtocol.maneuverStraight)));
      expect(sim.lastTransmissionResult, contains('Pantalla segura 0x1C'));
      sim.dispose();
    });

    // 17. Manejo de errores de ruta y de escritura BLE
    test('17. Manejo recuperable de fallos de red OSRM y fallos de escritura BLE', () async {
      final sim = NavigationSimulatorService(bleService: fakeBle);

      // Simular fallo OSRM
      final okRoute = await sim.loadLiveRouteFromOsrm(routingService: _FailingRoutingService());
      expect(okRoute, isFalse);
      expect(sim.routeLoadError, contains('No se pudo conectar con OSRM'));
      expect(sim.geometry, isNotEmpty); // Conserva geometría local

      // Simular fallo BLE
      fakeBle.shouldFailSend = true;
      sim.setTransmitToBle(true);
      sim.start();
      final okBle = await sim.syncCurrentManeuver();
      expect(okBle, isFalse);
      expect(sim.lastTransmissionResult, contains('Fallo de escritura'));
      sim.dispose();
    });

    // 18. Histéresis del semáforo para prevenir oscilaciones
    test('18. Histéresis de 5m en semáforo de proximidad previene parpadeos', () {
      // De amarillo a verde necesita > 205m
      var light = ProximityTrafficLight.yellow;
      light = ProximityTrafficLight.evaluate(
        distanceMeters: 202.0, // menor a 200 + 5
        previousState: light,
      );
      expect(light, equals(ProximityTrafficLight.yellow));

      light = ProximityTrafficLight.evaluate(
        distanceMeters: 206.0, // mayor a 205
        previousState: light,
      );
      expect(light, equals(ProximityTrafficLight.green));

      // De rojo a amarillo necesita > 55m
      light = ProximityTrafficLight.red;
      light = ProximityTrafficLight.evaluate(
        distanceMeters: 52.0, // menor a 50 + 5
        previousState: light,
      );
      expect(light, equals(ProximityTrafficLight.red));

      light = ProximityTrafficLight.evaluate(
        distanceMeters: 56.0, // mayor a 55
        previousState: light,
      );
      expect(light, equals(ProximityTrafficLight.yellow));
    });
  });
}
