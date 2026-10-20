import 'coordinates.dart';
import 'maneuver_type.dart';

const Object _sentinel = Object();

/// Representa una instrucción de maniobra de navegación inmutable.
class Maneuver {
  /// Texto descriptivo de la indicación (por ejemplo, "En 200 m, gira a la derecha").
  final String instructionText;

  /// Tipo neutral de maniobra.
  final ManeuverType type;

  /// Coordenada geográfica exacta donde ocurre la maniobra.
  final Coordinates location;

  /// Distancia en metros asociada al tramo de la maniobra (opcional).
  final double? distanceMeters;

  /// Nombre de la vía hacia la que se dirige o transita (opcional).
  final String? roadName;

  /// Número de salida aplicable para glorietas o enlaces viales (opcional, >= 1).
  final int? exitNumber;

  /// Grado de certeza del proveedor sobre la maniobra (0.0 a 1.0).
  final double confidence;

  /// Crea una maniobra validando la consistencia de sus campos y métricas.
  Maneuver({
    required this.instructionText,
    required this.type,
    required this.location,
    this.distanceMeters,
    this.roadName,
    this.exitNumber,
    this.confidence = 1.0,
  }) {
    if (instructionText.trim().isEmpty) {
      throw ArgumentError.value(
        instructionText,
        'instructionText',
        'El texto de la instrucción no puede estar vacío.',
      );
    }
    if (roadName != null && roadName!.trim().isEmpty) {
      throw ArgumentError.value(
        roadName,
        'roadName',
        'El nombre de la vía no puede estar vacío si se suministra.',
      );
    }
    if (distanceMeters != null) {
      if (!distanceMeters!.isFinite) {
        throw ArgumentError.value(
          distanceMeters,
          'distanceMeters',
          'La distancia de la maniobra debe ser un número finito.',
        );
      }
      if (distanceMeters! < 0.0) {
        throw ArgumentError.value(
          distanceMeters,
          'distanceMeters',
          'La distancia de la maniobra no puede ser negativa.',
        );
      }
    }
    if (exitNumber != null && exitNumber! < 1) {
      throw ArgumentError.value(
        exitNumber,
        'exitNumber',
        'El número de salida debe ser un entero positivo mayor o igual a 1.',
      );
    }
    if (!confidence.isFinite || confidence < 0.0 || confidence > 1.0) {
      throw ArgumentError.value(
        confidence,
        'confidence',
        'El nivel de confianza debe estar comprendido entre 0.0 y 1.0.',
      );
    }
  }

  /// Crea una copia inmutable con campos modificados.
  ///
  /// Para los campos opcionales ([distanceMeters], [roadName], [exitNumber]),
  /// este método permite distinguir entre:
  /// - Conservar el valor preexistente (omitiendo el argumento o pasando el centinela por defecto).
  /// - Establecer explícitamente el campo en `null` (pasando `null` como valor).
  /// - Actualizar el campo a un nuevo valor no nulo.
  Maneuver copyWith({
    String? instructionText,
    ManeuverType? type,
    Coordinates? location,
    Object? distanceMeters = _sentinel,
    Object? roadName = _sentinel,
    Object? exitNumber = _sentinel,
    double? confidence,
  }) {
    return Maneuver(
      instructionText: instructionText ?? this.instructionText,
      type: type ?? this.type,
      location: location ?? this.location,
      distanceMeters: identical(distanceMeters, _sentinel)
          ? this.distanceMeters
          : distanceMeters as double?,
      roadName:
          identical(roadName, _sentinel) ? this.roadName : roadName as String?,
      exitNumber: identical(exitNumber, _sentinel)
          ? this.exitNumber
          : exitNumber as int?,
      confidence: confidence ?? this.confidence,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Maneuver &&
          runtimeType == other.runtimeType &&
          instructionText == other.instructionText &&
          type == other.type &&
          location == other.location &&
          distanceMeters == other.distanceMeters &&
          roadName == other.roadName &&
          exitNumber == other.exitNumber &&
          confidence == other.confidence;

  @override
  int get hashCode => Object.hash(
        instructionText,
        type,
        location,
        distanceMeters,
        roadName,
        exitNumber,
        confidence,
      );

  @override
  String toString() =>
      'Maneuver(type: $type, instruction: "$instructionText", dist: $distanceMeters m, loc: $location)';
}
