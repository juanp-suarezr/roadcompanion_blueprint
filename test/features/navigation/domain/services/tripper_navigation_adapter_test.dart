import 'package:flutter_test/flutter_test.dart';
import 'package:road_companion/domain/entities/maneuver_type.dart';
import 'package:road_companion/features/bridge/domain/entities/bridge_instruction_status.dart';
import 'package:road_companion/features/bridge/domain/entities/bridge_navigation_instruction.dart';
import 'package:road_companion/features/bridge/domain/entities/bridge_source_type.dart';
import 'package:road_companion/features/navigation/domain/services/tripper_navigation_adapter.dart';
import 'package:road_companion/features/navigation/domain/services/tripper_protocol.dart';

void main() {
  group('TripperNavigationAdapter - Adaptación Waze / REStelar a Tripper', () {
    const adapter = TripperNavigationAdapter();

    test('Convierte exitosamente instrucción reconocida de Waze con giro y distancia',
        () {
      final instruction = BridgeNavigationInstruction(
        source: BridgeSourceType.waze,
        maneuverType: ManeuverType.right,
        distanceMeters: 250,
        rawText: 'Gira a la derecha en 250 m por Calle 100',
        destinationStreet: 'Calle 100',
        receivedAt: DateTime(2026, 10, 22, 10, 30),
        status: BridgeInstructionStatus.recognized,
      );

      final result = adapter.adaptBridgeInstruction(instruction);

      expect(result.isSupported, isTrue);
      expect(result.packet, isNotNull);
      expect(result.packet!.length, 20);
      expect(result.tripperManeuverCode, TripperProtocol.maneuverTurnRight);
      expect(result.encodedDistanceMeters, 250);
      expect(result.packet![0], 0x10);
      expect(result.packet![1], 0x11);
      expect(result.packet![2], 0x15); // Turn right
    });

    test('Rechaza instrucción de Waze que carece de distancia válida', () {
      final instruction = BridgeNavigationInstruction(
        source: BridgeSourceType.waze,
        maneuverType: ManeuverType.left,
        distanceMeters: null, // Sin distancia
        rawText: 'Gira a la izquierda',
        receivedAt: DateTime(2026, 10, 22, 10, 30),
        status: BridgeInstructionStatus.incomplete,
      );

      final result = adapter.adaptBridgeInstruction(instruction);

      expect(result.isSupported, isFalse);
      expect(result.packet, isNull);
      expect(result.description, contains('reconocida'));
    });

    test('Rechaza instrucción con maniobra desconocida', () {
      final instruction = BridgeNavigationInstruction(
        source: BridgeSourceType.waze,
        maneuverType: ManeuverType.unknown,
        distanceMeters: 500,
        rawText: 'Texto extraño no mapeado',
        receivedAt: DateTime(2026, 10, 22, 10, 30),
        status: BridgeInstructionStatus.recognized,
      );

      final result = adapter.adaptBridgeInstruction(instruction);

      expect(result.isSupported, isFalse);
      expect(result.packet, isNull);
      expect(result.description, contains('no posee representación'));
    });

    test('Rechaza instrucción marcada como obsoleta (stale)', () {
      final instruction = BridgeNavigationInstruction(
        source: BridgeSourceType.waze,
        maneuverType: ManeuverType.straight,
        distanceMeters: 100,
        rawText: 'Continúa',
        receivedAt: DateTime(2026, 10, 22, 10, 30),
        status: BridgeInstructionStatus.stale,
      );

      final result = adapter.adaptBridgeInstruction(instruction);

      expect(result.isSupported, isFalse);
      expect(result.packet, isNull);
      expect(result.description, contains('obsoleta'));
    });

    test('Mapea glorieta con salida específica (ej. salida 2)', () {
      final instruction = BridgeNavigationInstruction(
        source: BridgeSourceType.googleMaps,
        maneuverType: ManeuverType.roundabout,
        roundaboutExit: 2,
        distanceMeters: 150,
        rawText: 'En la rotonda toma la 2.ª salida',
        receivedAt: DateTime(2026, 10, 22, 10, 30),
        status: BridgeInstructionStatus.recognized,
      );

      final result = adapter.adaptBridgeInstruction(instruction);

      expect(result.isSupported, isTrue);
      expect(result.tripperManeuverCode, 0x33); // 0x32 + (2-1)
      expect(result.packet![2], 0x33);
    });

    test('Adapta maniobra nativa directa de REStelar', () {
      final result = adapter.adaptNativeManeuver(
        maneuverType: ManeuverType.slightLeft,
        distanceMeters: 600,
        totalDistanceMeters: 12000,
      );

      expect(result.isSupported, isTrue);
      expect(result.tripperManeuverCode, TripperProtocol.maneuverSlightLeft);
      expect(result.packet!.length, 20);
    });
  });
}
