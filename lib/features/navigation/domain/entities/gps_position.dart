import '../../../../domain/entities/coordinates.dart';

/// Representa una lectura posicional inmutable capturada por el sensor GPS del dispositivo.
///
/// Distingue estrictamente entre velocidad disponible y ausencia de medición
/// (un valor nulo de velocidad NO debe interpretarse como 0 km/h).
class GpsPosition {
  /// Coordenada geográfica validada (WGS84).
  final Coordinates coordinates;

  /// Precisión estimada en radio horizontal en metros (1-sigma).
  final double accuracyMeters;

  /// Altitud sobre el nivel del mar en metros (opcional).
  final double? altitudeMeters;

  /// Velocidad instantánea sobre el terreno en metros por segundo (opcional).
  final double? speedMps;

  /// Rumbo o dirección de desplazamiento en grados [0.0, 360.0) respecto al norte verdadero.
  final double? headingDegrees;

  /// Marca de tiempo UTC registrada por el proveedor satelital o sensor.
  final DateTime timestamp;

  const GpsPosition({
    required this.coordinates,
    required this.accuracyMeters,
    this.altitudeMeters,
    this.speedMps,
    this.headingDegrees,
    required this.timestamp,
  });

  /// Indica si el sensor suministró una medición válida de velocidad.
  bool get hasSpeed => speedMps != null && speedMps! >= 0.0;

  /// Velocidad en kilómetros por hora (km/h), o `null` si no está disponible.
  double? get speedKmh => hasSpeed ? (speedMps! * 3.6) : null;

  /// Antigüedad transcurrida desde la captura de la lectura respecto a [currentTime].
  Duration age(DateTime currentTime) => currentTime.difference(timestamp);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GpsPosition &&
          runtimeType == other.runtimeType &&
          coordinates == other.coordinates &&
          accuracyMeters == other.accuracyMeters &&
          speedMps == other.speedMps &&
          timestamp == other.timestamp;

  @override
  int get hashCode =>
      Object.hash(coordinates, accuracyMeters, speedMps, timestamp);

  @override
  String toString() =>
      'GpsPosition(coords: $coordinates, acc: ±${accuracyMeters.toStringAsFixed(1)}m, speed: ${speedKmh?.toStringAsFixed(1)}km/h)';
}
