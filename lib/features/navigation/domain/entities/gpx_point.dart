import '../../../../domain/entities/coordinates.dart';

/// Representa un punto geográfico inmutable dentro de un recorrido GPX.
///
/// Encapsula la coordenada geográfica estricta ([Coordinates]), junto con
/// la elevación opcional en metros y la marca temporal si está presente.
class GpxPoint {
  /// Coordenada geográfica validada (WGS84).
  final Coordinates coordinates;

  /// Elevación sobre el nivel del mar en metros (opcional).
  final double? elevation;

  /// Marca de tiempo UTC registrada para el punto (opcional).
  final DateTime? time;

  const GpxPoint({required this.coordinates, this.elevation, this.time});

  /// Acceso directo a la latitud del punto.
  double get latitude => coordinates.latitude;

  /// Acceso directo a la longitud del punto.
  double get longitude => coordinates.longitude;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GpxPoint &&
          runtimeType == other.runtimeType &&
          coordinates == other.coordinates &&
          elevation == other.elevation &&
          time == other.time;

  @override
  int get hashCode => Object.hash(coordinates, elevation, time);

  @override
  String toString() =>
      'GpxPoint(coords: $coordinates, ele: $elevation, time: $time)';
}
