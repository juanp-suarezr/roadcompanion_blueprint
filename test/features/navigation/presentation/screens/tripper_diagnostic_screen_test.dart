import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_companion/features/navigation/domain/entities/tripper_connection_state.dart';
import 'package:road_companion/features/navigation/domain/entities/tripper_device.dart';
import 'package:road_companion/features/navigation/domain/entities/tripper_gatt_info.dart';
import 'package:road_companion/features/navigation/domain/entities/tripper_maneuver_payload.dart';
import 'package:road_companion/features/navigation/domain/services/tripper_ble_service.dart';
import 'package:road_companion/features/navigation/domain/services/voice_navigation_service.dart';
import 'package:road_companion/features/navigation/presentation/screens/tripper_diagnostic_screen.dart';
import 'package:road_companion/domain/entities/maneuver.dart';

class MockTripperBleService implements TripperBleService {
  final _stateCtrl = StreamController<TripperConnectionState>.broadcast();
  final _devicesCtrl = StreamController<List<TripperDevice>>.broadcast();
  final _gattCtrl = StreamController<List<TripperGattService>>.broadcast();
  final _logCtrl = StreamController<String>.broadcast();

  TripperConnectionState _currentState = TripperConnectionState.idle;
  TripperDevice? _connectedDevice;
  final List<TripperDevice> _devices = [];
  final List<TripperGattService> _gattServices = [];
  final List<String> _logs = [];
  bool bluetoothAvailable = true;

  @override
  TripperConnectionState get currentState => _currentState;

  @override
  Stream<TripperConnectionState> get stateStream => _stateCtrl.stream;

  @override
  TripperDevice? get connectedDevice => _connectedDevice;

  @override
  List<TripperDevice> get discoveredDevices => _devices;

  @override
  Stream<List<TripperDevice>> get discoveredDevicesStream => _devicesCtrl.stream;

  @override
  List<TripperGattService> get discoveredGattServices => _gattServices;

  @override
  Stream<List<TripperGattService>> get discoveredGattServicesStream => _gattCtrl.stream;

  @override
  List<String> get diagnosticLogs => _logs;

  @override
  Stream<String> get diagnosticLogStream => _logCtrl.stream;

  @override
  Future<bool> isBluetoothAvailable() async => bluetoothAvailable;

  @override
  Future<void> startScan({Duration timeout = const Duration(seconds: 15)}) async {
    _currentState = TripperConnectionState.scanning;
    _stateCtrl.add(_currentState);
  }

  @override
  Future<void> stopScan() async {
    _currentState = TripperConnectionState.idle;
    _stateCtrl.add(_currentState);
  }

  @override
  Future<bool> connect(TripperDevice device) async {
    _connectedDevice = device;
    _currentState = TripperConnectionState.connected;
    _stateCtrl.add(_currentState);
    return true;
  }

  @override
  Future<void> disconnect() async {
    _connectedDevice = null;
    _currentState = TripperConnectionState.idle;
    _stateCtrl.add(_currentState);
  }

  @override
  Future<bool> sendManeuver(TripperManeuverPayload maneuver) async => true;

  @override
  void clearDiagnosticLogs() {
    _logs.clear();
  }

  void emitDevice(TripperDevice device) {
    _devices.add(device);
    _devicesCtrl.add(List.unmodifiable(_devices));
  }

  void emitGattServices(List<TripperGattService> services) {
    _gattServices.clear();
    _gattServices.addAll(services);
    _gattCtrl.add(List.unmodifiable(_gattServices));
  }

  void emitLog(String log) {
    _logs.add(log);
    _logCtrl.add(log);
  }

  void dispose() {
    _stateCtrl.close();
    _devicesCtrl.close();
    _gattCtrl.close();
    _logCtrl.close();
  }
}

class MockVoiceNavigationService implements VoiceNavigationService {
  bool _isMuted = false;
  VoiceServiceStatus _status = VoiceServiceStatus.ready;
  final String _statusMessage = 'Voz lista en es-ES para indicaciones viales.';
  final _statusCtrl = StreamController<VoiceServiceStatus>.broadcast();

  @override
  bool get isMuted => _isMuted;

  @override
  set isMuted(bool val) {
    _isMuted = val;
    _status = val ? VoiceServiceStatus.muted : VoiceServiceStatus.ready;
    _statusCtrl.add(_status);
  }

  @override
  void toggleMute() {
    isMuted = !isMuted;
  }

  @override
  bool get isAvailable => true;

  @override
  VoiceServiceStatus get status => _status;

  @override
  String? get statusMessage => _statusMessage;

  @override
  Stream<VoiceServiceStatus> get statusStream => _statusCtrl.stream;

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
  void dispose() {
    _statusCtrl.close();
  }
}

void main() {
  group('TripperDiagnosticScreen — Pruebas de Interfaz y Estados', () {
    late MockTripperBleService bleService;
    late MockVoiceNavigationService voiceService;

    setUp(() {
      bleService = MockTripperBleService();
      voiceService = MockVoiceNavigationService();
    });

    tearDown(() {
      bleService.dispose();
      voiceService.dispose();
    });

    testWidgets('Renderiza controles completos sin pantalla en blanco', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: TripperDiagnosticScreen(
            bleService: bleService,
            voiceService: voiceService,
            autoCheckHardware: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verifica presencia de encabezado y secciones principales
      expect(find.text('Laboratorio Tripper & GPS'), findsOneWidget);
      expect(find.text('Permisos y Sensores (Android 16)'), findsOneWidget);
      expect(find.text('Royal Enfield Tripper Pod (Meteor 350)'), findsOneWidget);
      expect(find.text('Servicios y Características GATT'), findsOneWidget);
      expect(find.text('Motor de Voz TTS (Indicaciones de Casco)'), findsOneWidget);
      expect(find.text('Fases de Validación — Royal Enfield Tripper'), findsOneWidget);
      expect(find.text('Consola de Diagnóstico en Vivo'), findsOneWidget);

      // Botones esenciales
      expect(find.text('Buscar Tripper'), findsOneWidget);
      expect(find.text('Probar voz'), findsOneWidget);
      expect(find.text('Copiar diagnóstico completo al portapapeles'), findsOneWidget);
    });

    testWidgets('Muestra candidato Tripper detectado tras escaneo', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: TripperDiagnosticScreen(
            bleService: bleService,
            voiceService: voiceService,
            autoCheckHardware: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Emitir candidato
      final candidate = TripperDevice.evaluate(
        id: 'AA:BB:CC:DD:EE:FF',
        name: 'Royal Enfield Tripper',
        rssi: -62,
        serviceUuids: ['0000ffe0-0000-1000-8000-00805f9b34fb'],
      );
      bleService.emitDevice(candidate);
      await tester.pumpAndSettle();

      expect(find.text('Royal Enfield Tripper'), findsOneWidget);
      expect(find.text('CANDIDATO TRIPPER (Alta)'), findsOneWidget);
      expect(find.text('Conectar'), findsOneWidget);
    });

    testWidgets('Muestra árbol de servicios GATT cuando está conectado', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: TripperDiagnosticScreen(
            bleService: bleService,
            voiceService: voiceService,
            autoCheckHardware: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final device = TripperDevice.evaluate(
        id: '11:22:33:44:55:66',
        name: 'Royal Enfield Tripper',
        rssi: -58,
        serviceUuids: ['0000ffe0-0000-1000-8000-00805f9b34fb'],
      );

      await bleService.connect(device);
      bleService.emitGattServices([
        const TripperGattService(
          uuid: '0000ffe0-0000-1000-8000-00805f9b34fb',
          characteristics: [
            TripperGattCharacteristic(
              uuid: '0000ffe1-0000-1000-8000-00805f9b34fb',
              canRead: true,
              canWrite: true,
              canNotify: true,
            ),
          ],
        ),
      ]);
      await tester.pumpAndSettle();

      expect(find.text('Servicio UUID: 0000ffe0-0000-1000-8000-00805f9b34fb'), findsOneWidget);
      expect(find.textContaining('Char: 0000ffe1-0000-1000-8000-00805f9b34fb'), findsOneWidget);
      expect(find.textContaining('READ, WRITE, NOTIFY'), findsOneWidget);
      expect(find.text('ENLAZADO'), findsOneWidget);
    });

    testWidgets('Ejecuta prueba de voz y muestra resultado interactivo', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: TripperDiagnosticScreen(
            bleService: bleService,
            voiceService: voiceService,
            autoCheckHardware: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Voz lista'), findsOneWidget);

      await tester.tap(find.text('Probar voz'));
      await tester.pumpAndSettle();

      expect(find.text('Prueba emitida correctamente.'), findsOneWidget);
    });

    testWidgets('Muestra estado de lista vacía con instrucciones cuando no hay dispositivos', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: TripperDiagnosticScreen(
            bleService: bleService,
            voiceService: voiceService,
            autoCheckHardware: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sin dispositivos detectados'), findsOneWidget);
      expect(find.text('Pasos para conectar tu Tripper Pod:'), findsOneWidget);
      expect(find.text('Gira la llave de ignición de tu Meteor 350 a la posición ON.'), findsOneWidget);
    });

    testWidgets('Muestra estado de escaneo activo con spinner y botón de cancelar búsqueda', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: TripperDiagnosticScreen(
            bleService: bleService,
            voiceService: voiceService,
            autoCheckHardware: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Iniciar escaneo con Buscar Tripper
      await tester.tap(find.text('Buscar Tripper'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Cancelar búsqueda'), findsOneWidget);
      expect(find.text('Buscando todos los periféricos BLE cercanos sin filtros...'), findsOneWidget);

      // Cancelar búsqueda
      await tester.tap(find.text('Cancelar búsqueda'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Buscar Tripper'), findsOneWidget);
    });

    testWidgets('Muestra registros de diagnóstico en tiempo real en la consola', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: TripperDiagnosticScreen(
            bleService: bleService,
            voiceService: voiceService,
            autoCheckHardware: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      bleService.emitLog('[ERROR] Error de conexión BLE con Tripper Pod timeout');
      await tester.pumpAndSettle();

      expect(find.textContaining('Error de conexión BLE con Tripper Pod timeout'), findsOneWidget);
    });
  });
}
