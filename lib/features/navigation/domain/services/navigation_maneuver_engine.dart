import '../../../../domain/entities/coordinates.dart';
import '../../../../domain/entities/maneuver.dart';
import '../../../../domain/entities/maneuver_type.dart';
import '../../../../domain/entities/route_progress.dart';
import '../../../../domain/services/route_progress_calculator.dart';
import '../entities/calculated_route.dart';

/// Información del paso de navegación actual y próximo para la interfaz y voz.
class NavigationManeuverStep {
  /// Maniobra que el usuario debe ejecutar a continuación.
  final Maneuver activeManeuver;

  /// Maniobra subsiguiente (si existe) para avisos encadenados.
  final Maneuver? nextManeuver;

  /// Distancia real restante por carretera hasta el punto de la maniobra en metros.
  final double distanceToManeuverMeters;

  /// Distancia real restante hasta el próximo hito vial o cruce intermedio en metros.
  final double? distanceToMilestoneMeters;

  /// Distancia total restante hasta el destino final en metros.
  final double? totalRemainingDistanceMeters;

  /// Índice de la maniobra activa en la lista de maniobras de la ruta.
  final int maneuverIndex;

  /// Indica si es la última maniobra del recorrido (llegada al destino).
  final bool isLastManeuver;

  /// Indica si el paso actual corresponde a mantenimiento en calzada recta prolongada.
  final bool isHighwayStraightContinuation;

  const NavigationManeuverStep({
    required this.activeManeuver,
    this.nextManeuver,
    required this.distanceToManeuverMeters,
    this.distanceToMilestoneMeters,
    this.totalRemainingDistanceMeters,
    required this.maneuverIndex,
    required this.isLastManeuver,
    this.isHighwayStraightContinuation = false,
  });
}

/// Motor de dominio puro para indexar maniobras sobre la geometría de la ruta
/// y determinar con precisión métrica la próxima maniobra y la distancia real a ella.
class NavigationManeuverEngine {
  final RouteProgressCalculator _calculator;
  CalculatedRoute? _route;
  final List<double> _cumulativeDistances = [];
  final List<double> _maneuverDistancesAlongRoute = [];
  NavigationManeuverStep? _lastResolvedStep;

  NavigationManeuverEngine({
    RouteProgressCalculator calculator = const RouteProgressCalculator(),
  }) : _calculator = calculator;

  CalculatedRoute? get currentRoute => _route;
  NavigationManeuverStep? get lastResolvedStep => _lastResolvedStep;

  /// Configura la ruta y precalcula las distancias acumuladas a lo largo de la calzada.
  void setRoute(CalculatedRoute route) {
    _route = route;
    _cumulativeDistances.clear();
    _maneuverDistancesAlongRoute.clear();

    final geometry = route.geometry;
    if (geometry.isEmpty) return;

    // 1. Distancias acumuladas de cada vértice geométrico
    _cumulativeDistances.add(0.0);
    double accumulated = 0.0;
    for (int i = 1; i < geometry.length; i++) {
      accumulated += geometry[i - 1].distanceTo(geometry[i]);
      _cumulativeDistances.add(accumulated);
    }

    // 2. Asociar cada maniobra a su posición acumulada a lo largo de la ruta
    final maneuvers = route.routePlan.maneuvers;
    for (int m = 0; m < maneuvers.length; m++) {
      final maneuver = maneuvers[m];
      final distAlong = _findDistanceAlongRoute(maneuver.location, geometry);
      _maneuverDistancesAlongRoute.add(distAlong);
    }
  }

  /// Encuentra la distancia acumulada de una coordenada a lo largo de la geometría.
  double _findDistanceAlongRoute(
    Coordinates point,
    List<Coordinates> geometry,
  ) {
    if (geometry.isEmpty) return 0.0;
    if (geometry.length == 1) return 0.0;

    try {
      final totalDist = _cumulativeDistances.isNotEmpty
          ? _cumulativeDistances.last
          : null;
      final progress = _calculator.calculate(
        geometry: geometry,
        currentPosition: point,
        totalDistanceMeters: totalDist,
      );
      return progress.distanceTraveledMeters;
    } catch (_) {
      // Fallback a distancia directa si la proyección sobre segmentos falla
      int bestSegment = 0;
      double bestDistToSegment = double.infinity;

      for (int i = 0; i < geometry.length - 1; i++) {
        final d = point.distanceTo(geometry[i]);
        if (d < bestDistToSegment) {
          bestDistToSegment = d;
          bestSegment = i;
        }
      }

      final baseDist =
          _cumulativeDistances.isNotEmpty &&
              bestSegment < _cumulativeDistances.length
          ? _cumulativeDistances[bestSegment]
          : 0.0;
      final offset = geometry[bestSegment].distanceTo(point);
      return baseDist + offset;
    }
  }

  /// Resuelve la maniobra activa y la distancia métrica restante a ella
  /// a partir de la posición GPS actual del motociclista o el progreso calculado.
  ///
  /// En tramos de carretera nacional donde el próximo giro se encuentra a más de
  /// [highwayStraightThresholdMeters] (por defecto 1500 m), sintetiza un paso de
  /// continuidad recta hacia ese hito, asegurando que la flecha permanezca recta
  /// con distancia decreciente real sin inventar metros ni confundir al conductor.
  NavigationManeuverStep? resolveStep({
    required Coordinates currentCoordinates,
    RouteProgress? progress,
    double highwayStraightThresholdMeters = 1500.0,
  }) {
    if (_route == null || _route!.routePlan.maneuvers.isEmpty) {
      return null;
    }

    final maneuvers = _route!.routePlan.maneuvers;
    if (_maneuverDistancesAlongRoute.length != maneuvers.length) {
      return null;
    }

    // Distancia recorrida por el motociclista a lo largo de la ruta
    final double riderDistAlongRoute;
    if (progress != null) {
      riderDistAlongRoute = progress.distanceTraveledMeters;
    } else {
      riderDistAlongRoute = _findDistanceAlongRoute(
        currentCoordinates,
        _route!.geometry,
      );
    }

    // Buscar la primera maniobra que esté por delante del motociclista
    // Se utiliza una tolerancia de -20 metros para no descartar el giro mientras se ejecuta
    int activeIdx = -1;
    for (int i = 0; i < maneuvers.length; i++) {
      final maneuverDist = _maneuverDistancesAlongRoute[i];
      // Si el punto de la maniobra está por delante (o hasta 20m atrás durante el giro)
      if (maneuverDist >= riderDistAlongRoute - 20.0) {
        activeIdx = i;
        break;
      }
    }

    // Si ya superó todas las maniobras intermedias, la activa es la última (llegada)
    if (activeIdx == -1) {
      activeIdx = maneuvers.length - 1;
    }

    final activeManeuver = maneuvers[activeIdx];
    final double rawDistance =
        _maneuverDistancesAlongRoute[activeIdx] - riderDistAlongRoute;
    final double distanceToManeuver = rawDistance > 0.0
        ? rawDistance
        : currentCoordinates.distanceTo(activeManeuver.location);

    final nextManeuver = (activeIdx + 1 < maneuvers.length)
        ? maneuvers[activeIdx + 1]
        : null;

    final totalRemainingDist = _route != null && _cumulativeDistances.isNotEmpty
        ? (_cumulativeDistances.last - riderDistAlongRoute).clamp(
            0.0,
            _cumulativeDistances.last,
          )
        : null;

    final bool isTurnManeuver =
        activeManeuver.type != ManeuverType.straight &&
        activeManeuver.type != ManeuverType.depart &&
        activeManeuver.type != ManeuverType.arrive;

    // Si la próxima maniobra está a más del umbral de anticipación (ej. > 1500 m en carretera),
    // o si es la llegada a destino a gran distancia, estructurar la instrucción como
    // mantenimiento recto hacia ese hito para que el display muestre flecha recta con
    // distancia decreciente real sin alarmar al conductor prematuramente con giros lejanos.
    final bool shouldShowStraightContinuation =
        (isTurnManeuver &&
            distanceToManeuver > highwayStraightThresholdMeters) ||
        (activeIdx == maneuvers.length - 1 &&
            activeManeuver.type == ManeuverType.arrive &&
            distanceToManeuver > highwayStraightThresholdMeters);

    if (shouldShowStraightContinuation) {
      final roadName =
          activeManeuver.roadName ?? _route?.summary ?? 'la vía principal';
      final straightManeuver = Maneuver(
        type: ManeuverType.straight,
        location: activeManeuver.location,
        instructionText: 'Continúa por $roadName',
        roadName: roadName,
        distanceMeters: distanceToManeuver,
      );

      final step = NavigationManeuverStep(
        activeManeuver: straightManeuver,
        nextManeuver: activeManeuver,
        distanceToManeuverMeters: distanceToManeuver,
        distanceToMilestoneMeters: distanceToManeuver,
        totalRemainingDistanceMeters: totalRemainingDist,
        maneuverIndex: activeIdx,
        isLastManeuver: false,
        isHighwayStraightContinuation: true,
      );
      _lastResolvedStep = step;
      return step;
    }

    final step = NavigationManeuverStep(
      activeManeuver: activeManeuver,
      nextManeuver: nextManeuver,
      distanceToManeuverMeters: distanceToManeuver,
      distanceToMilestoneMeters: distanceToManeuver,
      totalRemainingDistanceMeters: totalRemainingDist,
      maneuverIndex: activeIdx,
      isLastManeuver: activeIdx == maneuvers.length - 1,
      isHighwayStraightContinuation: false,
    );
    _lastResolvedStep = step;
    return step;
  }

  /// Limpia la ruta activa al finalizar la navegación.
  void clear() {
    _route = null;
    _lastResolvedStep = null;
    _cumulativeDistances.clear();
    _maneuverDistancesAlongRoute.clear();
  }
}
