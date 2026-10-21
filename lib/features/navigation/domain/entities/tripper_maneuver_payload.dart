/// Tipos de maniobra estándar de navegación para motocicleta.
enum TripperManeuverType {
  straight,
  turnLeft,
  turnRight,
  slightLeft,
  slightRight,
  uTurn,
  roundabout,
  destinationReached,
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

  int _mapManeuverCode(TripperManeuverType type) {
    switch (type) {
      case TripperManeuverType.straight:
        return 0x01;
      case TripperManeuverType.turnLeft:
        return 0x02;
      case TripperManeuverType.turnRight:
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
    }
  }
}
