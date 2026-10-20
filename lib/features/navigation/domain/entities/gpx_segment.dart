import 'gpx_point.dart';

/// Representa un segmento continuo e inmutable de puntos en una ruta GPX.
///
/// Un segmento agrupa un tramo continuo de recorrido donde los puntos
/// consecutivos están conectados cronológica y espacialmente.
/// La distancia geográfica se calcula estrictamente entre puntos consecutivos
/// dentro de este segmento, evitando saltos artificiales entre segmentos distintos.
class GpxSegment {
  /// Lista inmutable de puntos ordenados que componen este segmento.
  final List<GpxPoint> points;

  GpxSegment(List<GpxPoint> points) : points = List.unmodifiable(points);

  /// Indica si el segmento no contiene puntos.
  bool get isEmpty => points.isEmpty;

  /// Indica si el segmento contiene al menos un punto.
  bool get isNotEmpty => points.isNotEmpty;

  /// Cantidad de puntos en el segmento.
  int get length => points.length;

  /// Calcula la distancia acumulada en metros sobre la polilínea del segmento
  /// sumando las distancias de gran círculo (Haversine) entre vértices contiguos.
  double calculateDistanceMeters() {
    if (points.length < 2) return 0.0;

    double total = 0.0;
    for (int i = 0; i < points.length - 1; i++) {
      total += points[i].coordinates.distanceTo(points[i + 1].coordinates);
    }
    return total;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! GpxSegment || runtimeType != other.runtimeType) return false;
    if (points.length != other.points.length) return false;
    for (int i = 0; i < points.length; i++) {
      if (points[i] != other.points[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(points);

  @override
  String toString() => 'GpxSegment(points: ${points.length})';
}
