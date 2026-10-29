import 'package:flutter_test/flutter_test.dart';
import 'package:road_companion/features/navigation/domain/services/tripper_protocol.dart';

void main() {
  group('TripperProtocol - Serializador 10 11, Progresión Visual y CRC-16', () {
    test('Matriz de 7 distancias representativas genera tramas exactas de 20 bytes con CRC válido', () {
      const maneuverTurnRight = TripperProtocol.maneuverTurnRight; // 0x15
      const nextTurnLeft = TripperProtocol.maneuverTurnLeft; // 0x14

      // 1. 600 m: Mayor a 500m -> Fiel a diseño: sólido, sin barras (Byte 6 = 0x00), sin prox maniobra (Byte 7 = 0xFF)
      final pkt600 = TripperProtocol.buildNavPacket(
        maneuver: maneuverTurnRight,
        distanceMeters: 600,
        nextManeuver: TripperProtocol.nextManeuverNone,
        nightMode: false,
      );
      expect(TripperProtocol.toHexString(pkt600),
          '10 11 15 02 58 01 00 FF FF FF 41 FF FF FF 00 00 00 00 FE 82');
      expect(pkt600[2], 0x15);
      expect(pkt600[3], 0x02);
      expect(pkt600[4], 0x58);
      expect(pkt600[5], 0x01); // Unidad metros
      expect(pkt600[6], 0x00); // 0 barras
      expect(pkt600[7], 0xFF); // Sin indicación secundaria

      // 2. 400 m: Menor a 500m pero mayor a 100m -> Sólido, sin barras (0x00), sin prox maniobra (0xFF)
      final pkt400 = TripperProtocol.buildNavPacket(
        maneuver: maneuverTurnRight,
        distanceMeters: 400,
        nextManeuver: TripperProtocol.nextManeuverNone,
        nightMode: false,
      );
      expect(TripperProtocol.toHexString(pkt400),
          '10 11 15 01 90 01 00 FF FF FF 41 FF FF FF 00 00 00 00 8A 0D');
      expect(pkt400[3], 0x01);
      expect(pkt400[4], 0x90);
      expect(pkt400[6], 0x00);
      expect(pkt400[7], 0xFF);

      // 3. 150 m: Mayor a 100m -> Sólido, sin barras (0x00), sin prox maniobra (0xFF)
      final pkt150 = TripperProtocol.buildNavPacket(
        maneuver: maneuverTurnRight,
        distanceMeters: 150,
        nextManeuver: TripperProtocol.nextManeuverNone,
        nightMode: false,
      );
      expect(TripperProtocol.toHexString(pkt150),
          '10 11 15 00 96 01 00 FF FF FF 41 FF FF FF 00 00 00 00 2F 96');
      expect(pkt150[3], 0x00);
      expect(pkt150[4], 0x96);
      expect(pkt150[6], 0x00);
      expect(pkt150[7], 0xFF);

      // 4. 90 m: Menor a 100m -> 1 barra de progresión (0x10) y aparece próxima maniobra (0x14)
      final pkt90 = TripperProtocol.buildNavPacket(
        maneuver: maneuverTurnRight,
        distanceMeters: 90,
        nextManeuver: nextTurnLeft,
        nightMode: false,
      );
      expect(TripperProtocol.toHexString(pkt90),
          '10 11 15 00 5A 01 10 14 FF FF 41 FF FF FF 00 00 00 00 CF B8');
      expect(pkt90[3], 0x00);
      expect(pkt90[4], 0x5A);
      expect(pkt90[6], 0x10); // 1 barra
      expect(pkt90[7], 0x14); // Seta secundaria visible

      // 5. 50 m: Menor a 70m -> 2 barras de progresión (0x20)
      final pkt50 = TripperProtocol.buildNavPacket(
        maneuver: maneuverTurnRight,
        distanceMeters: 50,
        nextManeuver: nextTurnLeft,
        nightMode: false,
      );
      expect(TripperProtocol.toHexString(pkt50),
          '10 11 15 00 32 01 20 14 FF FF 41 FF FF FF 00 00 00 00 CB 53');
      expect(pkt50[3], 0x00);
      expect(pkt50[4], 0x32);
      expect(pkt50[6], 0x20); // 2 barras
      expect(pkt50[7], 0x14);

      // 6. 20 m: Menor o igual a 20m -> 4 barras de progresión (0x40)
      final pkt20 = TripperProtocol.buildNavPacket(
        maneuver: maneuverTurnRight,
        distanceMeters: 20,
        nextManeuver: nextTurnLeft,
        nightMode: false,
      );
      expect(TripperProtocol.toHexString(pkt20),
          '10 11 15 00 14 01 40 14 FF FF 41 FF FF FF 00 00 00 00 EE 1B');
      expect(pkt20[3], 0x00);
      expect(pkt20[4], 0x14);
      expect(pkt20[6], 0x40); // 4 barras
      expect(pkt20[7], 0x14);

      // 7. 5 m: Menor o igual a 10m -> Punto de giro (0x50: 4 barras / destello / ejecución)
      final pkt5 = TripperProtocol.buildNavPacket(
        maneuver: maneuverTurnRight,
        distanceMeters: 5,
        nextManeuver: nextTurnLeft,
        nightMode: false,
      );
      expect(TripperProtocol.toHexString(pkt5),
          '10 11 15 00 05 01 50 14 FF FF 41 FF FF FF 00 00 00 00 64 DD');
      expect(pkt5[3], 0x00);
      expect(pkt5[4], 0x05);
      expect(pkt5[6], 0x50); // Estado máximo de giro
      expect(pkt5[7], 0x14);
    });

    test('Byte [6] mapea exactamente las transiciones diurnas y nocturnas (+1)', () {
      // Día (bit 0 = 0)
      expect(TripperProtocol.distanceIntensity(600, false), 0x00);
      expect(TripperProtocol.distanceIntensity(100, false), 0x00);
      expect(TripperProtocol.distanceIntensity(99, false), 0x10); // 1 barra
      expect(TripperProtocol.distanceIntensity(71, false), 0x10);
      expect(TripperProtocol.distanceIntensity(70, false), 0x20); // 2 barras
      expect(TripperProtocol.distanceIntensity(46, false), 0x20);
      expect(TripperProtocol.distanceIntensity(45, false), 0x30); // 3 barras
      expect(TripperProtocol.distanceIntensity(21, false), 0x30);
      expect(TripperProtocol.distanceIntensity(20, false), 0x40); // 4 barras
      expect(TripperProtocol.distanceIntensity(11, false), 0x40);
      expect(TripperProtocol.distanceIntensity(10, false), 0x50); // Ejecución de giro
      expect(TripperProtocol.distanceIntensity(0, false), 0x50);

      // Noche (bit 0 = 1)
      expect(TripperProtocol.distanceIntensity(600, true), 0x01);
      expect(TripperProtocol.distanceIntensity(100, true), 0x01);
      expect(TripperProtocol.distanceIntensity(90, true), 0x11);
      expect(TripperProtocol.distanceIntensity(50, true), 0x21);
      expect(TripperProtocol.distanceIntensity(30, true), 0x31);
      expect(TripperProtocol.distanceIntensity(20, true), 0x41);
      expect(TripperProtocol.distanceIntensity(5, true), 0x51);
    });

    test('Cálculo de CRC-16/CCITT-FALSE estricto sobre los 18 bytes', () {
      final payload18 = [
        0x10, 0x11, 0x15, 0x02, 0x58, 0x01, 0x00, 0xFF,
        0xFF, 0xFF, 0x41, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00
      ];
      final crc = TripperProtocol.crc16CcittFalse(payload18);
      expect(crc, 0xFE82);

      final fullPacket = TripperProtocol.withCrc(payload18);
      expect(fullPacket.length, 20);
      expect(fullPacket[18], 0xFE);
      expect(fullPacket[19], 0x82);
    });
  });
}
