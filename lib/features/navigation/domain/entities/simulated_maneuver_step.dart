import 'dart:typed_data';

import '../../../../domain/entities/maneuver.dart';
import '../services/tripper_protocol.dart';

/// Representa un paso determinista dentro del escenario de simulación de navegación.
///
/// Distingue explícitamente entre la semántica vehicular de la maniobra simulada
/// y su compatibilidad física con el hardware del Tripper Pod.
class SimulatedManeuverStep {
  /// Número ordinal del paso (1-based para claridad del usuario).
  final int stepNumber;

  /// Maniobra vehicular simulada en el dominio.
  final Maneuver maneuver;

  /// Distancia inicial asignada al paso en metros.
  final int initialDistanceMeters;

  /// Indica si la maniobra cuenta con un código binario verificado en el hardware del Tripper.
  final bool isSupportedByTripper;

  /// Código de maniobra del Tripper Pod (Byte [2]), o null si no está soportado.
  final int? tripperManeuverCode;

  /// Explicación técnica de la compatibilidad o limitación.
  final String compatibilityNote;

  const SimulatedManeuverStep({
    required this.stepNumber,
    required this.maneuver,
    required this.initialDistanceMeters,
    required this.isSupportedByTripper,
    this.tripperManeuverCode,
    required this.compatibilityNote,
  });

  /// Construye un paquete binario de 20 bytes con CRC-16 para la distancia especificada.
  /// Retorna `null` si la maniobra no es compatible con el hardware.
  Uint8List? buildProtocolPacket({
    required int distanceMeters,
    bool nightMode = false,
    int nextManeuver = TripperProtocol.nextManeuverNone,
    int nextDistanceMeters = -1,
  }) {
    if (!isSupportedByTripper || tripperManeuverCode == null) {
      return null;
    }
    return TripperProtocol.buildNavPacket(
      maneuver: tripperManeuverCode!,
      distanceMeters: distanceMeters,
      nightMode: nightMode,
      nextManeuver: nextManeuver,
      nextDistanceMeters: nextDistanceMeters,
    );
  }
}
