import '../../../../domain/entities/coordinates.dart';
import 'trip_stop.dart';
import 'trip_stop_type.dart';

/// Representación inmutable de un punto de interés (POI) ubicado a lo largo del corredor de una ruta vial.
///
/// Encapsula la distancia perpendicular (cross-track) a la calzada, la distancia recorrida
/// acumulada desde el origen donde se sitúa la proyección, el desvío aproximado para acceder a él,
/// y si los datos de OSM contienen atributos parciales o incompletos.
class RoutePoi {
  /// Identificador único del POI (ej. `osm_node_12345678`).
  final String id;

  /// Nombre del establecimiento o punto de interés.
  final String name;

  /// Clave de categoría de búsqueda (ej. `fuel`, `motorcycle_repair`, `restaurant`, `viewpoint`, `hairdresser`).
  final String category;

  /// Tipo de parada normalizado para itinerarios de REstelar.
  final TripStopType type;

  /// Coordenada geográfica del POI.
  final Coordinates coordinates;

  /// Distancia ortogonal (perpendicular / cross-track) aproximada desde la calzada de la ruta hasta el POI en metros.
  /// ADVERTENCIA: Esta es una métrica perpendicular a la geometría del trazado y NO debe presentarse como distancia por carretera.
  final double distanceToRouteMeters;

  /// Distancia acumulada a lo largo del trazado vial desde el punto de partida (origen)
  /// hasta el punto más cercano de la ruta que proyecta hacia este POI.
  final double distanceAlongRouteMeters;

  /// Estimación teórica fundada del desvío adicional de ida y vuelta para visitar el POI desde el recorrido
  /// (~2 * distancia perpendicular).
  /// ADVERTENCIA: Esta es una aproximación geométrica teórica lineal (no vial) y NO representa una ruta vial por carretera.
  final double estimatedDetourMeters;

  /// Distancia real por carretera del desvío calculada mediante ruteo vial OSRM (opcional).
  /// Permanece null si no se ha ejecutado un cálculo de ruteo explícito para este POI.
  final double? roadDetourMeters;

  /// Dirección o datos de ubicación descriptiva (calle, municipio).
  final String subtitle;

  /// Indica si el POI carece de nombre propio oficial o detalles completos en OpenStreetMap.
  final bool hasIncompleteData;

  const RoutePoi({
    required this.id,
    required this.name,
    required this.category,
    required this.type,
    required this.coordinates,
    required this.distanceToRouteMeters,
    required this.distanceAlongRouteMeters,
    required this.estimatedDetourMeters,
    this.roadDetourMeters,
    this.subtitle = '',
    this.hasIncompleteData = false,
  });

  /// Indica si se dispone de una medición real por carretera del desvío calculada por el motor vial.
  bool get hasRoadDetour => roadDetourMeters != null;

  /// Aproximación geométrica teórica (2 × distancia perpendicular).
  double get theoreticalGeometricDetourMeters => distanceToRouteMeters * 2.0;

  /// Convierte este POI en una parada intermedia [TripStop] para integrarla al itinerario.
  TripStop toTripStop({required int orderIndex}) {
    // Normalizar ID seguro alfanumérico
    final safeId = id.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    return TripStop(
      id: 'poi_${safeId}_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      coordinates: coordinates,
      type: type,
      orderIndex: orderIndex,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoutePoi && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'RoutePoi($name, cat: $category, distToRoute: ${distanceToRouteMeters.toStringAsFixed(1)}m, alongRoute: ${(distanceAlongRouteMeters / 1000).toStringAsFixed(1)}km)';
}
