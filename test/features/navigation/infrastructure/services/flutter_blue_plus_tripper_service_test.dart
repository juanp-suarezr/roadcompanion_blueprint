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

    test('Telemetry getters se inicializan con valores por defecto seguros', () {
      final service = FlutterBluePlusTripperService();
      expect(service.lastNavPacketSentTime, isNull);
      expect(service.lastNavPacketSentHex, isNull);
      expect(service.lastKeepAliveSentTime, isNull);
      expect(service.isLocalDisconnectRequested, isFalse);
      expect(service.isNavScreenActive, isFalse);
      expect(service.isTestManeuverActive, isFalse);
    });

    test('stopNavigation limpia flags y emite logs de solicitud y purga', () async {
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
    });

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
  });
}
