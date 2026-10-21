import '../../../../domain/entities/coordinates.dart';
import '../../../../domain/entities/route_plan.dart';
import '../services/route_integrity_validator.dart';

/// Representa una ruta cartográfica calculada por un motor de routing en tiempo real,
/// con soporte para alternativas de recorrido y validación de seguridad vial.
class CalculatedRoute {
  /// Plan de ruta de dominio con la geometría vial, distancia y pasos de maniobra.
  final RoutePlan routePlan;

  /// Resumen textual del trayecto (ej. "por Autopista del Café").
  final String summary;

  /// Nombre identificador de la alternativa (ej. "Ruta 1", "Ruta 2", "Ruta 3").
  final String routeName;

  /// Resultado de validación de integridad geométrica, aproximación y restricciones.
  final RouteValidationResult validation;

  /// Indica si esta opción es la más rápida entre las alternativas disponibles.
  final bool isFastest;

  /// Indica si esta opción es la más corta en distancia entre las alternativas disponibles.
  final bool isShortest;

  /// Indica si esta opción ofrece una relación equilibrada entre distancia y tiempo en vías principales.
  final bool isBalanced;

  /// Indica si esta opción es la preferida por el motociclista según sus preferencias y memoria vial.
  final bool isPreferred;

  /// Diferencia de distancia en km con respecto a la ruta más corta (ej. +2.4 km).
  final double? distanceDiffKm;

  /// Diferencia de tiempo con respecto a la ruta más rápida (ej. +5 min).
  final Duration? durationDiff;

  /// Lista de rutas alternativas asociadas a este cálculo.
  final List<CalculatedRoute> alternatives;

  const CalculatedRoute({
    required this.routePlan,
    required this.summary,
    this.routeName = 'Ruta 1',
    this.validation = const RouteValidationResult(
      status: RouteValidationStatus.viable,
    ),
    this.isFastest = false,
    this.isShortest = false,
    this.isBalanced = false,
    this.isPreferred = false,
    this.distanceDiffKm,
    this.durationDiff,
    this.alternatives = const [],
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

  /// Indica si la ruta es transitable por el público general (sin restricciones de acceso confirmadas).
  bool get isPubliclyPassable => validation.isPubliclyPassable;

  /// Indica si se confirmó que la ruta cruza vías privadas o restringidas con portón/cerrojo.
  bool get isConfirmedRestricted => validation.isConfirmedRestricted;

  /// Indica si no hay información cartográfica suficiente para confirmar el acceso.
  bool get hasUnconfirmedTransitability =>
      validation.hasUnconfirmedTransitability;

  /// Indica si la calzada vehicular finaliza lejos del destino (> 300 m).
  bool get hasDestinationGap => validation.hasDestinationGap;

  /// Crea una copia de la ruta con atributos de comparación actualizados.
  CalculatedRoute copyWith({
    String? routeName,
    String? summary,
    bool? isFastest,
    bool? isShortest,
    bool? isBalanced,
    bool? isPreferred,
    double? distanceDiffKm,
    Duration? durationDiff,
    List<CalculatedRoute>? alternatives,
    RouteValidationResult? validation,
  }) {
    return CalculatedRoute(
      routePlan: routePlan,
      summary: summary ?? this.summary,
      routeName: routeName ?? this.routeName,
      validation: validation ?? this.validation,
      isFastest: isFastest ?? this.isFastest,
      isShortest: isShortest ?? this.isShortest,
      isBalanced: isBalanced ?? this.isBalanced,
      isPreferred: isPreferred ?? this.isPreferred,
      distanceDiffKm: distanceDiffKm ?? this.distanceDiffKm,
      durationDiff: durationDiff ?? this.durationDiff,
      alternatives: alternatives ?? this.alternatives,
    );
  }

  @override
  String toString() =>
      'CalculatedRoute($routeName: $summary, ${totalDistanceKm.toStringAsFixed(1)} km, $formattedDuration)';
}
