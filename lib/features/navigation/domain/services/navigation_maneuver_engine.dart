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

  int _activeManeuverIndex = 0;
  int _lastRouteVersion = -1;

  /// Callback de diagnóstico correlacionado para registrar transiciones métricas
  void Function(String message)? onDiagnosticLog;

  NavigationManeuverEngine({
    RouteProgressCalculator calculator = const RouteProgressCalculator(),
    this.onDiagnosticLog,
  }) : _calculator = calculator;

  CalculatedRoute? get currentRoute => _route;
  NavigationManeuverStep? get lastResolvedStep => _lastResolvedStep;
  int get activeManeuverIndex => _activeManeuverIndex;

  /// Configura la ruta y precalcula las distancias acumuladas a lo largo de la calzada.
  void setRoute(CalculatedRoute route) {
    _route = route;
    _lastRouteVersion = route.routeVersion;
    _activeManeuverIndex = 0;
    _lastResolvedStep = null;
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
  /// Garantiza avance monotónico sin retroceso por ruido GPS, calcula distancias
  /// estrictamente a lo largo de la calzada vial y conmuta a la maniobra real
  /// cuando el motociclista se aproxima a menos de [highwayStraightThresholdMeters].
  NavigationManeuverStep? resolveStep({
    required Coordinates currentCoordinates,
    RouteProgress? progress,
    double highwayStraightThresholdMeters = 1500.0,
    int? currentSegmentIndex,
    double? gpsAccuracy,
    double? gpsSpeed,
    double? movementHeading,
    int? recalculationRequestSeq,
  }) {
    if (_route == null || _route!.routePlan.maneuvers.isEmpty) {
      return null;
    }

    final maneuvers = _route!.routePlan.maneuvers;
    if (_maneuverDistancesAlongRoute.length != maneuvers.length) {
      return null;
    }

    // Si cambió la versión de la ruta por recálculo, reiniciar índice monotónico
    if (_route!.routeVersion != _lastRouteVersion) {
      _lastRouteVersion = _route!.routeVersion;
      _activeManeuverIndex = 0;
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

    final previousIndex = _activeManeuverIndex;
    String reason = 'Seguimiento continuo de maniobra';

    // Regla 1: Tratamiento de salida (depart).
    // Si estamos en maniobra 0 y es 'depart', tan pronto el vehículo recorre más de 15 metros,
    // fijamos el objetivo en la maniobra 1 (el primer giro real por delante).
    if (_activeManeuverIndex == 0 &&
        maneuvers.length > 1 &&
        maneuvers[0].type == ManeuverType.depart) {
      if (riderDistAlongRoute >= 15.0) {
        _activeManeuverIndex = 1;
        reason =
            'Salida inicial superada (avance >= 15m) -> fijando primer giro';
      }
    }

    // Regla 2: Avance monotónico con histéresis anti-regresión (+10m).
    // Una maniobra k se considera superada si el piloto ha avanzado más allá de su ubicación (+10 m)
    // a lo largo de la calzada. El índice no puede retroceder bajo ninguna circunstancia.
    while (_activeManeuverIndex < maneuvers.length - 1) {
      final maneuverDist = _maneuverDistancesAlongRoute[_activeManeuverIndex];
      if (riderDistAlongRoute >= maneuverDist + 10.0) {
        _activeManeuverIndex++;
        reason =
            'Maniobra ${_activeManeuverIndex - 1} completada -> avanzando a index $_activeManeuverIndex';
      } else {
        break;
      }
    }

    final activeIdx = _activeManeuverIndex;
    final activeManeuver = maneuvers[activeIdx];

    // Regla 3: Cálculo métrico a lo largo de la calzada (nunca distancia euclidiana hacia atrás).
    final double rawDistance =
        _maneuverDistancesAlongRoute[activeIdx] - riderDistAlongRoute;
    // Si rawDistance <= 0.0 (en el ápice del giro entre 0m y +10m), la distancia es 0.0 ("Ahora"),
    // evitando saltos hacia atrás o aumento arbitrario mientras se dobla la esquina.
    final double distanceToManeuver = rawDistance > 0.0 ? rawDistance : 0.0;

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

    // Regla 4: Continuidad en carreteras rectas prolongadas (> highwayStraightThresholdMeters)
    final bool shouldShowStraightContinuation =
        (isTurnManeuver &&
            distanceToManeuver > highwayStraightThresholdMeters) ||
        (activeIdx == maneuvers.length - 1 &&
            activeManeuver.type == ManeuverType.arrive &&
            distanceToManeuver > highwayStraightThresholdMeters);

    final NavigationManeuverStep step;
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

      step = NavigationManeuverStep(
        activeManeuver: straightManeuver,
        nextManeuver: activeManeuver,
        distanceToManeuverMeters: distanceToManeuver,
        distanceToMilestoneMeters: distanceToManeuver,
        totalRemainingDistanceMeters: totalRemainingDist,
        maneuverIndex: activeIdx,
        isLastManeuver: false,
        isHighwayStraightContinuation: true,
      );
    } else {
      step = NavigationManeuverStep(
        activeManeuver: activeManeuver,
        nextManeuver: nextManeuver,
        distanceToManeuverMeters: distanceToManeuver,
        distanceToMilestoneMeters: distanceToManeuver,
        totalRemainingDistanceMeters: totalRemainingDist,
        maneuverIndex: activeIdx,
        isLastManeuver: activeIdx == maneuvers.length - 1,
        isHighwayStraightContinuation: false,
      );
    }

    _lastResolvedStep = step;

    // Instrumentación diagnóstica correlacionada
    if (onDiagnosticLog != null) {
      final distRouteStr = progress != null
          ? '${progress.distanceToRouteMeters.toStringAsFixed(1)}m'
          : 'N/A';
      final accStr = gpsAccuracy != null
          ? '${gpsAccuracy.toStringAsFixed(1)}m'
          : 'N/A';
      final spdStr = gpsSpeed != null
          ? '${gpsSpeed.toStringAsFixed(1)}km/h'
          : 'N/A';
      final hdgStr = movementHeading != null
          ? '${movementHeading.round()}°'
          : 'N/A';
      onDiagnosticLog!(
        '[REstelar:NAV] [step_resolved] '
        'v=$_lastRouteVersion | '
        'reqSeq=${recalculationRequestSeq ?? 0} | '
        'seg=${currentSegmentIndex ?? 0} | '
        'mIdx=$activeIdx (prev=$previousIndex) | '
        'type=${step.activeManeuver.type.name} | '
        'dist=${distanceToManeuver.round()}m | '
        'riderDist=${riderDistAlongRoute.round()}m | '
        'distToRoute=$distRouteStr | '
        'acc=$accStr | '
        'spd=$spdStr | '
        'hdg=$hdgStr | '
        'reason=$reason',
      );
    }

    return step;
  }

  /// Limpia la ruta activa al finalizar la navegación o en recálculo.
  void clear() {
    _route = null;
    _activeManeuverIndex = 0;
    _lastRouteVersion = -1;
    _lastResolvedStep = null;
    _cumulativeDistances.clear();
    _maneuverDistancesAlongRoute.clear();
  }
}
