import '../../../../domain/entities/maneuver_type.dart';
import 'bridge_instruction_status.dart';
import 'bridge_source_type.dart';

const Object _sentinel = Object();

/// Representación inmutable de una instrucción de navegación normalizada en ESTELA Bridge.
///
/// Encapsula datos provenientes de fuentes externas (como Google Maps o Waze)
/// o de simulación, preservando el texto original crudo para auditoría y
/// clasificando rigurosamente su estado de validez antes de ser considerada
/// apta para el hardware Tripper Pod.
class BridgeNavigationInstruction {
  /// Origen o proveedor de la instrucción.
  final BridgeSourceType source;

  /// Tipo de maniobra estandarizado. Si no se reconoció, es [ManeuverType.unknown].
  final ManeuverType maneuverType;

  /// Distancia restante a la maniobra en metros, o `null` si no está disponible.
  /// No se inventan distancias arbitrarias.
  final int? distanceMeters;

  /// Fragmento textual original que contenía la distancia (ej. "400 m", "1,2 km", "1.2 km").
  final String? rawDistanceText;

  /// Texto completo original recibido de la notificación o mensaje de entrada.
  final String rawText;

  /// Título de la notificación si fue suministrado de forma separada.
  final String? rawTitle;

  /// Nombre de la calle o vía hacia la que se dirige la maniobra, si se detectó.
  final String? destinationStreet;

  /// Número de salida aplicable para glorietas / rotondas (1 a 8), o `null`.
  final int? roundaboutExit;

  /// Marca de tiempo exacta en que ESTELA Bridge recibió o procesó la indicación.
  final DateTime receivedAt;

  /// Estado de clasificación y completitud de la instrucción.
  final BridgeInstructionStatus status;

  const BridgeNavigationInstruction({
    required this.source,
    required this.maneuverType,
    required this.rawText,
    required this.receivedAt,
    required this.status,
    this.distanceMeters,
    this.rawDistanceText,
    this.rawTitle,
    this.destinationStreet,
    this.roundaboutExit,
  });

  /// Indica si la instrucción fue plenamente reconocida y sus datos son válidos.
  bool get isRecognized => status == BridgeInstructionStatus.recognized;

  /// Indica si la indicación contiene datos de navegación pero la maniobra es ambigua o parcial.
  bool get isIncomplete => status == BridgeInstructionStatus.incomplete;

  /// Indica si el texto recibido no corresponde a una maniobra válida.
  bool get isUnrecognized => status == BridgeInstructionStatus.unrecognized;

  /// Indica si la instrucción ha sido explícitamente marcada como obsoleta.
  bool get isStale => status == BridgeInstructionStatus.stale;

  /// Evalúa si la instrucción ha superado el tiempo máximo de frescura sin actualización.
  bool isExpired({
    Duration maxAge = const Duration(seconds: 45),
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    return current.difference(receivedAt) > maxAge;
  }

  /// Retorna una nueva instancia marcada con el estado [BridgeInstructionStatus.stale].
  BridgeNavigationInstruction asStale() {
    return copyWith(status: BridgeInstructionStatus.stale);
  }

  /// Crea una copia inmutable permitiendo actualizar atributos seleccionados.
  BridgeNavigationInstruction copyWith({
    BridgeSourceType? source,
    ManeuverType? maneuverType,
    Object? distanceMeters = _sentinel,
    Object? rawDistanceText = _sentinel,
    String? rawText,
    Object? rawTitle = _sentinel,
    Object? destinationStreet = _sentinel,
    Object? roundaboutExit = _sentinel,
    DateTime? receivedAt,
    BridgeInstructionStatus? status,
  }) {
    return BridgeNavigationInstruction(
      source: source ?? this.source,
      maneuverType: maneuverType ?? this.maneuverType,
      distanceMeters: identical(distanceMeters, _sentinel)
          ? this.distanceMeters
          : distanceMeters as int?,
      rawDistanceText: identical(rawDistanceText, _sentinel)
          ? this.rawDistanceText
          : rawDistanceText as String?,
      rawText: rawText ?? this.rawText,
      rawTitle: identical(rawTitle, _sentinel)
          ? this.rawTitle
          : rawTitle as String?,
      destinationStreet: identical(destinationStreet, _sentinel)
          ? this.destinationStreet
          : destinationStreet as String?,
      roundaboutExit: identical(roundaboutExit, _sentinel)
          ? this.roundaboutExit
          : roundaboutExit as int?,
      receivedAt: receivedAt ?? this.receivedAt,
      status: status ?? this.status,
    );
  }

  /// Resumen para registros de diagnóstico sin exponer datos personales.
  String toDiagnosticString() {
    final dist = distanceMeters != null ? '${distanceMeters}m' : 'sin_dist';
    final exit = roundaboutExit != null ? ' (Salida $roundaboutExit)' : '';
    final street = destinationStreet != null ? ' -> "$destinationStreet"' : '';
    return '[BRIDGE ${source.displayName}] ${status.name.toUpperCase()} | '
        'Maniobra: ${maneuverType.name}$exit | Distancia: $dist | '
        'Vía: $street | Hora: ${receivedAt.toIso8601String().substring(11, 19)}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BridgeNavigationInstruction &&
          runtimeType == other.runtimeType &&
          source == other.source &&
          maneuverType == other.maneuverType &&
          distanceMeters == other.distanceMeters &&
          rawDistanceText == other.rawDistanceText &&
          rawText == other.rawText &&
          rawTitle == other.rawTitle &&
          destinationStreet == other.destinationStreet &&
          roundaboutExit == other.roundaboutExit &&
          receivedAt == other.receivedAt &&
          status == other.status;

  @override
  int get hashCode => Object.hash(
    source,
    maneuverType,
    distanceMeters,
    rawDistanceText,
    rawText,
    rawTitle,
    destinationStreet,
    roundaboutExit,
    receivedAt,
    status,
  );

  @override
  String toString() =>
      'BridgeNavigationInstruction(${source.name}, ${maneuverType.name}, '
      'dist: $distanceMeters, status: ${status.name}, text: "$rawText")';
}
