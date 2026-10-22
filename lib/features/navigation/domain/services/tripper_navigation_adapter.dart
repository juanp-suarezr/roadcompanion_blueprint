import 'dart:typed_data';

import '../../../../domain/entities/maneuver_type.dart';
import '../../../bridge/domain/entities/bridge_instruction_status.dart';
import '../../../bridge/domain/entities/bridge_navigation_instruction.dart';
import 'tripper_protocol.dart';

/// Resultado de la adaptación de una indicación de navegación externa hacia el protocolo Tripper Pod.
class TripperNavAdaptationResult {
  /// Indica si la instrucción pudo ser convertida de manera fiable a un paquete físico del Tripper.
  final bool isSupported;

  /// Paquete de 20 bytes listo para ser transmitido al hardware por BLE, o `null` si no es compatible.
  final Uint8List? packet;

  /// Motivo técnico explícito cuando la indicación no es apta o carece de campos obligatorios.
  final String description;

  /// Código de maniobra del Tripper Pod que fue seleccionado, o `null`.
  final int? tripperManeuverCode;

  /// Distancia codificada en metros, o `null`.
  final int? encodedDistanceMeters;

  const TripperNavAdaptationResult._({
    required this.isSupported,
    required this.description,
    this.packet,
    this.tripperManeuverCode,
    this.encodedDistanceMeters,
  });

  factory TripperNavAdaptationResult.success({
    required Uint8List packet,
    required int maneuverCode,
    required int distanceMeters,
    required String description,
  }) {
    return TripperNavAdaptationResult._(
      isSupported: true,
      packet: packet,
      tripperManeuverCode: maneuverCode,
      encodedDistanceMeters: distanceMeters,
      description: description,
    );
  }

  factory TripperNavAdaptationResult.incompatible({
    required String reason,
  }) {
    return TripperNavAdaptationResult._(
      isSupported: false,
      packet: null,
      description: reason,
    );
  }
}

/// Adaptador desacoplado entre las indicaciones de navegación (Waze, Google Maps o navegador propio)
/// y el protocolo binario NXP del Royal Enfield Tripper Pod.
///
/// Responsabilidades:
/// - Filtrar indicaciones incompletas, ficticias o no mapeables.
/// - Validar que la distancia y la maniobra sean datos reales confirmados por Android.
/// - Ensamblar tramas de 20 bytes con CRC-16 estricto según la especificación WazeTripper.
class TripperNavigationAdapter {
  final bool Function()? isNightModeProvider;

  const TripperNavigationAdapter({this.isNightModeProvider});

  /// Adapta una [BridgeNavigationInstruction] hacia una trama binaria del Tripper Pod.
  TripperNavAdaptationResult adaptBridgeInstruction(
    BridgeNavigationInstruction instruction, {
    int nextManeuverCode = TripperProtocol.nextManeuverNone,
    int nextDistanceMeters = -1,
    int? totalDistanceMeters,
    int? etaMinutes,
  }) {
    // 1. Verificación de estado de obsolescencia
    if (instruction.status == BridgeInstructionStatus.stale) {
      return TripperNavAdaptationResult.incompatible(
        reason:
            'Instrucción clasificada como obsoleta o descartada por el navegador de origen.',
      );
    }

    // 2. Verificación de completitud y reconocimiento
    if (!instruction.isRecognized) {
      return TripperNavAdaptationResult.incompatible(
        reason:
            'La indicación de origen no contiene una maniobra vehicular reconocida.',
      );
    }

    // 3. Verificación de distancia real entregada por el sistema
    final distance = instruction.distanceMeters;
    if (distance == null) {
      return TripperNavAdaptationResult.incompatible(
        reason:
            'La notificación externa no suministró una distancia física válida.',
      );
    }

    // 4. Mapeo del código de maniobra según la tabla de hardware del Tripper
    final maneuverCode = TripperProtocol.mapManeuverToTripperCode(
      instruction.maneuverType,
      roundaboutExit: instruction.roundaboutExit,
    );

    if (maneuverCode == null) {
      return TripperNavAdaptationResult.incompatible(
        reason:
            'La maniobra "${instruction.maneuverType.name}" no posee representación gráfica compatible en el Tripper Pod.',
      );
    }

    // 5. Determinación de modo nocturno (proveedor explícito o detección horaria)
    final bool night = isNightModeProvider != null
        ? isNightModeProvider!()
        : _isNightByDefault(instruction.receivedAt);

    // 6. Ensamblado de línea inferior
    List<int>? bottomInfo;
    if (totalDistanceMeters != null && totalDistanceMeters >= 0) {
      bottomInfo = TripperProtocol.buildBottomInfoBytes(
        mode: TripperProtocol.bottomTotalDistance,
        totalDistanceMeters: totalDistanceMeters,
      );
    } else if (etaMinutes != null && etaMinutes > 0) {
      bottomInfo = TripperProtocol.buildBottomInfoBytes(
        mode: TripperProtocol.bottomTimeRemaining,
        etaMinutes: etaMinutes,
      );
    }

    // 7. Construcción de trama CMD_NAVIGATE (20 bytes con CRC-16)
    final packet = TripperProtocol.buildNavPacket(
      maneuver: maneuverCode,
      distanceMeters: distance,
      nextManeuver: nextManeuverCode,
      nextDistanceMeters: nextDistanceMeters,
      bottomInfo: bottomInfo,
      nightMode: night,
    );

    final streetText = instruction.destinationStreet != null
        ? ' hacia "${instruction.destinationStreet}"'
        : '';
    final desc =
        'Maniobra: 0x${maneuverCode.toRadixString(16).toUpperCase()} (${instruction.maneuverType.name}), Distancia: ${distance}m$streetText, Noche: $night';

    return TripperNavAdaptationResult.success(
      packet: packet,
      maneuverCode: maneuverCode,
      distanceMeters: distance,
      description: desc,
    );
  }

  /// Adapta una maniobra directa del copiloto nativo de REStelar (cuando no se usa Waze).
  TripperNavAdaptationResult adaptNativeManeuver({
    required ManeuverType maneuverType,
    required int distanceMeters,
    int? roundaboutExit,
    int? totalDistanceMeters,
    int? etaMinutes,
  }) {
    final maneuverCode = TripperProtocol.mapManeuverToTripperCode(
      maneuverType,
      roundaboutExit: roundaboutExit,
    );

    if (maneuverCode == null) {
      return TripperNavAdaptationResult.incompatible(
        reason:
            'La maniobra "${maneuverType.name}" no está soportada por el display del Tripper Pod.',
      );
    }

    final bool night = isNightModeProvider != null
        ? isNightModeProvider!()
        : _isNightByDefault(DateTime.now());

    List<int>? bottomInfo;
    if (totalDistanceMeters != null && totalDistanceMeters >= 0) {
      bottomInfo = TripperProtocol.buildBottomInfoBytes(
        mode: TripperProtocol.bottomTotalDistance,
        totalDistanceMeters: totalDistanceMeters,
      );
    }

    final packet = TripperProtocol.buildNavPacket(
      maneuver: maneuverCode,
      distanceMeters: distanceMeters,
      bottomInfo: bottomInfo,
      nightMode: night,
    );

    return TripperNavAdaptationResult.success(
      packet: packet,
      maneuverCode: maneuverCode,
      distanceMeters: distanceMeters,
      description:
          'Navegación nativa REStelar: 0x${maneuverCode.toRadixString(16).toUpperCase()} (${maneuverType.name}), ${distanceMeters}m',
    );
  }

  bool _isNightByDefault(DateTime time) {
    final hour = time.hour;
    return hour >= 18 || hour < 6;
  }
}
