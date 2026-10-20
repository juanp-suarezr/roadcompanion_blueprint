import '../../../../domain/entities/coordinates.dart';
import 'gpx_segment.dart';

/// Representa una ruta geográfica importada desde un archivo GPX.
///
/// Encapsula la colección de segmentos, puntos y metadatos extraídos de
/// un archivo GPX válido. Mantiene la separación estricta entre la distancia
/// geográfica ortodrómica (Haversine acumulado por segmento) y la distancia vial
/// calculada por un motor de rutas.
class ImportedGpxRoute {
  /// Nombre descriptivo del recorrido o del archivo de origen.
  final String name;

  /// Segmentos ordenados que componen el recorrido.
  final List<GpxSegment> segments;

  /// Distancia geográfica total en metros calculada sumando las distancias
  /// intra-segmento mediante la fórmula de Haversine.
  final double totalGeographicDistanceMeters;

  /// Cantidad total de puntos geográficos contenidos en todos los segmentos.
  final int totalPoints;

  /// Elevación mínima registrada en metros sobre el nivel del mar, si existe.
  final double? minElevation;

  /// Elevación máxima registrada en metros sobre el nivel del mar, si existe.
  final double? maxElevation;

  /// Lista aplanada de todas las coordenadas de la ruta.
  final List<Coordinates> allCoordinates;

  ImportedGpxRoute._({
    required this.name,
    required this.segments,
    required this.totalGeographicDistanceMeters,
    required this.totalPoints,
    required this.minElevation,
    required this.maxElevation,
    required this.allCoordinates,
  });

  /// Crea una ruta importada a partir de sus segmentos y nombre, calculando
  /// de forma determinista la distancia geográfica y las métricas de elevación.
  ///
  /// Lanza [ArgumentError] si no contiene al menos un punto utilizable.
  factory ImportedGpxRoute({
    required String name,
    required List<GpxSegment> segments,
  }) {
    final cleanedName = name.trim().isNotEmpty ? name.trim() : 'Ruta GPX';
    final nonNullSegments = List<GpxSegment>.unmodifiable(segments);

    double totalDist = 0.0;
    int pointCount = 0;
    double? minEle;
    double? maxEle;
    final coords = <Coordinates>[];

    for (final seg in nonNullSegments) {
      totalDist += seg.calculateDistanceMeters();
      pointCount += seg.length;
      for (final pt in seg.points) {
        coords.add(pt.coordinates);
        if (pt.elevation != null && pt.elevation!.isFinite) {
          final ele = pt.elevation!;
          minEle = (minEle == null || ele < minEle) ? ele : minEle;
          maxEle = (maxEle == null || ele > maxEle) ? ele : maxEle;
        }
      }
    }

    if (pointCount == 0) {
      throw ArgumentError.value(
        segments,
        'segments',
        'La ruta GPX debe contener al menos un punto geográfico utilizable.',
      );
    }

    return ImportedGpxRoute._(
      name: cleanedName,
      segments: nonNullSegments,
      totalGeographicDistanceMeters: totalDist,
      totalPoints: pointCount,
      minElevation: minEle,
      maxElevation: maxEle,
      allCoordinates: List.unmodifiable(coords),
    );
  }

  /// Primer punto geográfico del recorrido.
  Coordinates get origin => allCoordinates.first;

  /// Último punto geográfico del recorrido.
  Coordinates get destination => allCoordinates.last;

  /// Representación en kilómetros para visualización.
  double get totalDistanceKm => totalGeographicDistanceMeters / 1000.0;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ImportedGpxRoute || runtimeType != other.runtimeType) {
      return false;
    }
    if (name != other.name ||
        totalPoints != other.totalPoints ||
        totalGeographicDistanceMeters != other.totalGeographicDistanceMeters ||
        minElevation != other.minElevation ||
        maxElevation != other.maxElevation ||
        segments.length != other.segments.length) {
      return false;
    }
    for (int i = 0; i < segments.length; i++) {
      if (segments[i] != other.segments[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    name,
    totalGeographicDistanceMeters,
    totalPoints,
    minElevation,
    maxElevation,
    Object.hashAll(segments),
  );

  @override
  String toString() =>
      'ImportedGpxRoute(name: $name, points: $totalPoints, distance: ${totalDistanceKm.toStringAsFixed(2)} km, segments: ${segments.length})';
}
