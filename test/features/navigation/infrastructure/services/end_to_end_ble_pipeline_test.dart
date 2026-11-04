import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

import 'package:road_companion/domain/entities/coordinates.dart';
import 'package:road_companion/domain/entities/maneuver.dart';
import 'package:road_companion/domain/entities/maneuver_type.dart';
import 'package:road_companion/domain/entities/route_plan.dart';
import 'package:road_companion/features/bridge/domain/entities/bridge_instruction_status.dart';
import 'package:road_companion/features/bridge/domain/entities/bridge_source_type.dart';
import 'package:road_companion/features/bridge/domain/services/navigation_instruction_parser.dart';
import 'package:road_companion/features/navigation/domain/entities/calculated_route.dart';
import 'package:road_companion/features/navigation/domain/entities/destination.dart';
import 'package:road_companion/features/navigation/domain/entities/gps_position.dart';
import 'package:road_companion/features/navigation/domain/entities/tripper_connection_state.dart';
import 'package:road_companion/features/navigation/domain/entities/tripper_maneuver_payload.dart';
import 'package:road_companion/features/navigation/domain/services/auto_navigation_source_arbiter.dart';
import 'package:road_companion/features/navigation/domain/services/location_service.dart';
import 'package:road_companion/features/navigation/domain/services/navigation_source.dart';
import 'package:road_companion/features/navigation/domain/services/tripper_ble_service.dart';
import 'package:road_companion/features/navigation/domain/services/tripper_navigation_adapter.dart';
import 'package:road_companion/features/navigation/domain/services/tripper_protocol.dart';
import 'package:road_companion/features/navigation/domain/services/voice_navigation_service.dart';
import 'package:road_companion/features/navigation/infrastructure/services/internal_navigation_session_manager.dart';

/// Elemento de log estructurado que rastrea el paso exacto en el transporte BLE simulado.
enum BlePipelineStep {
  instructionGenerated,
  instructionAccepted,
  packetBuilt,
  packetQueued,
  gattWriteStarted,
  gattWriteConfirmed,
  deviceResponseReceived,
}

class BlePipelineLog {
  final BlePipelineStep step;
  final String source;
  final String detail;
  final Uint8List? packetBytes;
  final DateTime timestamp;

  const BlePipelineLog({
    required this.step,
    required this.source,
    required this.detail,
    this.packetBytes,
    required this.timestamp,
  });

  String get stepName {
    switch (step) {
      case BlePipelineStep.instructionGenerated:
        return 'instruction_generated';
      case BlePipelineStep.instructionAccepted:
        return 'instruction_accepted';
      case BlePipelineStep.packetBuilt:
        return 'packet_built';
      case BlePipelineStep.packetQueued:
        return 'packet_queued';
      case BlePipelineStep.gattWriteStarted:
        return 'gatt_write_started';
      case BlePipelineStep.gattWriteConfirmed:
        return 'gatt_write_confirmed';
      case BlePipelineStep.deviceResponseReceived:
        return 'device_response_received';
    }
  }

  @override
  String toString() =>
      '[$stepName] ($source) $detail ${packetBytes != null ? "| Hex: ${packetBytes!.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}" : ""}';
}

/// Transporte BLE simulado con cola FIFO asíncrona, temporización GATT y registro estricto.
class SimulatedTripperBleTransport implements TripperBleService {
  final List<BlePipelineLog> logs = [];
  final List<Uint8List> transmittedPackets = [];
  final StreamController<TripperConnectionState> _stateCtrl =
      StreamController<TripperConnectionState>.broadcast();

  TripperConnectionState _state = TripperConnectionState.connected;
  bool _isWriting = false;
  final List<_QueuedPacket> _queue = [];
  bool simulateDeviceResponse = false;

  void logEvent({
    required BlePipelineStep step,
    required String source,
    required String detail,
    Uint8List? packetBytes,
  }) {
    logs.add(
      BlePipelineLog(
        step: step,
        source: source,
        detail: detail,
        packetBytes: packetBytes,
        timestamp: DateTime.now(),
      ),
    );
  }

  void setState(TripperConnectionState state) {
    _state = state;
    _stateCtrl.add(state);
  }

  @override
  TripperConnectionState get currentState => _state;

  @override
  Stream<TripperConnectionState> get stateStream => _stateCtrl.stream;

  @override
  Future<bool> sendManeuver(TripperManeuverPayload maneuver) async {
    if (!maneuver.isSupported) {
      return false;
    }
    final packet = Uint8List.fromList(maneuver.toProtocolPacket());
    logEvent(
      step: BlePipelineStep.packetBuilt,
      source: 'TripperProtocol',
      detail:
          'Construido paquete ${packet.length} bytes para ${maneuver.maneuverType.name} (${maneuver.distanceMeters}m)',
      packetBytes: packet,
    );

    return _enqueue(packet, description: maneuver.toDiagnosticString());
  }

  @override
  Future<bool> sendRawPacket(List<int> bytes) async {
    final packet = Uint8List.fromList(bytes);
    logEvent(
      step: BlePipelineStep.packetBuilt,
      source: 'TripperProtocol',
      detail: 'Paquete RAW ${packet.length} bytes',
      packetBytes: packet,
    );
    return _enqueue(packet, description: 'RAW packet');
  }

  Future<bool> _enqueue(Uint8List packet, {required String description}) {
    final completer = Completer<bool>();
    _queue.add(_QueuedPacket(packet, description, completer));

    logEvent(
      step: BlePipelineStep.packetQueued,
      source: 'SimulatedBleQueue',
      detail: 'Encolado: $description (longitud cola: ${_queue.length})',
      packetBytes: packet,
    );

    _processQueue();
    return completer.future;
  }

  Future<void> _processQueue() async {
    if (_isWriting || _queue.isEmpty) return;
    _isWriting = true;

    while (_queue.isNotEmpty) {
      final item = _queue.removeAt(0);

      logEvent(
        step: BlePipelineStep.gattWriteStarted,
        source: 'SimulatedGattServer',
        detail:
            'Iniciando escritura GATT en característica ${TripperProtocol.characteristicUuid}',
        packetBytes: item.bytes,
      );

      // Simular latencia física de radio Bluetooth LE (10 ms)
      await Future<void>.delayed(const Duration(milliseconds: 10));

      transmittedPackets.add(item.bytes);

      logEvent(
        step: BlePipelineStep.gattWriteConfirmed,
        source: 'SimulatedGattServer',
        detail:
            'GATT write callback recibido: STATUS_SUCCESS (sin errores de buffer)',
        packetBytes: item.bytes,
      );

      if (simulateDeviceResponse) {
        logEvent(
          step: BlePipelineStep.deviceResponseReceived,
          source: 'TripperPodHardware',
          detail: 'Ack de trama de pantalla recibido por indicación CCCD',
        );
      }

      item.completer.complete(true);
    }

    _isWriting = false;
  }

  @override
  Future<bool> stopNavigation() async => true;

  @override
  void clearActiveNavPacket({String? reason}) {}

  @override
  bool get isNavScreenActive => false;

  @override
  bool get isTestManeuverActive => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QueuedPacket {
  final Uint8List bytes;
  final String description;
  final Completer<bool> completer;

  _QueuedPacket(this.bytes, this.description, this.completer);
}

class _PipelineFakeLocationService implements LocationService {
  final StreamController<GpsPosition> _gpsCtrl =
      StreamController<GpsPosition>.broadcast();

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

class _PipelineFakeVoiceService implements VoiceNavigationService {
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

  late SimulatedTripperBleTransport transport;
  late AutoNavigationSourceArbiter arbiter;
  const parser = NavigationInstructionParser();
  const adapter = TripperNavigationAdapter();

  setUp(() {
    transport = SimulatedTripperBleTransport();
    arbiter = AutoNavigationSourceArbiter(
      stalenessTimeout: const Duration(seconds: 45),
    );
    AutoNavigationSourceArbiter.setMockInstance(arbiter);
  });

  tearDown(() {
    AutoNavigationSourceArbiter.setMockInstance(null);
  });

  void verifyTripperPacket(
    Uint8List packet, {
    required int expectedOpcode,
    required int expectedDistanceMeters,
  }) {
    // 1. Longitud exacta de 20 bytes
    expect(
      packet.length,
      equals(20),
      reason: 'El paquete Tripper debe medir exactamente 20 bytes',
    );

    // 2. Encabezado de comando de navegación oficial Tripper: 0x10, 0x11
    expect(
      packet[0],
      equals(0x10),
      reason: 'El primer byte de navegación en el Tripper es 0x10',
    );
    expect(
      packet[1],
      equals(0x11),
      reason: 'El segundo byte de navegación en el Tripper es 0x11',
    );

    // 3. Opcode de maniobra en byte 2
    expect(
      packet[2],
      equals(expectedOpcode),
      reason: 'Opcode 0x${expectedOpcode.toRadixString(16)} esperado en byte 2',
    );

    // 4. Distancia codificada en bytes 3, 4 y 5
    final encodedDist = TripperProtocol.encodeDistance(expectedDistanceMeters);
    expect(packet[3], equals(encodedDist[0]));
    expect(packet[4], equals(encodedDist[1]));
    expect(packet[5], equals(encodedDist[2]));

    // 5. Verificación estricta del CRC16/CCITT-FALSE en bytes 18..19
    final payload18 = packet.sublist(0, 18);
    final calculatedCrc = TripperProtocol.crc16CcittFalse(payload18);
    final packetCrc = (packet[18] << 8) | packet[19];
    expect(
      packetCrc,
      equals(calculatedCrc),
      reason: 'El CRC-16 (0x${calculatedCrc.toRadixString(16)}) debe coincidir',
    );
  }

  group('Validación del Pipeline BLE de Extremo a Extremo (Sección 5)', () {
    test(
      'Pipeline completo para NAVEGACIÓN INTERNA: Maniobra -> Normalización -> Árbitro -> Mapper -> Cola -> Escritura GATT -> Confirmación',
      () async {
        final locationService = _PipelineFakeLocationService();
        final voiceService = _PipelineFakeVoiceService();
        final sessionManager = InternalNavigationSessionManager.instance;

        final internalRoute = CalculatedRoute(
          routePlan: RoutePlan(
            origin: Coordinates(4.6097, -74.0817),
            destination: Coordinates(4.6150, -74.0750),
            estimatedDuration: const Duration(minutes: 10),
            geometry: [
              Coordinates(4.6097, -74.0817),
              Coordinates(4.6120, -74.0780),
              Coordinates(4.6150, -74.0750),
            ],
            totalDistanceMeters: 800.0,
            maneuvers: [
              Maneuver(
                instructionText: 'Sal por Carrera 7',
                type: ManeuverType.depart,
                location: Coordinates(4.6097, -74.0817),
                distanceMeters: 200.0,
                roadName: 'Carrera 7',
              ),
              Maneuver(
                instructionText: 'Gira a la izquierda por Calle 26',
                type: ManeuverType.left,
                location: Coordinates(4.6120, -74.0780),
                distanceMeters: 600.0,
                roadName: 'Calle 26',
              ),
              Maneuver(
                instructionText: 'Llegada al destino',
                type: ManeuverType.arrive,
                location: Coordinates(4.6150, -74.0750),
                distanceMeters: 0.0,
                roadName: 'Destino',
              ),
            ],
          ),
          summary: 'Carrera 7 a Calle 26',
        );

        // 1. Iniciar sesión interna
        final started = await sessionManager.startSession(
          route: internalRoute,
          destination: Destination(
            id: 'dest_int',
            title: 'Calle 26',
            coordinates: Coordinates(4.6150, -74.0750),
          ),
          locationService: locationService,
          bleService: transport,
          voiceService: voiceService,
          arbiter: arbiter,
          selectedSourceProvider: () => SelectedNavigationSourceType.auto,
        );

        expect(started, isTrue);

        // 2. Emitir posición que genera primera maniobra de salida
        locationService.emit(
          GpsPosition(
            coordinates: Coordinates(4.6097, -74.0817),
            accuracyMeters: 3.0,
            speedMps: 10.0,
            timestamp: DateTime.now(),
          ),
        );

        // Esperar ciclo asíncrono de cola GATT
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(transport.transmittedPackets.isNotEmpty, isTrue);

        // Comprobar secuencia estricta de logs de la tubería
        final logSteps = transport.logs.map((l) => l.stepName).toList();
        expect(logSteps, contains('packet_built'));
        expect(logSteps, contains('packet_queued'));
        expect(logSteps, contains('gatt_write_started'));
        expect(logSteps, contains('gatt_write_confirmed'));

        // Inspección de bytes para salida (depart -> 0x3c)
        final firstPacket = transport.transmittedPackets.first;
        verifyTripperPacket(
          firstPacket,
          expectedOpcode: TripperProtocol.maneuverDepart,
          expectedDistanceMeters: 0,
        );

        // Limpiar sesión
        await sessionManager.stopSession();
        locationService.dispose();
      },
    );

    test(
      'Pipeline completo para WAZE: Notificación -> Parser -> Árbitro -> Tripper Adapter -> Cola -> Escritura GATT -> Confirmación',
      () async {
        transport.simulateDeviceResponse = false;

        // 1. Maniobra generada: Notificación cruda de Waze
        final rawTitle = 'En 350 m';
        final rawText = 'Gira a la derecha hacia Calle 100';
        final notifTime = DateTime.now();

        transport.logEvent(
          step: BlePipelineStep.instructionGenerated,
          source: 'WazeStatusBarNotification',
          detail: 'title="$rawTitle", text="$rawText"',
        );

        // 2. Normalización mediante parser sintáctico
        final parsed = parser.parseWaze(
          rawTitle: rawTitle,
          rawText: rawText,
          receivedAt: notifTime,
          notificationKey: '0|com.waze|101|null|10234',
        );

        expect(parsed.status, equals(BridgeInstructionStatus.recognized));
        expect(parsed.maneuverType, equals(ManeuverType.right));
        expect(parsed.distanceMeters, equals(350));
        expect(parsed.destinationStreet, equals('Calle 100'));

        // 3. Source Arbiter acepta la maniobra en modo AUTO
        final arbitration = arbiter.processInstruction(
          parsed,
          correlationId: 'pipeline_waze_1',
        );

        expect(arbitration.action, equals(AutoArbitrationAction.activated));
        expect(arbitration.shouldTransmitToBle, isTrue);
        expect(arbitration.newSource, equals(BridgeSourceType.waze));

        transport.logEvent(
          step: BlePipelineStep.instructionAccepted,
          source: 'AutoNavigationSourceArbiter',
          detail:
              'Fuente Waze activada. Maniobra ${parsed.maneuverType.name} a ${parsed.distanceMeters}m',
        );

        // 4. Tripper mapper construye el paquete oficial
        final adaptation = adapter.adaptBridgeInstruction(parsed);
        expect(adaptation.isSupported, isTrue);
        expect(adaptation.packet, isNotNull);
        expect(
          adaptation.tripperManeuverCode,
          equals(TripperProtocol.maneuverTurnRight),
        );
        expect(adaptation.encodedDistanceMeters, equals(350));

        // 5, 6, 7. Cola -> Escritura GATT simulada -> Confirmación
        final txResult = await transport.sendRawPacket(adaptation.packet!);
        expect(txResult, isTrue);

        // 8. Inspección de resultado registrado
        expect(transport.transmittedPackets.length, equals(1));
        final packet = transport.transmittedPackets.first;

        // Verificar opcode de giro a la derecha (0x15), 350m y CRC
        verifyTripperPacket(
          packet,
          expectedOpcode: TripperProtocol.maneuverTurnRight,
          expectedDistanceMeters: 350,
        );

        // Verificar presencia de todos los logs requeridos
        final logSteps = transport.logs.map((l) => l.stepName).toList();
        expect(
          logSteps,
          equals([
            'instruction_generated',
            'instruction_accepted',
            'packet_built',
            'packet_queued',
            'gatt_write_started',
            'gatt_write_confirmed',
          ]),
        );
      },
    );

    test(
      'Pipeline completo para GOOGLE MAPS: Notificación -> Parser -> Árbitro -> Tripper Adapter -> Cola -> Escritura GATT -> Confirmación',
      () async {
        // 1. Maniobra generada: Notificación cruda de Google Maps
        final rawTitle = 'Gira a la izquierda';
        final rawText = 'en 500 m hacia Av. El Dorado';
        final notifTime = DateTime.now();

        transport.logEvent(
          step: BlePipelineStep.instructionGenerated,
          source: 'GoogleMapsStatusBarNotification',
          detail: 'title="$rawTitle", text="$rawText"',
        );

        // 2. Normalización mediante parser sintáctico
        final parsed = parser.parseGoogleMaps(
          rawTitle: rawTitle,
          rawText: rawText,
          receivedAt: notifTime,
          notificationKey:
              '0|com.google.android.apps.maps|201|navigation|10234',
        );

        expect(parsed.status, equals(BridgeInstructionStatus.recognized));
        expect(parsed.maneuverType, equals(ManeuverType.left));
        expect(parsed.distanceMeters, equals(500));
        expect(parsed.destinationStreet, equals('Av. El Dorado'));

        // 3. Source Arbiter acepta la maniobra en modo AUTO
        final arbitration = arbiter.processInstruction(
          parsed,
          correlationId: 'pipeline_maps_1',
        );

        expect(arbitration.action, equals(AutoArbitrationAction.activated));
        expect(arbitration.shouldTransmitToBle, isTrue);
        expect(arbitration.newSource, equals(BridgeSourceType.googleMaps));

        transport.logEvent(
          step: BlePipelineStep.instructionAccepted,
          source: 'AutoNavigationSourceArbiter',
          detail:
              'Fuente Google Maps activada. Maniobra ${parsed.maneuverType.name} a ${parsed.distanceMeters}m',
        );

        // 4. Tripper mapper construye el paquete oficial
        final adaptation = adapter.adaptBridgeInstruction(parsed);
        expect(adaptation.isSupported, isTrue);
        expect(adaptation.packet, isNotNull);
        expect(
          adaptation.tripperManeuverCode,
          equals(TripperProtocol.maneuverTurnLeft),
        );
        expect(adaptation.encodedDistanceMeters, equals(500));

        // 5, 6, 7. Cola -> Escritura GATT simulada -> Confirmación
        final txResult = await transport.sendRawPacket(adaptation.packet!);
        expect(txResult, isTrue);

        // 8. Inspección de resultado registrado
        expect(transport.transmittedPackets.length, equals(1));
        final packet = transport.transmittedPackets.first;

        // Verificar opcode de giro a la izquierda (0x14), 500m y CRC
        verifyTripperPacket(
          packet,
          expectedOpcode: TripperProtocol.maneuverTurnLeft,
          expectedDistanceMeters: 500,
        );

        final logSteps = transport.logs.map((l) => l.stepName).toList();
        expect(
          logSteps,
          equals([
            'instruction_generated',
            'instruction_accepted',
            'packet_built',
            'packet_queued',
            'gatt_write_started',
            'gatt_write_confirmed',
          ]),
        );
      },
    );
  });
}
