import 'dart:convert';
import 'dart:typed_data';

import '../../../../domain/entities/maneuver_type.dart';

/// Implementación formal del protocolo Bluetooth Low Energy del Royal Enfield Tripper Pod
/// (Meteor 350, periférico anunciado como RE_DISP, hardware NXP Semiconductor).
///
/// Especificación de referencia comunitaria e interoperabilidad:
/// - Repositorio: https://github.com/jnsdias/wazetripper
/// - Documentación técnica: PROTOCOL.md & TripperProtocol.java
///
/// Todas las tramas constan de 20 bytes exactos:
/// - Bytes 0..17: Carga útil de comando o datos (18 bytes).
/// - Bytes 18..19: CRC-16/CCITT-FALSE (Big Endian, MSB first, poly 0x1021, init 0xFFFF).
class TripperProtocol {
  TripperProtocol._();

  /// UUID del servicio principal NXP Wireless UART del Tripper Pod.
  static const String serviceUuid = '01ff0100-ba5e-f4ee-5ca1-eb1e5e4b1ce0';

  /// UUID de la característica de escritura/lectura NXP Wireless UART.
  static const String characteristicUuid =
      '01ff0101-ba5e-f4ee-5ca1-eb1e5e4b1ce0';

  /// UUID del Client Characteristic Configuration Descriptor (CCCD).
  static const String cccdUuid = '00002902-0000-1000-8000-00805f9b34fb';

  /// Nombre BLE oficial transmitido en el anuncio publicitario.
  static const String expectedDeviceName = 'RE_DISP';

  /// Prefijo OUI de dirección MAC registrado a NXP Semiconductors.
  static const String nxpMacPrefix = '00:60:37';

  // --- Códigos de maniobra confirmados en hardware Tripper Pod (Byte [2]) ---
  static const int maneuverDestination = 0x00;
  static const int maneuverDestinationLeft = 0x01;
  static const int maneuverDestinationRight = 0x02;
  static const int maneuverMergeRight = 0x03;
  static const int maneuverMergeLeft = 0x04;
  static const int maneuverForkRight = 0x05;
  static const int maneuverForkLeft = 0x06;
  static const int maneuverOffRampRight = 0x07;
  static const int maneuverOffRampLeft = 0x08;
  static const int maneuverStraight = 0x09;
  static const int maneuverRoundaboutBase = 0x0A;
  static const int maneuverTurnLeft = 0x14;
  static const int maneuverTurnRight = 0x15;
  static const int maneuverSharpLeft = 0x16;
  static const int maneuverSharpRight = 0x17;
  static const int maneuverSlightLeft = 0x18;
  static const int maneuverSlightRight = 0x19;
  static const int maneuverUTurnClockwise = 0x1A;
  static const int maneuverExitKeepRight = 0x27;
  static const int maneuverExitKeepLeft = 0x28;
  static const int maneuverOffRampSlightRight = 0x2D;
  static const int maneuverOffRampSlightLeft = 0x2E;
  static const int maneuverDepart = 0x3C;
  static const int maneuverUTurnCounterClockwise = 0x3D;
  static const int maneuverRouteStarted = 0x45;
  static const int maneuverReRouting = 0x1C;

  // Seta pequeña de próxima maniobra (Byte [7])
  static const int nextManeuverNone = 0xFF;
  static const int nextManeuverRadar = 0x3C;
  static const int nextKeepLeftGeneric = 0x2B;
  static const int nextKeepRightGeneric = 0x2C;

  // Modos de línea inferior (Bytes [11-13])
  static const int bottomTotalDistance = 0;
  static const int bottomTimeRemaining = 1;
  static const int bottomArrivalTime = 2;

  // --- Tramas fijas precalculadas con su CRC (20 bytes) ---
  /// Handshake para dispositivo ya emparejado previamente (0x21 00).
  static final Uint8List packetHandshakeResume = Uint8List.fromList([
    0x21, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // 0..7
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // 8..15
    0x00, 0x00, // 16..17
    0x40, 0x45, // CRC-16
  ]);

  /// Handshake para emparejamiento nuevo donde el Pod muestra un PIN (0x21 01).
  static final Uint8List packetHandshakeShowPin = Uint8List.fromList([
    0x21, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // 0..7
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // 8..15
    0x00, 0x00, // 16..17
    0x50, 0xA7, // CRC-16
  ]);

  /// Keepalive mandatorio cada 2 segundos (0x03 00).
  ///
  /// El Pod cuenta con un watchdog en su firmware que desconecta el enlace BLE
  /// automáticamente si transcurren aproximadamente 5 segundos sin recibir datos.
  static final Uint8List packetPingFw = Uint8List.fromList([
    0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // 0..7
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // 8..15
    0x00, 0x00, // 16..17
    0x45, 0xD9, // CRC-16
  ]);

  /// Calcula el CRC-16/CCITT-FALSE estándar sobre un arreglo de bytes.
  /// Polinomio: 0x1021 | Valor inicial: 0xFFFF | Sin XOR final.
  static int crc16CcittFalse(List<int> bytes) {
    int crc = 0xFFFF;
    for (final b in bytes) {
      crc ^= ((b & 0xFF) << 8);
      for (int i = 0; i < 8; i++) {
        if ((crc & 0x8000) != 0) {
          crc = (((crc << 1) ^ 0x1021) & 0xFFFF);
        } else {
          crc = ((crc << 1) & 0xFFFF);
        }
      }
    }
    return crc & 0xFFFF;
  }

  /// Toma 18 bytes de carga útil y anexa los 2 bytes de CRC-16 (Big-Endian).
  static Uint8List withCrc(List<int> first18) {
    if (first18.length != 18) {
      throw ArgumentError(
        'El protocolo Tripper requiere exactamente 18 bytes de carga útil, recibido: ${first18.length}',
      );
    }
    final crc = crc16CcittFalse(first18);
    final out = Uint8List(20);
    out.setRange(0, 18, first18);
    out[18] = (crc >> 8) & 0xFF;
    out[19] = crc & 0xFF;
    return out;
  }

  /// Construye el paquete de confirmación de PIN ingresado por el usuario (CMD 0x20).
  static Uint8List buildPinPacket(String pin) {
    final buf = Uint8List(18);
    buf[0] = 0x20;
    final pinBytes = utf8.encode(pin.trim());
    final count = pinBytes.length > 6 ? 6 : pinBytes.length;
    for (int i = 0; i < count; i++) {
      buf[1 + i] = pinBytes[i];
    }
    return withCrc(buf);
  }

  /// Construye el paquete de sincronización horaria del reloj del Tripper (CMD 0x50).
  ///
  /// - En formato 24h: hora pura (0-23).
  /// - En formato 12h: hora (1-12) con el bit 0x40 activo si es AM.
  static Uint8List buildSetTimePacket(int hour24, int minute, bool is12h) {
    final buf = Uint8List(18);
    buf[0] = 0x50;
    if (!is12h) {
      buf[1] = hour24 & 0xFF;
    } else {
      int hour12 = hour24 % 12;
      if (hour12 == 0) hour12 = 12;
      buf[1] = (hour12 | (hour24 < 12 ? 0x40 : 0x00)) & 0xFF;
    }
    buf[2] = minute & 0xFF;
    return withCrc(buf);
  }

  /// Genera el paquete de sincronización horaria con la hora actual del sistema.
  static Uint8List buildSetTimeNowPacket({bool is12h = false}) {
    final now = DateTime.now();
    return buildSetTimePacket(now.hour, now.minute, is12h);
  }

  /// Codifica una distancia en metros según la norma del Tripper:
  /// - Hasta 999 metros: valor exacto en metros y unidad 1.
  /// - A partir de 1000 metros: hectómetros (metros / 100) y unidad 2 (ej. 22.9 km = 229).
  ///
  /// Retorna una lista con: `[byteHigh, byteLow, unit]`.
  static List<int> encodeDistance(int meters) {
    final safeMeters = meters < 0 ? 0 : meters;
    int value;
    int unit;
    if (safeMeters <= 999) {
      value = safeMeters;
      unit = 1;
    } else {
      value = safeMeters ~/ 100;
      unit = 2;
    }
    final clamped = value.clamp(0, 0xFFFF);
    return [(clamped >> 8) & 0xFF, clamped & 0xFF, unit];
  }

  /// Calcula el byte de intensidad según proximidad a la maniobra (Byte [6]):
  /// Añade 1 si el modo nocturno está activo.
  static int distanceIntensity(int meters, bool night) {
    int v;
    if (meters <= 10) {
      v = 0x50;
    } else if (meters <= 20) {
      v = 0x40;
    } else if (meters <= 45) {
      v = 0x30;
    } else if (meters <= 70) {
      v = 0x20;
    } else if (meters <= 95) {
      v = 0x10;
    } else {
      v = 0x00;
    }
    return v + (night ? 1 : 0);
  }

  /// Construye los bytes de información de la línea inferior (Bytes [11-13]).
  static List<int> buildBottomInfoBytes({
    required int mode,
    int etaMinutes = -1,
    int totalDistanceMeters = -1,
    bool is12h = false,
    DateTime? now,
  }) {
    const sentinel = [0xFF, 0xFF, 0xFF];
    switch (mode) {
      case bottomTimeRemaining:
        if (etaMinutes <= 0) return sentinel;
        return [
          (etaMinutes ~/ 60).clamp(0, 23),
          (etaMinutes % 60).clamp(0, 59),
          0x00,
        ];
      case bottomArrivalTime:
        if (etaMinutes <= 0) return sentinel;
        final current = now ?? DateTime.now();
        final arrival = current.add(Duration(minutes: etaMinutes));
        if (!is12h) {
          return [arrival.hour, arrival.minute, 0x00];
        }
        int hour12 = arrival.hour % 12;
        if (hour12 == 0) hour12 = 12;
        final isPm = arrival.hour >= 12;
        return [hour12 | (isPm ? 0x80 : 0x40), arrival.minute, 0x00];
      case bottomTotalDistance:
      default:
        return totalDistanceMeters >= 0
            ? encodeDistance(totalDistanceMeters)
            : sentinel;
    }
  }


  /// Construye el paquete de navegación principal (CMD_NAVIGATE = 0x10 0x11).
  ///
  /// Campos:
  /// - `[0]=0x10, [1]=0x11`
  /// - `[2]`: Código de maniobra principal
  /// - `[3-4]`: Distancia a la maniobra
  /// - `[5]`: Unidad de distancia (1 = m, 2 = hectómetros)
  /// - `[6]`: Intensidad / indicador nocturno
  /// - `[7]`: Próxima maniobra (seta pequeña) o 0x3C (radar)
  /// - `[8-9]`: Distancia a radar (0xFFFF sin radar)
  /// - `[10]`: 0x41 (fijo)
  /// - `[11-13]`: Información inferior (distancia total o tiempo restante)
  /// - `[14-17]`: 0x00
  /// - `[18-19]`: CRC-16
  static Uint8List buildNavPacket({
    required int maneuver,
    required int distanceMeters,
    int nextManeuver = nextManeuverNone,
    int nextDistanceMeters = -1,
    List<int>? bottomInfo,
    int? byte6,
    bool nightMode = false,
  }) {
    final dist = encodeDistance(distanceMeters);
    final pkt = Uint8List(18);
    pkt[0] = 0x10;
    pkt[1] = 0x11;
    pkt[2] = maneuver & 0xFF;
    pkt[3] = dist[0];
    pkt[4] = dist[1];
    pkt[5] = dist[2];
    pkt[6] =
        (byte6 ?? distanceIntensity(distanceMeters, nightMode)) & 0xFF;
    pkt[7] = nextManeuver & 0xFF;

    final nd = nextDistanceMeters < 0
        ? 0xFFFF
        : nextDistanceMeters.clamp(0, 0xFFFE);
    pkt[8] = (nd >> 8) & 0xFF;
    pkt[9] = nd & 0xFF;

    pkt[10] = 0x41;

    final bottom = (bottomInfo != null && bottomInfo.length == 3)
        ? bottomInfo
        : const [0xFF, 0xFF, 0xFF];
    pkt[11] = bottom[0] & 0xFF;
    pkt[12] = bottom[1] & 0xFF;
    pkt[13] = bottom[2] & 0xFF;

    pkt[14] = 0x00;
    pkt[15] = 0x00;
    pkt[16] = 0x00;
    pkt[17] = 0x00;

    return withCrc(pkt);
  }

  /// Construye la pantalla de compás/brújula cuando no hay ruta activa (CMD_NAVIGATE con 0x41).
  /// Sector: 0..7 (N=0x10, NE=0x50, E=0x20, SE=0x70, S=0x40, SW=0x80, W=0x30, NW=0x60).
  static Uint8List buildCompassPacket(int sector, bool nightMode) {
    int dirValue;
    switch (sector % 8) {
      case 0:
        dirValue = 0x10; // N
        break;
      case 1:
        dirValue = 0x50; // NE
        break;
      case 2:
        dirValue = 0x20; // E
        break;
      case 3:
        dirValue = 0x70; // SE
        break;
      case 4:
        dirValue = 0x40; // S
        break;
      case 5:
        dirValue = 0x80; // SW
        break;
      case 6:
        dirValue = 0x30; // W
        break;
      default:
        dirValue = 0x60; // NW
        break;
    }

    final buf = Uint8List(18);
    buf[0] = 0x10;
    buf[1] = 0x11;
    buf[2] = 0x41;
    buf[6] = nightMode ? 0x01 : 0x00;
    buf[7] = 0xFF;
    buf[11] = 0xFF;
    buf[12] = 0xFF;
    buf[13] = 0xFF;
    buf[14] = dirValue & 0xFF;
    return withCrc(buf);
  }

  /// Mapea un [ManeuverType] normalizado al código oficial del Tripper Pod.
  static int? mapManeuverToTripperCode(
    ManeuverType maneuver, {
    int? roundaboutExit,
  }) {
    switch (maneuver) {
      case ManeuverType.straight:
        return maneuverStraight;
      case ManeuverType.left:
        return maneuverTurnLeft;
      case ManeuverType.right:
        return maneuverTurnRight;
      case ManeuverType.slightLeft:
        return maneuverSlightLeft;
      case ManeuverType.slightRight:
        return maneuverSlightRight;
      case ManeuverType.sharpLeft:
        return maneuverSharpLeft;
      case ManeuverType.sharpRight:
        return maneuverSharpRight;
      case ManeuverType.uTurn:
        return maneuverUTurnCounterClockwise;
      case ManeuverType.roundabout:
        if (roundaboutExit != null && roundaboutExit >= 1) {
          final exitClamped = roundaboutExit.clamp(1, 9);
          return 0x32 + (exitClamped - 1);
        }
        return maneuverRoundaboutBase;
      case ManeuverType.depart:
        return maneuverDepart;
      case ManeuverType.arrive:
        return maneuverDestination;
      case ManeuverType.unknown:
        return null;
    }
  }


  /// Formatea un paquete de bytes como cadena hexadecimal limpia con espacios (ej. "21 00 00 ... 40 45").
  static String toHexString(List<int> bytes) {
    return bytes
        .map((b) => (b & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
  }
}
