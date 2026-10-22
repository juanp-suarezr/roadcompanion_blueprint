import 'package:flutter_test/flutter_test.dart';
import 'package:road_companion/features/navigation/domain/entities/tripper_connection_state.dart';
import 'package:road_companion/features/navigation/domain/entities/tripper_device.dart';
import 'package:road_companion/features/navigation/domain/entities/tripper_maneuver_payload.dart';

void main() {
  group('TripperDevice - Evaluación Técnica de Candidatos', () {
    test(
      'Identifica Tripper Pod por nombre de Royal Enfield y servicio UART',
      () {
        final device = TripperDevice.evaluate(
          id: 'AA:BB:CC:DD:EE:FF',
          name: 'Royal Enfield Tripper',
          rssi: -65,
          serviceUuids: ['0000ffe0-0000-1000-8000-00805f9b34fb'],
        );

        expect(device.isTripperCandidate, isTrue);
        expect(device.confidenceLevel, 'Alta');
        expect(
          device.technicalEvidence,
          contains('Nombre anunciado concordante'),
        );
        expect(device.rssi, -65);
      },
    );

    test(
      'Identifica Meteor 350 con confianza Media si no anuncia UUIDs específicos',
      () {
        final device = TripperDevice.evaluate(
          id: '11:22:33:44:55:66',
          name: 'RE_METEOR_350',
          rssi: -72,
          serviceUuids: [],
        );

        expect(device.isTripperCandidate, isTrue);
        expect(device.confidenceLevel, 'Media');
        expect(device.technicalEvidence, contains('Se requiere conectar'));
      },
    );

    test('Descarta auriculares o dispositivos BLE ajenos', () {
      final device = TripperDevice.evaluate(
        id: '99:88:77:66:55:44',
        name: 'Sony WH-1000XM4',
        rssi: -80,
        serviceUuids: ['0000180d-0000-1000-8000-00805f9b34fb'],
      );

      expect(device.isTripperCandidate, isFalse);
      expect(device.confidenceLevel, 'Baja');
      expect(
        device.technicalEvidence,
        contains('genérico sin identificadores'),
      );
    });

    test('Maneja dispositivo sin nombre adecuadamente', () {
      final device = TripperDevice.evaluate(
        id: '00:11:22:33:44:55',
        name: '',
        rssi: -90,
        serviceUuids: [],
      );

      expect(device.name, 'Dispositivo BLE sin nombre');
      expect(device.isTripperCandidate, isFalse);
    });
  });

  group('TripperManeuverPayload - Empaquetado y Diagnóstico', () {
    test('Genera texto de diagnóstico estructurado', () {
      final payload = TripperManeuverPayload(
        distanceMeters: 450,
        maneuverType: TripperManeuverType.turnLeft,
        nextStreet: 'Calle 38',
        timestamp: DateTime(2026, 10, 21, 14, 30, 0),
      );

      final diag = payload.toDiagnosticString();
      expect(diag, contains('[MANIOBRA]'));
      expect(diag, contains('turnLeft'));
      expect(diag, contains('450m'));
      expect(diag, contains('Calle 38'));
    });

    test(
      'Genera paquete de bytes tentativos con encabezado, opcode, distancia y checksum',
      () {
        final payload = TripperManeuverPayload(
          distanceMeters: 300,
          maneuverType: TripperManeuverType.turnRight,
          nextStreet: 'Carrera 16',
          timestamp: DateTime(2026, 10, 21, 14, 35, 0),
        );

        final bytes = payload.toTentativeBytes();
        expect(bytes.length, 5);
        expect(bytes[0], 0xAA); // Sync byte
        expect(bytes[1], 0x03); // turnRight code
        expect((bytes[2] << 8) | bytes[3], 300); // 300 metros

        // Verificar checksum XOR
        int xor = 0;
        for (int i = 0; i < 4; i++) {
          xor ^= bytes[i];
        }
        expect(bytes[4], xor);
      },
    );

    test(
      'Clasifica correctamente todas las variantes del ciclo de vida BLE',
      () {
        expect(
          TripperConnectionState.values,
          contains(TripperConnectionState.idle),
        );
        expect(
          TripperConnectionState.values,
          contains(TripperConnectionState.scanning),
        );
        expect(
          TripperConnectionState.values,
          contains(TripperConnectionState.connecting),
        );
        expect(
          TripperConnectionState.values,
          contains(TripperConnectionState.connected),
        );
        expect(
          TripperConnectionState.values,
          contains(TripperConnectionState.error),
        );
      },
    );
  });
}
