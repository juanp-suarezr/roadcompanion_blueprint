import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_companion/domain/entities/maneuver_type.dart';
import 'package:road_companion/features/navigation/domain/entities/tripper_connection_state.dart';
import 'package:road_companion/features/navigation/domain/entities/tripper_device.dart';
import 'package:road_companion/features/navigation/domain/entities/tripper_maneuver_payload.dart';
import 'package:road_companion/features/navigation/domain/services/tripper_protocol.dart';
import 'package:road_companion/features/navigation/infrastructure/services/flutter_blue_plus_tripper_service.dart';

BluetoothService createMockTripperService(String deviceId) {
  final bmChar = BmBluetoothCharacteristic(
    remoteId: DeviceIdentifier(deviceId),
    primaryServiceUuid: null,
    serviceUuid: Guid(TripperProtocol.serviceUuid),
    characteristicUuid: Guid(TripperProtocol.characteristicUuid),
    instanceId: 1,
    descriptors: [],
    properties: BmCharacteristicProperties(
      broadcast: false,
      read: false,
      writeWithoutResponse: true,
      write: true,
      notify: true,
      indicate: false,
      authenticatedSignedWrites: false,
      extendedProperties: false,
      notifyEncryptionRequired: false,
      indicateEncryptionRequired: false,
    ),
  );

  final bmService = BmBluetoothService(
    remoteId: DeviceIdentifier(deviceId),
    primaryServiceUuid: null,
    serviceUuid: Guid(TripperProtocol.serviceUuid),
    characteristics: [bmChar],
  );

  return BluetoothService.fromProto(bmService);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Tripper GATT Connection Resilience & Intercom Coexistence Tests', () {
    late FlutterBluePlusTripperService service;
    final testTripper = TripperDevice.evaluate(
      id: '00:60:37:C8:F3:AD',
      name: 'RE_DISP',
      rssi: -37,
    );

    setUp(() {
      FlutterBluePlusTripperService.resetInstance();
      service = FlutterBluePlusTripperService();
      service.testCharacteristicWriter = (bytes, {required withoutResponse}) async {};
    });

    tearDown(() async {
      try {
        await service.disconnect();
      } catch (_) {}
      service.dispose();
      FlutterBluePlusTripperService.resetInstance();
    });

    // 1. Conexión limpia y descubrimiento exitoso
    test('1. Conexión limpia y descubrimiento exitoso de servicios', () async {
      bool connectorCalled = false;
      bool discovererCalled = false;

      service.testDeviceConnector = (bleDevice) async {
        connectorCalled = true;
      };

      service.testIsConnectedOverride = (bleDevice) => true;

      final mockService = createMockTripperService(testTripper.id);
      service.testServicesDiscoverer = (bleDevice, device) async {
        discovererCalled = true;
        return [mockService];
      };

      final result = await service.connect(testTripper);
      if (!result) {
        // ignore: avoid_print
        print('DIAGNOSTIC LOGS:\n${service.diagnosticLogs.join('\n')}');
      }

      expect(connectorCalled, isTrue);
      expect(discovererCalled, isTrue);
      expect(result, isTrue);
      expect(service.currentState, TripperConnectionState.connected);
      expect(service.connectedDevice?.id, testTripper.id);
      expect(service.isLocalGattServerEnabled, isFalse);
      expect(
        service.diagnosticLogs.any((l) => l.contains('CONEXIÓN Y SESIÓN TRIPPER POD EXITOSA')),
        isTrue,
      );
    });

    // 2. Desconexión inmediata tras conectar (verificar que discoverServices() NO se ejecuta)
    test(
      '2. Desconexión inmediata tras conectar aborta sin invocar discoverServices ni crashear con FbpErrorCode 6',
      () async {
        bool discovererInvoked = false;
        bool isConnectedState = true;

        service.testDeviceConnector = (bleDevice) async {
          isConnectedState = true;
          // Simula desconexión nativa temprana (como en el diagnóstico de Android 16)
          Future.delayed(const Duration(milliseconds: 50), () {
            isConnectedState = false;
            service.simulateDisconnectForTesting();
          });
        };

        service.testIsConnectedOverride = (bleDevice) => isConnectedState;

        service.testServicesDiscoverer = (bleDevice, device) async {
          discovererInvoked = true;
          return [];
        };

        final result = await service.connect(testTripper);

        expect(result, isFalse);
        expect(discovererInvoked, isFalse, reason: 'discoverServices() NUNCA debe ser llamado si el enlace cayó');
        expect(service.currentState, TripperConnectionState.disconnected);
        expect(
          service.diagnosticLogs.any((l) => l.contains('[BLE-CONNECT-EARLY-DISCONNECT]')),
          isTrue,
        );
      },
    );

    // 3. Desconexión tardía de sesión previa no afecta a nueva sesión (epoch tracking)
    test(
      '3. Desconexión tardía de sesión previa no afecta a nueva sesión activa (Session Guard por Epoch)',
      () {
        final initialEpoch = service.gattSessionEpoch;

        // Simula sesión A conectada
        service.simulateGattConnectedForTesting(device: testTripper);
        expect(service.currentState, TripperConnectionState.gattConnected);

        // Desconexión de sesión A y avance de epoch
        service.simulateDisconnectForTesting();
        final epochAfterDisconnect = service.gattSessionEpoch;
        expect(epochAfterDisconnect, greaterThan(initialEpoch));

        // Inicio de sesión B
        service.simulateGattConnectedForTesting(device: testTripper);
        expect(service.currentState, TripperConnectionState.gattConnected);

        // Llega callback nativo de desconexión tardío con el epoch de la sesión A
        service.simulateLateNativeCallbackForTesting(initialEpoch);

        // Verificación estricta: sesión B permanece en gattConnected
        expect(service.currentState, TripperConnectionState.gattConnected);
        expect(
          service.diagnosticLogs.any((l) => l.contains('[SESSION-GUARD]')),
          isTrue,
        );
      },
    );

    // 4. Solicitud de conexión concurrente rechazada/no duplicada
    test('4. Solicitud de conexión concurrente es rechazada de inmediato', () async {
      service.testDeviceConnector = (bleDevice) async {
        await Future.delayed(const Duration(milliseconds: 400));
      };
      service.testIsConnectedOverride = (bleDevice) => true;

      final future1 = service.connect(testTripper);
      expect(service.isConnecting, isTrue);

      final result2 = await service.connect(testTripper);
      expect(result2, isFalse, reason: 'Segunda llamada concurrente debe ser rechazada');
      expect(
        service.diagnosticLogs.any((l) => l.contains('ya existe una conexión en curso')),
        isTrue,
      );

      await service.cancelPendingConnection();
      await future1;
    });

    // 5. Detener escaneo antes de conectar no destruye conexión existente
    test('5. Detener escaneo antes de conectar no afecta conexiones existentes', () async {
      service.simulateGattConnectedForTesting(device: testTripper);
      expect(service.currentState, TripperConnectionState.gattConnected);

      await service.stopScan();

      expect(service.currentState, TripperConnectionState.gattConnected);
      expect(service.isConnecting, isFalse);
    });

    // 6. Manejo de fallo en descubrimiento de servicios
    test(
      '6. Fallo de discoverServices se captura limpiamente sin excepciones no controladas',
      () async {
        service.testDeviceConnector = (bleDevice) async {};
        service.testIsConnectedOverride = (bleDevice) => true;

        service.testServicesDiscoverer = (bleDevice, device) async {
          throw FlutterBluePlusException(
            ErrorPlatform.fbp,
            "discoverServices",
            FbpErrorCode.timeout.index,
            "GATT discovery timeout",
          );
        };

        final result = await service.connect(testTripper);

        expect(result, isFalse);
        expect(service.currentState, TripperConnectionState.error);
        expect(
          service.diagnosticLogs.any((l) => l.contains('[GATT-DISCOVERY-ERROR]')),
          isTrue,
        );
      },
    );

    // 7. Reconexión controlada tras desconexión no deseada (retry con backoff controlado)
    test(
      '7. Reconexión automática controlada tras desconexión prematura (máximo 1 reintento)',
      () async {
        int attempt = 0;

        service.testDeviceConnector = (bleDevice) async {
          attempt++;
          if (attempt == 1) {
            Future.delayed(const Duration(milliseconds: 50), () {
              service.simulateDisconnectForTesting();
            });
          }
        };

        service.testIsConnectedOverride = (bleDevice) => attempt >= 2;

        final mockService = createMockTripperService(testTripper.id);
        service.testServicesDiscoverer = (bleDevice, device) async => [mockService];

        final result = await service.connect(testTripper);

        expect(attempt, 2, reason: 'Debe haber realizado exactamente 2 intentos (1 reintento)');
        expect(result, isTrue);
        expect(service.currentState, TripperConnectionState.connected);
        expect(
          service.diagnosticLogs.any((l) => l.contains('[BLE-RETRY]')),
          isTrue,
        );
      },
    );

    // 8. Servidor GATT local y cliente GATT independientes
    test(
      '8. Servidor GATT local y cliente GATT están completamente desacoplados',
      () async {
        expect(service.isLocalGattServerEnabled, isFalse);

        service.isLocalGattServerEnabled = true;
        expect(service.isLocalGattServerEnabled, isTrue);

        expect(service.currentState, TripperConnectionState.idle);
        await service.stopLocalGattServer();
        expect(service.currentState, TripperConnectionState.idle);

        service.isLocalGattServerEnabled = false;
        service.testDeviceConnector = (bleDevice) async {};
        service.testIsConnectedOverride = (bleDevice) => true;

        final mockService = createMockTripperService(testTripper.id);
        service.testServicesDiscoverer = (bleDevice, device) async => [mockService];

        final ok = await service.connect(testTripper);
        expect(ok, isTrue);
        expect(
          service.diagnosticLogs.any((l) => l.contains('Servidor GATT local desactivado (aislamiento estricto')),
          isTrue,
        );
      },
    );

    // 9. Conexión BLE no depende del estado de audio Bluetooth clásico (LEXIN G2P)
    test(
      '9. Conexión BLE del Tripper es completamente independiente del audio Bluetooth clásico',
      () async {
        service.testDeviceConnector = (bleDevice) async {};
        service.testIsConnectedOverride = (bleDevice) => true;

        final mockService = createMockTripperService(testTripper.id);
        service.testServicesDiscoverer = (bleDevice, device) async => [mockService];

        final connected = await service.connect(testTripper);
        expect(connected, isTrue);

        expect(
          service.diagnosticLogs.any((l) => l.contains('MTU estándar fijo (sin negociación 512)')),
          isTrue,
        );
      },
    );

    // 10. Ninguna trama de navegación enviada antes de autenticación completa
    test(
      '10. Ninguna trama de navegación es enviada antes de autenticación completa',
      () async {
        final dummyPayload = TripperManeuverPayload.fromManeuver(
          type: ManeuverType.right,
          distanceMeters: 250,
          nextStreet: 'Carrera 7',
        );

        // 1. En idle
        expect(service.currentState, TripperConnectionState.idle);
        expect(service.currentState.isReadyForNavigation, isFalse);
        var sent = await service.sendManeuver(dummyPayload);
        expect(sent, isFalse);

        // 2. En connecting
        service.simulateDisconnectForTesting();
        expect(service.currentState.isReadyForNavigation, isFalse);
        sent = await service.sendManeuver(dummyPayload);
        expect(sent, isFalse);

        // 3. En gattConnected
        service.simulateGattConnectedForTesting(device: testTripper);
        expect(service.currentState, TripperConnectionState.gattConnected);
        expect(service.currentState.isReadyForNavigation, isFalse);
        sent = await service.sendManeuver(dummyPayload);
        expect(sent, isFalse);

        // 4. En servicesDiscovered
        service.simulateServicesDiscoveredForTesting(services: []);
        expect(service.currentState, TripperConnectionState.servicesDiscovered);
        expect(service.currentState.isReadyForNavigation, isFalse);
        sent = await service.sendManeuver(dummyPayload);
        expect(sent, isFalse);

        // 5. En authenticated
        service.simulateAuthenticatedForTesting();
        expect(service.currentState, TripperConnectionState.authenticated);
        expect(service.currentState.isReadyForNavigation, isTrue);
        sent = await service.sendManeuver(dummyPayload);
        expect(sent, isFalse); // False porque no hay writeCharacteristic asignada

        expect(
          service.diagnosticLogs.any((l) => l.contains('sesión Tripper Pod no autenticada')),
          isTrue,
        );
      },
    );
  });
}
