import 'package:flutter_test/flutter_test.dart';
import 'package:road_companion/domain/entities/maneuver_type.dart';
import 'package:road_companion/features/navigation/domain/entities/tripper_maneuver_payload.dart';
import 'package:road_companion/features/navigation/domain/services/tripper_protocol.dart';

void main() {
  group('TripperProtocol - Protocolo BLE Royal Enfield Tripper Pod', () {
    test(
      'Calcula exactamente los vectores de CRC-16/CCITT-FALSE confirmados',
      () {
        // Vector 1: Handshake Resume (0x21 00 ...) -> CRC 0x4045
        final resume18 = List<int>.filled(18, 0);
        resume18[0] = 0x21;
        resume18[1] = 0x00;
        final crcResume = TripperProtocol.crc16CcittFalse(resume18);
        expect(crcResume, 0x4045);

        // Vector 2: Handshake Show PIN (0x21 01 ...) -> CRC 0x50A7
        final showPin18 = List<int>.filled(18, 0);
        showPin18[0] = 0x21;
        showPin18[1] = 0x01;
        final crcShowPin = TripperProtocol.crc16CcittFalse(showPin18);
        expect(crcShowPin, 0x50A7);

        // Vector 3: Ping FW Keepalive (0x03 00 ...) -> CRC 0x45D9
        final ping18 = List<int>.filled(18, 0);
        ping18[0] = 0x03;
        ping18[1] = 0x00;
        final crcPing = TripperProtocol.crc16CcittFalse(ping18);
        expect(crcPing, 0x45D9);
      },
    );

    test(
      'Tramas fijas coinciden con los paquetes precompilados de 20 bytes',
      () {
        expect(TripperProtocol.packetHandshakeResume.length, 20);
        expect(TripperProtocol.packetHandshakeResume[0], 0x21);
        expect(TripperProtocol.packetHandshakeResume[1], 0x00);
        expect(TripperProtocol.packetHandshakeResume[18], 0x40);
        expect(TripperProtocol.packetHandshakeResume[19], 0x45);

        expect(TripperProtocol.packetHandshakeShowPin.length, 20);
        expect(TripperProtocol.packetHandshakeShowPin[0], 0x21);
        expect(TripperProtocol.packetHandshakeShowPin[1], 0x01);
        expect(TripperProtocol.packetHandshakeShowPin[18], 0x50);
        expect(TripperProtocol.packetHandshakeShowPin[19], 0xA7);

        expect(TripperProtocol.packetPingFw.length, 20);
        expect(TripperProtocol.packetPingFw[0], 0x03);
        expect(TripperProtocol.packetPingFw[18], 0x45);
        expect(TripperProtocol.packetPingFw[19], 0xD9);
      },
    );

    test('Construye paquete de PIN (CMD 0x20) con caracteres ASCII', () {
      final pinPkt = TripperProtocol.buildPinPacket('1234');
      expect(pinPkt.length, 20);
      expect(pinPkt[0], 0x20);
      expect(pinPkt[1], 0x31); // '1'
      expect(pinPkt[2], 0x32); // '2'
      expect(pinPkt[3], 0x33); // '3'
      expect(pinPkt[4], 0x34); // '4'
      expect(pinPkt[5], 0x00);

      // Verificar que el CRC generado es válido
      final checkCrc = TripperProtocol.crc16CcittFalse(pinPkt.sublist(0, 18));
      expect((pinPkt[18] << 8) | pinPkt[19], checkCrc);
    });

    test('Construye paquete de reloj (CMD 0x50) en 24h y 12h', () {
      // 14:30 en 24h -> hora 14, min 30
      final time24 = TripperProtocol.buildSetTimePacket(14, 30, false);
      expect(time24.length, 20);
      expect(time24[0], 0x50);
      expect(time24[1], 14);
      expect(time24[2], 30);

      // 09:15 AM en 12h -> hora 9 | 0x40 = 0x49, min 15
      final time12Am = TripperProtocol.buildSetTimePacket(9, 15, true);
      expect(time12Am[1], 9 | 0x40);
      expect(time12Am[2], 15);

      // 15:45 PM en 12h -> hora 3 (sin 0x40), min 45
      final time12Pm = TripperProtocol.buildSetTimePacket(15, 45, true);
      expect(time12Pm[1], 3);
      expect(time12Pm[2], 45);
    });

    test(
      'Codifica distancias según la norma del Tripper (<1000m y >=1000m)',
      () {
        // 450 m -> valor 450, unidad 1
        final d1 = TripperProtocol.encodeDistance(450);
        expect(d1[0], (450 >> 8) & 0xFF);
        expect(d1[1], 450 & 0xFF);
        expect(d1[2], 1); // Unidad metros

        // 22.9 km (22900 m) -> valor 229, unidad 2
        final d2 = TripperProtocol.encodeDistance(22900);
        expect(d2[0], 0);
        expect(d2[1], 229);
        expect(d2[2], 2); // Unidad hectómetros (km * 10)
      },
    );

    test('Construye paquete de navegación (CMD_NAVIGATE 0x10 0x11)', () {
      final navPkt = TripperProtocol.buildNavPacket(
        maneuver: TripperProtocol.maneuverTurnRight,
        distanceMeters: 350,
        nextManeuver: TripperProtocol.maneuverStraight,
        nightMode: false,
      );

      expect(navPkt.length, 20);
      expect(navPkt[0], 0x10);
      expect(navPkt[1], 0x11);
      expect(navPkt[2], 0x15); // Turn right
      expect((navPkt[3] << 8) | navPkt[4], 350);
      expect(navPkt[5], 1); // metros
      expect(navPkt[7], 0x09); // Próxima: seguir recto
      expect(navPkt[10], 0x41); // Flag fijo
    });

    test('Mapea maniobras de ManeuverType a códigos del Tripper', () {
      expect(
        TripperProtocol.mapManeuverToTripperCode(ManeuverType.straight),
        0x09,
      );
      expect(TripperProtocol.mapManeuverToTripperCode(ManeuverType.left), 0x14);
      expect(
        TripperProtocol.mapManeuverToTripperCode(ManeuverType.right),
        0x15,
      );
      expect(
        TripperProtocol.mapManeuverToTripperCode(ManeuverType.uTurn),
        0x3D,
      );
      expect(
        TripperProtocol.mapManeuverToTripperCode(ManeuverType.arrive),
        0x00,
      );
      expect(
        TripperProtocol.mapManeuverToTripperCode(
          ManeuverType.roundabout,
          roundaboutExit: 3,
        ),
        0x34, // 0x32 + (3 - 1)
      );
      expect(
        TripperProtocol.mapManeuverToTripperCode(ManeuverType.unknown),
        isNull,
      );
    });

    test('Construye compás sin ruta con sectores válidos', () {
      final compNorth = TripperProtocol.buildCompassPacket(0, false);
      expect(compNorth[0], 0x10);
      expect(compNorth[1], 0x11);
      expect(compNorth[2], 0x41); // Modo compás
      expect(compNorth[14], 0x10); // Sector Norte
    });

    test(
      'Valida la trama exacta de maniobra de prueba recto 500m y su CRC (73 85)',
      () {
        final pkt = TripperProtocol.buildNavPacket(
          maneuver: TripperProtocol.maneuverStraight,
          distanceMeters: 500,
          nextManeuver: TripperProtocol.nextManeuverNone,
        );
        expect(pkt.length, 20);
        expect(pkt[0], 0x10);
        expect(pkt[1], 0x11);
        expect(pkt[2], 0x09); // maneuverStraight
        expect(pkt[3], 0x01); // 500 = 0x01F4
        expect(pkt[4], 0xF4);
        expect(pkt[5], 0x01); // metros
        expect(pkt[6], 0x00); // intensidad diurna
        expect(pkt[7], 0xFF); // sin segunda maniobra
        expect(pkt[8], 0xFF);
        expect(pkt[9], 0xFF);
        expect(pkt[10], 0x41); // flag fijo
        expect(pkt[11], 0xFF); // sin barra inferior
        expect(pkt[12], 0xFF);
        expect(pkt[13], 0xFF);
        expect(pkt[14], 0x00);
        expect(pkt[15], 0x00);
        expect(pkt[16], 0x00);
        expect(pkt[17], 0x00);
        // CRC-16 esperado: 0x7385
        expect(pkt[18], 0x73);
        expect(pkt[19], 0x85);
        expect(
          TripperProtocol.toHexString(pkt),
          '10 11 09 01 F4 01 00 FF FF FF 41 FF FF FF 00 00 00 00 73 85',
        );
      },
    );

    test('Valida la trama exacta de reloj a las 08:40 y su CRC (9C 4A)', () {
      final pkt = TripperProtocol.buildSetTimePacket(8, 40, false);
      expect(pkt.length, 20);
      expect(pkt[0], 0x50);
      expect(pkt[1], 0x08);
      expect(pkt[2], 0x28); // 40 min = 0x28
      expect(pkt[18], 0x9C);
      expect(pkt[19], 0x4A);
      expect(
        TripperProtocol.toHexString(pkt),
        '50 08 28 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 9C 4A',
      );
    });

    test(
      'TripperManeuverPayload no convierte ManeuverType.unknown en recto y preserva códigos sharp/depart',
      () {
        final unknownPayload = TripperManeuverPayload.fromManeuver(
          type: ManeuverType.unknown,
          distanceMeters: 250,
        );
        expect(unknownPayload.maneuverType, TripperManeuverType.unknown);
        expect(unknownPayload.isSupported, isFalse);
        expect(() => unknownPayload.toProtocolPacket(), throwsStateError);

        final sharpLeftPayload = TripperManeuverPayload.fromManeuver(
          type: ManeuverType.sharpLeft,
          distanceMeters: 120,
        );
        expect(sharpLeftPayload.isSupported, isTrue);
        expect(
          sharpLeftPayload.toProtocolPacket()[2],
          TripperProtocol.maneuverSharpLeft,
        );

        final departPayload = TripperManeuverPayload.fromManeuver(
          type: ManeuverType.depart,
          distanceMeters: 80,
        );
        expect(departPayload.isSupported, isTrue);
        expect(
          departPayload.toProtocolPacket()[2],
          TripperProtocol.maneuverDepart,
        );
      },
    );
  });
}
