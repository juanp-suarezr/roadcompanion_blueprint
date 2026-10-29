import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_companion/domain/entities/coordinates.dart';
import 'package:road_companion/domain/entities/maneuver_type.dart';
import 'package:road_companion/features/bridge/domain/entities/bridge_instruction_status.dart';
import 'package:road_companion/features/bridge/domain/entities/bridge_source_type.dart';
import 'package:road_companion/features/bridge/infrastructure/services/bridge_native_channel.dart';
import 'package:road_companion/features/bridge/infrastructure/services/bridge_navigation_source.dart';
import 'package:road_companion/features/navigation/domain/entities/road_curvature.dart';
import 'package:road_companion/features/navigation/domain/entities/tripper_connection_state.dart';
import 'package:road_companion/features/navigation/domain/entities/tripper_device.dart';
import 'package:road_companion/features/navigation/domain/entities/tripper_gatt_info.dart';
import 'package:road_companion/features/navigation/domain/entities/tripper_maneuver_payload.dart';
import 'package:road_companion/features/navigation/domain/services/navigation_diagnostic_logger.dart';
import 'package:road_companion/features/navigation/domain/services/navigation_source.dart';
import 'package:road_companion/features/navigation/domain/services/tripper_ble_service.dart';
import 'package:road_companion/features/navigation/infrastructure/services/navigation_instruction_bridge.dart';

class _MockTripperBleService implements TripperBleService {
  TripperConnectionState state = TripperConnectionState.authenticated;
  final List<List<int>> sentRawPackets = [];
  int stopNavigationCount = 0;
  int clearActiveNavPacketCount = 0;

  @override
  TripperConnectionState get currentState => state;

  @override
  Future<bool> sendRawPacket(List<int> bytes) async {
    sentRawPackets.add(List.from(bytes));
    return true;
  }

  @override
  Future<bool> stopNavigation() async {
    stopNavigationCount++;
    return true;
  }

  @override
  void clearActiveNavPacket({String? reason}) {
    clearActiveNavPacketCount++;
  }

  @override
  Future<void> disconnect() async {}
  @override
  bool get isNavScreenActive => sentRawPackets.isNotEmpty && stopNavigationCount == 0;
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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Fuentes de Navegación Independientes y Máquina de Estados (Etapas 5, 6 y 7)', () {
    late _MockTripperBleService mockBle;

    setUp(() {
      mockBle = _MockTripperBleService();
      NavigationDiagnosticLogger.clearPipelineEntries();
    });

    test('1. WazeNavigationSource y GoogleMapsNavigationSource son adaptadores independientes con capacidades declaradas', () {
      const wazeSource = WazeNavigationSource();
      const gmapsSource = GoogleMapsNavigationSource();
      const internalSource = InternalNavigationSource();

      expect(wazeSource.sourceType, equals(SelectedNavigationSourceType.waze));
      expect(wazeSource.capabilities.providesManeuvers, isTrue);
      expect(wazeSource.capabilities.providesDistances, isTrue);
      expect(wazeSource.capabilities.providesRoadGeometry, isFalse);
      expect(wazeSource.capabilities.supportsRealCurveDetection, isFalse);
      expect(wazeSource.capabilities.requiresNotificationAccess, isTrue);

      expect(gmapsSource.sourceType, equals(SelectedNavigationSourceType.googleMaps));
      expect(gmapsSource.capabilities.providesRoadGeometry, isFalse);
      expect(gmapsSource.capabilities.requiresNotificationAccess, isTrue);

      expect(internalSource.sourceType, equals(SelectedNavigationSourceType.internal));
      expect(internalSource.capabilities.providesRoadGeometry, isTrue);
      expect(internalSource.capabilities.supportsRealCurveDetection, isTrue);
      expect(internalSource.capabilities.requiresNotificationAccess, isFalse);

      // Parseo independiente de Waze con distancia en título y acción en texto
      final wazeInst = wazeSource.parseNotification(
        title: '250 m',
        text: 'Dobla a la derecha hacia Av. Circunvalar',
        timestamp: DateTime(2026, 10, 29, 12, 0),
      );
      expect(wazeInst.source, equals(BridgeSourceType.waze));
      expect(wazeInst.maneuverType, equals(ManeuverType.right));
      expect(wazeInst.distanceMeters, equals(250));
      expect(wazeInst.isCompatibleWithTripper, isTrue);

      // Parseo independiente de Google Maps
      final gmapsInst = gmapsSource.parseNotification(
        title: 'En 400 m, usa el carril izquierdo',
        text: 'Hacia Autopista del Café',
        timestamp: DateTime(2026, 10, 29, 12, 1),
      );
      expect(gmapsInst.source, equals(BridgeSourceType.googleMaps));
      expect(gmapsInst.maneuverType, equals(ManeuverType.slightLeft));
      expect(gmapsInst.distanceMeters, equals(400));
    });

    test('2. Navegación externa + curvas: no inventa curvas cuando la fuente no expone geometría', () {
      const wazeSource = WazeNavigationSource();
      final p0 = Coordinates(4.8143, -75.6946);
      final p1 = p0.project(0.0, 50.0);
      final p2 = p1.project(60.0, 50.0);

      // Aunque se pase una polilínea cualquiera, WazeNavigationSource declara explícitamente insufficientData
      final curveInfo = wazeSource.evaluateCurvature(
        geometry: [p0, p1, p2],
        traveledDistanceMeters: 10.0,
      );
      expect(curveInfo.curveClass, equals(CurveClass.insufficientData));
      expect(curveInfo.geometrySource, equals(GeometrySource.none));
      expect(curveInfo.hasActiveCurve, isFalse);
    });

    test('3. BridgeNavigationSource filtra por fuente seleccionada y rechaza duplicados y eventos fuera de orden', () {
      final source = BridgeNavigationSource(
        allowedSource: BridgeSourceType.waze,
      );
      final t0 = DateTime(2026, 10, 29, 12, 0, 10);

      // Evento de Google Maps debe ser ignorado porque la fuente seleccionada es Waze
      source.processNotificationEvent(
        BridgeNotificationEvent(
          source: BridgeSourceType.googleMaps,
          title: 'En 200 m, gira a la izquierda',
          text: 'Calle 14',
          timestamp: t0,
        ),
      );
      expect(source.lastInstruction, isNull);

      // Evento válido de Waze es procesado
      source.processNotificationEvent(
        BridgeNotificationEvent(
          source: BridgeSourceType.waze,
          title: '300 m',
          text: 'Gira a la derecha en Carrera 7',
          timestamp: t0,
        ),
      );
      expect(source.lastInstruction, isNotNull);
      expect(source.lastInstruction!.source, equals(BridgeSourceType.waze));
      expect(source.lastInstruction!.distanceMeters, equals(300));

      // Evento fuera de orden (10 segundos más antiguo) es rechazado y no sobrescribe el de 300 m
      source.processNotificationEvent(
        BridgeNotificationEvent(
          source: BridgeSourceType.waze,
          title: '800 m',
          text: 'Gira a la izquierda en Calle 10',
          timestamp: t0.subtract(const Duration(seconds: 10)),
        ),
      );
      expect(source.lastInstruction!.distanceMeters, equals(300));
      expect(source.lastInstruction!.maneuverType, equals(ManeuverType.right));

      source.dispose();
    });

    test('4. Eliminar notificación (fin de ruta) detiene la navegación activa en BLE sin repetir la última maniobra', () async {
      final bridgeSource = BridgeNavigationSource(
        allowedSource: BridgeSourceType.waze,
      );
      final bridge = NavigationInstructionBridge(
        navigationSource: bridgeSource,
        bleService: mockBle,
      );
      bridge.start();

      final t0 = DateTime(2026, 10, 29, 12, 5, 0);
      bridgeSource.processNotificationEvent(
        BridgeNotificationEvent(
          source: BridgeSourceType.waze,
          title: '150 m',
          text: 'Gira a la derecha en Calle 72',
          timestamp: t0,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(mockBle.sentRawPackets.length, equals(1));
      expect(mockBle.stopNavigationCount, equals(0));

      // Ahora Waze elimina la notificación al finalizar la ruta
      bridgeSource.processNotificationEvent(
        BridgeNotificationEvent(
          source: BridgeSourceType.waze,
          timestamp: t0.add(const Duration(seconds: 5)),
          isRemoved: true,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(bridgeSource.lastInstruction!.status, equals(BridgeInstructionStatus.stale));
      expect(mockBle.clearActiveNavPacketCount, greaterThanOrEqualTo(1));
      expect(mockBle.stopNavigationCount, equals(1));

      bridge.dispose();
      bridgeSource.dispose();
    });

    test('5. Máquina de estados cumple las 6 reglas obligatorias (selección, detección, cambio de fuente y desconexión)', () async {
      final sm = CompanionNavigationStateMachine(
        initialSource: const WazeNavigationSource(),
        bleService: mockBle,
        hasNotificationPermission: false,
      );

      // Sin permiso -> awaitingPermission
      expect(sm.state, equals(CompanionNavigationState.awaitingPermission));

      // Al conceder permiso -> sourceSelected (Regla 1: seleccionar fuente != ruta activa)
      sm.updateNotificationPermission(true);
      expect(sm.state, equals(CompanionNavigationState.sourceSelected));

      // Recibir una notificación no navegable (ej. alerta de tráfico) -> navigationDetected (Regla 2)
      const waze = WazeNavigationSource();
      final trafficAlert = waze.parseNotification(
        title: 'Waze',
        text: 'Tráfico denso más adelante',
      );
      await sm.onExternalInstruction(trafficAlert);
      expect(sm.state, equals(CompanionNavigationState.navigationDetected));

      // Recibir maniobra válida -> navigationActive
      final validTurn = waze.parseNotification(
        title: '200 m',
        text: 'Gira a la izquierda en Av. Santander',
      );
      await sm.onExternalInstruction(validTurn);
      expect(sm.state, equals(CompanionNavigationState.navigationActive));

      // Regla 6: Cambiar fuente a Google Maps invalida datos de Waze y detiene BLE
      await sm.selectSource(
        SelectedNavigationSourceType.googleMaps,
        notificationPermissionGranted: true,
      );
      expect(sm.selectedSourceType, equals(SelectedNavigationSourceType.googleMaps));
      expect(sm.activeExternalInstruction, isNull);
      expect(sm.state, equals(CompanionNavigationState.sourceSelected));
      expect(mockBle.clearActiveNavPacketCount, greaterThanOrEqualTo(1));

      // Regla 5: Desconexión BLE por watchdog refleja bleDisconnected sin bucle agresivo
      sm.onBleConnectionStateChanged(TripperConnectionState.disconnected);
      expect(sm.state, equals(CompanionNavigationState.bleDisconnected));
    });

    test('6. Observabilidad en 5 niveles registra L1, L2, L3, L4 y L5 de forma estructurada', () async {
      final bridgeSource = BridgeNavigationSource(
        allowedSource: BridgeSourceType.googleMaps,
      );
      final bridge = NavigationInstructionBridge(
        navigationSource: bridgeSource,
        bleService: mockBle,
      );
      bridge.start();

      bridgeSource.processNotificationEvent(
        BridgeNotificationEvent(
          source: BridgeSourceType.googleMaps,
          title: 'En 500 m, continúa recto',
          text: 'Por Carrera 7',
          timestamp: DateTime(2026, 10, 29, 12, 10),
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        NavigationDiagnosticLogger.getPipelineEntries(
          filterStage: DiagnosticPipelineStage.l1AndroidEvent,
        ),
        isNotEmpty,
      );
      expect(
        NavigationDiagnosticLogger.getPipelineEntries(
          filterStage: DiagnosticPipelineStage.l2ParsedEvent,
        ),
        isNotEmpty,
      );
      expect(
        NavigationDiagnosticLogger.getPipelineEntries(
          filterStage: DiagnosticPipelineStage.l3InternalModel,
        ),
        isNotEmpty,
      );
      expect(
        NavigationDiagnosticLogger.getPipelineEntries(
          filterStage: DiagnosticPipelineStage.l4BleTx,
        ),
        isNotEmpty,
      );
      expect(
        NavigationDiagnosticLogger.getPipelineEntries(
          filterStage: DiagnosticPipelineStage.l5PhysicalObservation,
        ),
        isNotEmpty,
      );

      bridge.dispose();
      bridgeSource.dispose();
    });
  });
}
