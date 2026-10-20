import '../../../../domain/entities/coordinates.dart';
import '../../../../domain/entities/route_plan.dart';

/// Representa una ruta cartográfica calculada por un motor de routing en tiempo real.
class CalculatedRoute {
  /// Plan de ruta de dominio con la geometría vial, distancia y pasos de maniobra.
  final RoutePlan routePlan;

  /// Resumen textual del trayecto (ej. "por Autopista del Café y Vía Honda").
  final String summary;

  const CalculatedRoute({
    required this.routePlan,
    required this.summary,
  });

  /// Coordenada de origen del recorrido.
  Coordinates get origin => routePlan.origin;

  /// Coordenada de destino final del recorrido.
  Coordinates get destination => routePlan.destination;

  /// Tiempo estimado de viaje.
  Duration get estimatedDuration => routePlan.estimatedDuration;

  /// Distancia total en kilómetros.
  double get totalDistanceKm => routePlan.totalDistanceMeters / 1000.0;

  /// Geometría completa de la ruta.
  List<Coordinates> get geometry => routePlan.geometry;

  /// Tiempo estimado formateado (ej. "1 h 24 min" o "42 min").
  String get formattedDuration {
    final hours = estimatedDuration.inHours;
    final minutes = estimatedDuration.inMinutes.remainder(60);
    if (hours > 0) {
      return '$hours h ${minutes.toString().padLeft(2, '0')} min';
    }
    return '$minutes min';
  }

  @override
  String toString() =>
      'CalculatedRoute($summary, ${totalDistanceKm.toStringAsFixed(1)} km, $formattedDuration)';
}
