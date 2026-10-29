import '../../../../domain/entities/maneuver_type.dart';
import '../services/tripper_protocol.dart';

/// Tipos de maniobra estándar de navegación para motocicleta.
enum TripperManeuverType {
  straight,
  turnLeft,
  turnRight,
  sharpLeft,
  sharpRight,
  slightLeft,
  slightRight,
  uTurn,
  roundabout,
  depart,
  destinationReached,
  unknown,
}

/// Contenedor desacoplado de una instrucción de navegación para el Tripper Pod.
///
/// Separa la lógica de navegación vial del protocolo de transporte Bluetooth LE.
class TripperManeuverPayload {
  /// Distancia restante a la maniobra en metros.
  final int distanceMeters;

  /// Tipo de giro o maniobra a representar.
  final TripperManeuverType maneuverType;

  /// Nombre de la calle o vía del próximo giro.
  final String nextStreet;

  /// Marca de tiempo de emisión de la instrucción.
  final DateTime timestamp;

  /// Bandera explícita que declara el estado experimental de la carga útil.
  final bool isExperimental;

  const TripperManeuverPayload({
    required this.distanceMeters,
    required this.maneuverType,
    required this.nextStreet,
    required this.timestamp,
    this.isExperimental = true,
  });

  /// Crea un payload de maniobra a partir del [ManeuverType] normalizado de la app.
  factory TripperManeuverPayload.fromManeuver({
    required ManeuverType type,
    required int distanceMeters,
    String nextStreet = '',
    DateTime? timestamp,
  }) {
    TripperManeuverType mapped;
    switch (type) {
      case ManeuverType.left:
        mapped = TripperManeuverType.turnLeft;
        break;
      case ManeuverType.sharpLeft:
        mapped = TripperManeuverType.sharpLeft;
        break;
      case ManeuverType.right:
        mapped = TripperManeuverType.turnRight;
        break;
      case ManeuverType.sharpRight:
        mapped = TripperManeuverType.sharpRight;
        break;
      case ManeuverType.slightLeft:
        mapped = TripperManeuverType.slightLeft;
        break;
      case ManeuverType.slightRight:
        mapped = TripperManeuverType.slightRight;
        break;
      case ManeuverType.uTurn:
        mapped = TripperManeuverType.uTurn;
        break;
      case ManeuverType.roundabout:
        mapped = TripperManeuverType.roundabout;
        break;
      case ManeuverType.arrive:
        mapped = TripperManeuverType.destinationReached;
        break;
      case ManeuverType.depart:
        mapped = TripperManeuverType.depart;
        break;
      case ManeuverType.straight:
        mapped = TripperManeuverType.straight;
        break;
      case ManeuverType.unknown:
        mapped = TripperManeuverType.unknown;
        break;
    }
    return TripperManeuverPayload(
      distanceMeters: distanceMeters,
      maneuverType: mapped,
      nextStreet: nextStreet,
      timestamp: timestamp ?? DateTime.now(),
    );
  }

  /// Representación en texto legible para la consola de diagnóstico de ESTELA.
  String toDiagnosticString() {
    return '[MANIOBRA] Tipo: ${maneuverType.name} | Distancia: ${distanceMeters}m | Vía: "$nextStreet" | Hora: ${timestamp.toIso8601String().substring(11, 19)}';
  }

  /// Estructura de bytes tentativa basada en la referencia comunitaria WazeTripper.
  ///
  /// NOTA DE SEGURIDAD Y TRANSPARENCIA:
  /// Este paquete es una aproximación para diagnóstico. No debe enviarse sin
  /// confirmar enlace seguro previo y verificación en hardware real.
  List<int> toTentativeBytes() {
    final bytes = <int>[];
    // Byte 0: Prefijo de sincronismo comunitario (0xAA)
    bytes.add(0xAA);
    // Byte 1: Código de maniobra según mapa WazeTripper
    bytes.add(_mapManeuverCode(maneuverType));
    // Bytes 2-3: Distancia en metros (Big Endian, 16 bits)
    final clampedDist = distanceMeters.clamp(0, 65535);
    bytes.add((clampedDist >> 8) & 0xFF);
    bytes.add(clampedDist & 0xFF);
    // Byte 4: Checksum simple XOR
    int checksum = 0;
    for (final b in bytes) {
      checksum ^= b;
    }
    bytes.add(checksum);
    return bytes;
  }

  /// Indica si la maniobra tiene representación válida en el hardware Tripper Pod.
  bool get isSupported =>
      maneuverType != TripperManeuverType.unknown && distanceMeters >= 0;

  /// Genera la trama real de 20 bytes del protocolo oficial del Tripper Pod (CMD_NAVIGATE).
  List<int> toProtocolPacket({bool nightMode = false}) {
    if (!isSupported) {
      throw StateError(
        'No se puede construir trama BLE para una maniobra desconocida o sin distancia válida.',
      );
    }
    final code = _mapToProtocolManeuverCode(maneuverType);
    return TripperProtocol.buildNavPacket(
      maneuver: code,
      distanceMeters: distanceMeters,
      nightMode: nightMode,
    );
  }

  int _mapToProtocolManeuverCode(TripperManeuverType type) {
    switch (type) {
      case TripperManeuverType.straight:
        return TripperProtocol.maneuverStraight;
      case TripperManeuverType.turnLeft:
        return TripperProtocol.maneuverTurnLeft;
      case TripperManeuverType.turnRight:
        return TripperProtocol.maneuverTurnRight;
      case TripperManeuverType.sharpLeft:
        return TripperProtocol.maneuverSharpLeft;
      case TripperManeuverType.sharpRight:
        return TripperProtocol.maneuverSharpRight;
      case TripperManeuverType.slightLeft:
        return TripperProtocol.maneuverSlightLeft;
      case TripperManeuverType.slightRight:
        return TripperProtocol.maneuverSlightRight;
      case TripperManeuverType.uTurn:
        return TripperProtocol.maneuverUTurnCounterClockwise;
      case TripperManeuverType.roundabout:
        return TripperProtocol.maneuverRoundaboutBase;
      case TripperManeuverType.depart:
        return TripperProtocol.maneuverDepart;
      case TripperManeuverType.destinationReached:
        return TripperProtocol.maneuverDestination;
      case TripperManeuverType.unknown:
        throw StateError('TripperManeuverType.unknown no tiene opcode BLE.');
    }
  }

  int _mapManeuverCode(TripperManeuverType type) {
    switch (type) {
      case TripperManeuverType.straight:
      case TripperManeuverType.depart:
        return 0x01;
      case TripperManeuverType.turnLeft:
      case TripperManeuverType.sharpLeft:
        return 0x02;
      case TripperManeuverType.turnRight:
      case TripperManeuverType.sharpRight:
        return 0x03;
      case TripperManeuverType.slightLeft:
        return 0x04;
      case TripperManeuverType.slightRight:
        return 0x05;
      case TripperManeuverType.uTurn:
        return 0x06;
      case TripperManeuverType.roundabout:
        return 0x07;
      case TripperManeuverType.destinationReached:
        return 0x08;
      case TripperManeuverType.unknown:
        return 0x00;
    }
  }
}
