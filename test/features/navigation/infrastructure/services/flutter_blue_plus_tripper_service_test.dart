import 'package:flutter_test/flutter_test.dart';
import 'package:road_companion/features/navigation/domain/entities/tripper_connection_state.dart';
import 'package:road_companion/features/navigation/infrastructure/services/flutter_blue_plus_tripper_service.dart';

void main() {
  group('FlutterBluePlusTripperService Unit Tests', () {
    setUp(() {
      FlutterBluePlusTripperService.resetInstance();
    });

    tearDown(() {
      FlutterBluePlusTripperService.resetInstance();
    });

    test('Mantiene instancia singleton compartida entre llamadas', () {
      final s1 = FlutterBluePlusTripperService();
      final s2 = FlutterBluePlusTripperService();
      expect(identical(s1, s2), isTrue);
    });

    test('resetInstance crea una nueva instancia en la siguiente llamada', () {
      final s1 = FlutterBluePlusTripperService();
      FlutterBluePlusTripperService.resetInstance();
      final s2 = FlutterBluePlusTripperService();
      expect(identical(s1, s2), isFalse);
    });

    test('Inicializa en estado idle con lista de dispositivos vacía', () {
      final service = FlutterBluePlusTripperService();
      expect(service.currentState, TripperConnectionState.idle);
      expect(service.discoveredDevices, isEmpty);
      expect(service.connectedDevice, isNull);
      expect(service.lastScanError, isNull);
    });

    test('Permite limpiar logs de diagnóstico', () {
      final service = FlutterBluePlusTripperService();
      expect(service.diagnosticLogs, isNotEmpty); // Inicialización genera log
      service.clearDiagnosticLogs();
      expect(service.diagnosticLogs.length, 1);
      expect(
        service.diagnosticLogs.first,
        contains('Búfer de diagnóstico reiniciado.'),
      );
    });

    test(
      'clearDiscoveredDevices emite lista vacía en el stream reactivo',
      () async {
        final service = FlutterBluePlusTripperService();
        final expectation = expectLater(
          service.discoveredDevicesStream,
          emits(isEmpty),
        );
        service.clearDiscoveredDevices();
        await expectation;
        expect(service.discoveredDevices, isEmpty);
      },
    );

    test('isConnecting inicial es false y currentConnectionPhase es null', () {
      final service = FlutterBluePlusTripperService();
      expect(service.isConnecting, isFalse);
      expect(service.currentConnectionPhase, isNull);
    });

    test(
      'cancelPendingConnection cuando no hay conexión no altera el estado',
      () async {
        final service = FlutterBluePlusTripperService();
        await service.cancelPendingConnection();
        expect(service.isConnecting, isFalse);
        expect(service.currentState, TripperConnectionState.idle);
      },
    );

    test(
      'exportFullDiagnosticReport genera reporte estructurado sin credenciales',
      () {
        final service = FlutterBluePlusTripperService();
        final report = service.exportFullDiagnosticReport();
        expect(report, contains('INFORME DE DIAGNÓSTICO BLE — RESTELAR'));
        expect(report, contains('Estado de conexión: idle'));
        expect(report, contains('Dispositivos descubiertos (0)'));
        expect(report, contains('Última trama navegación:'));
        expect(report, contains('Último keepalive (PING_FW):'));
        expect(report, contains('Desconexión local solicitada: false'));
        expect(report, contains('REGISTRO COMPLETO DE EVENTOS'));
        expect(report, contains('=== FIN DEL INFORME ==='));
        // No contiene contraseñas ni tokens
        expect(report.contains('password'), isFalse);
        expect(report.contains('token'), isFalse);
        expect(report.contains('secret'), isFalse);
      },
    );

    test(
      'Telemetry getters se inicializan con valores por defecto seguros',
      () {
        final service = FlutterBluePlusTripperService();
        expect(service.lastNavPacketSentTime, isNull);
        expect(service.lastNavPacketSentHex, isNull);
        expect(service.lastKeepAliveSentTime, isNull);
        expect(service.isLocalDisconnectRequested, isFalse);
        expect(service.isNavScreenActive, isFalse);
        expect(service.isTestManeuverActive, isFalse);
      },
    );

    test(
      'stopNavigation limpia flags y emite logs de solicitud y purga',
      () async {
        final service = FlutterBluePlusTripperService();
        final result = await service.stopNavigation();
        expect(result, isFalse); // No conectado
        expect(service.isNavScreenActive, isFalse);
        expect(service.isTestManeuverActive, isFalse);
        expect(
          service.diagnosticLogs.any((l) => l.contains('[NAV-STOP-REQ]')),
          isTrue,
        );
        expect(
          service.diagnosticLogs.any((l) => l.contains('[NAV-STOP-PURGE]')),
          isTrue,
        );
      },
    );

    test('disconnect registra solicitud local explícita en logs', () async {
      final service = FlutterBluePlusTripperService();
      await service.disconnect();
      expect(
        service.diagnosticLogs.any(
          (l) => l.contains('[BLE-DISCONNECT-LOCAL-REQ]'),
        ),
        isTrue,
      );
    });

    test(
      'Banderas de concurrencia nativa inician en false y se limpian al desconectar',
      () async {
        final service = FlutterBluePlusTripperService();
        expect(service.isNativeWriteInFlight, isFalse);
        expect(service.isGattBusyOrCompromised, isFalse);

        service.setGattCompromisedForTesting(true);
        expect(service.isGattBusyOrCompromised, isTrue);

        await service.disconnect();
        expect(service.isGattBusyOrCompromised, isFalse);
        expect(service.isNativeWriteInFlight, isFalse);
      },
    );

    test(
      'Aislamiento de sesiones GATT: callback nativo tardío de sesión anterior es ignorado por session guard',
      () async {
        final service = FlutterBluePlusTripperService();
        final initialEpoch = service.gattSessionEpoch;

        // 1. Sesión GATT A: inicia escritura, procesa cola, timeout marca canal comprometido
        service.setNativeWriteInFlightForTesting(true);
        service.setIsProcessingQueueForTesting(true);
        service.setGattCompromisedForTesting(true);
        expect(service.isNativeWriteInFlight, isTrue);
        expect(service.isProcessingQueue, isTrue);
        expect(service.isGattBusyOrCompromised, isTrue);

        // 2. Se desconecta la sesión A: epoch avanza y todas las banderas se limpian
        service.simulateDisconnectForTesting();
        final disconnectedEpoch = service.gattSessionEpoch;
        expect(disconnectedEpoch, greaterThan(initialEpoch));
        expect(service.isNativeWriteInFlight, isFalse);
        expect(service.isProcessingQueue, isFalse);
        expect(service.isGattBusyOrCompromised, isFalse);

        // 3. Se inicia la sesión GATT B (nuevo epoch, indicadores limpios)
        service
            .simulateDisconnectForTesting(); // Simula inicio de nueva conexión activa
        final newSessionEpoch = service.gattSessionEpoch;
        expect(newSessionEpoch, greaterThan(disconnectedEpoch));
        expect(service.isNativeWriteInFlight, isFalse);
        expect(service.isProcessingQueue, isFalse);
        expect(service.isGattBusyOrCompromised, isFalse);

        // 4. En la sesión B se inicia una escritura activa
        service.setNativeWriteInFlightForTesting(true);
        service.setIsProcessingQueueForTesting(true);
        expect(service.isNativeWriteInFlight, isTrue);
        expect(service.isProcessingQueue, isTrue);

        // 5. Llega tardíamente el callback de la sesión A
        service.simulateLateNativeCallbackForTesting(initialEpoch);

        // 6. Verificación estricta: el callback de A no altera ningún estado de la sesión B
        expect(
          service.isNativeWriteInFlight,
          isTrue,
        ); // No libera indebidamente el bloqueo de B
        expect(
          service.isProcessingQueue,
          isTrue,
        ); // La cola de B sigue en procesamiento
        expect(
          service.isGattBusyOrCompromised,
          isFalse,
        ); // No contamina el estado del canal de B
        expect(
          service.diagnosticLogs.any((l) => l.contains('[SESSION-GUARD]')),
          isTrue,
        );

        // 7. Cuando el callback legítimo de la sesión B termina, se libera correctamente
        service.simulateLateNativeCallbackForTesting(newSessionEpoch);
        expect(service.isNativeWriteInFlight, isFalse);
      },
    );
  });
}
