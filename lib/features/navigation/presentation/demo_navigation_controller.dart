import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../../domain/entities/coordinates.dart';
import '../../../domain/entities/maneuver.dart';
import '../../../domain/entities/maneuver_type.dart';
import '../../../domain/entities/route_plan.dart';
import '../../../domain/entities/route_progress.dart';
import '../../../domain/services/route_progress_calculator.dart';

/// Controlador de simulación de navegación pura para demostración interactiva.
///
/// Conecta las entidades [RoutePlan], [RouteProgress] y el calculador de dominio
/// [RouteProgressCalculator] con la interfaz de usuario, simulando el avance
/// de una motocicleta en una ruta realista de aventura (Honda - La Dorada - Norcasia).
class DemoNavigationController extends ChangeNotifier {
  final RouteProgressCalculator _calculator;

  late final RoutePlan _demoRoutePlan;
  late final List<Coordinates> _routeGeometry;

  Timer? _simulationTimer;
  bool _isPlaying = false;
  int _currentStepIndex = 0;
  static const int _totalSteps = 60; // 60 pasos discretos para suavidad

  late RouteProgress _currentProgress;
  late Maneuver _currentManeuver;
  late double _distanceToManeuverMeters;

  DemoNavigationController({
    RouteProgressCalculator calculator = const RouteProgressCalculator(),
  }) : _calculator = calculator {
    _initDemoRoute();
    _recomputeProgress();
  }

  /// Plan de ruta de demostración activo.
  RoutePlan get routePlan => _demoRoutePlan;

  /// Progreso calculado sobre la geometría de la ruta.
  RouteProgress get currentProgress => _currentProgress;

  /// Maniobra activa actualmente mostrada en pantalla.
  Maneuver get currentManeuver => _currentManeuver;

  /// Distancia estimada hasta la próxima maniobra en metros.
  double get distanceToManeuverMeters => _distanceToManeuverMeters;

  /// Indica si la simulación automática está reproduciéndose.
  bool get isPlaying => _isPlaying;

  /// Proporción normalizada del avance [0.0, 1.0].
  double get stepFraction => _currentStepIndex / _totalSteps;

  /// Geometría completa de la polilínea de ruta.
  List<Coordinates> get geometry => _routeGeometry;

  void _initDemoRoute() {
    // Vértices del recorrido: Honda -> La Dorada -> Norcasia (Embalse Amaní)
    _routeGeometry = [
      Coordinates(5.2045, -74.7408), // Honda (Plaza)
      Coordinates(5.2410, -74.7350), // Salida Honda
      Coordinates(5.3350, -74.7180), // Troncal Magdalena tramo 1
      Coordinates(5.4520, -74.6650), // Entrada La Dorada
      Coordinates(5.5100, -74.7800), // Desvío montañoso a Norcasia
      Coordinates(5.5520, -74.8450), // Carretera destapada
      Coordinates(5.5780, -74.8850), // Mirador Embalse Amaní
      Coordinates(5.5800, -74.8900), // Norcasia, Caldas
    ];

    // La distancia de carretera real del motor de enrutamiento es ~54 km
    const totalRoadMeters = 54200.0;

    final maneuvers = [
      Maneuver(
        instructionText: 'Salida de Honda por Cra. 10 hacia el norte',
        type: ManeuverType.depart,
        location: _routeGeometry[0],
        roadName: 'Cra. 10 / Vía Honda',
        distanceMeters: 4200.0,
      ),
      Maneuver(
        instructionText:
            'Continúa por la Troncal del Magdalena hacia La Dorada',
        type: ManeuverType.straight,
        location: _routeGeometry[2],
        roadName: 'Troncal del Magdalena (Ruta 45)',
        distanceMeters: 18500.0,
      ),
      Maneuver(
        instructionText: 'Gira a la izquierda rumbo a Norcasia',
        type: ManeuverType.left,
        location: _routeGeometry[4],
        roadName: 'Vía Norcasia - Caldas',
        distanceMeters: 15200.0,
      ),
      Maneuver(
        instructionText:
            'Continúa por carretera destapada hacia el Embalse Amaní',
        type: ManeuverType.straight,
        location: _routeGeometry[5],
        roadName: 'Vía Amaní',
        distanceMeters: 12500.0,
      ),
      Maneuver(
        instructionText: 'Has llegado a Norcasia, Caldas. ¡Fin de ruta!',
        type: ManeuverType.arrive,
        location: _routeGeometry.last,
        roadName: 'Norcasia Centro',
        distanceMeters: 0.0,
      ),
    ];

    _demoRoutePlan = RoutePlan(
      origin: _routeGeometry.first,
      destination: _routeGeometry.last,
      geometry: _routeGeometry,
      totalDistanceMeters: totalRoadMeters,
      remainingDistanceMeters: totalRoadMeters,
      estimatedDuration: const Duration(hours: 1, minutes: 25),
      maneuvers: maneuvers,
    );
  }

  /// Calcula la posición interpolada a lo largo de la geometría de ruta
  Coordinates _interpolatePosition(double fraction) {
    if (fraction <= 0.0) return _routeGeometry.first;
    if (fraction >= 1.0) return _routeGeometry.last;

    final double totalSegs = (_routeGeometry.length - 1).toDouble();
    final double exactIndex = fraction * totalSegs;
    final int segIndex = exactIndex.floor().clamp(0, _routeGeometry.length - 2);
    final double t = exactIndex - segIndex;

    final pA = _routeGeometry[segIndex];
    final pB = _routeGeometry[segIndex + 1];

    final lat = pA.latitude + t * (pB.latitude - pA.latitude);
    final lon = pA.longitude + t * (pB.longitude - pA.longitude);

    return Coordinates(lat, lon);
  }

  void _recomputeProgress() {
    final currentPos = _interpolatePosition(stepFraction);

    _currentProgress = _calculator.calculateForRoutePlan(
      routePlan: _demoRoutePlan,
      currentPosition: currentPos,
    );

    // Determinar la maniobra más relevante según el segmento o progreso
    final maneuvers = _demoRoutePlan.maneuvers;
    if (stepFraction >= 0.95) {
      _currentManeuver = maneuvers.last;
      _distanceToManeuverMeters = _currentProgress.remainingDistanceMeters;
    } else if (stepFraction >= 0.70) {
      _currentManeuver = maneuvers[3];
      _distanceToManeuverMeters =
          (_currentProgress.remainingDistanceMeters * 0.4).clamp(50.0, 5000.0);
    } else if (stepFraction >= 0.40) {
      _currentManeuver = maneuvers[2];
      _distanceToManeuverMeters =
          (_currentProgress.remainingDistanceMeters * 0.5).clamp(100.0, 8000.0);
    } else if (stepFraction >= 0.10) {
      _currentManeuver = maneuvers[1];
      _distanceToManeuverMeters =
          (_currentProgress.remainingDistanceMeters * 0.6).clamp(
            200.0,
            12000.0,
          );
    } else {
      _currentManeuver = maneuvers[0];
      _distanceToManeuverMeters = 350.0;
    }

    notifyListeners();
  }

  /// Inicia la reproducción automática de la simulación.
  void startSimulation() {
    if (_isPlaying) return;
    _isPlaying = true;
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      if (_currentStepIndex < _totalSteps) {
        _currentStepIndex++;
        _recomputeProgress();
      } else {
        pauseSimulation();
      }
    });
    notifyListeners();
  }

  /// Pausa la simulación automática.
  void pauseSimulation() {
    _simulationTimer?.cancel();
    _simulationTimer = null;
    _isPlaying = false;
    notifyListeners();
  }

  /// Alterna entre reproducir y pausar.
  void togglePlayPause() {
    if (_isPlaying) {
      pauseSimulation();
    } else {
      if (_currentStepIndex >= _totalSteps) {
        _currentStepIndex = 0;
      }
      startSimulation();
    }
  }

  /// Avanza un paso en la simulación.
  void stepForward() {
    pauseSimulation();
    if (_currentStepIndex < _totalSteps) {
      _currentStepIndex++;
      _recomputeProgress();
    }
  }

  /// Retrocede un paso en la simulación.
  void stepBackward() {
    pauseSimulation();
    if (_currentStepIndex > 0) {
      _currentStepIndex--;
      _recomputeProgress();
    }
  }

  /// Reinicia la simulación al inicio (0% de avance).
  void resetSimulation() {
    pauseSimulation();
    _currentStepIndex = 0;
    _recomputeProgress();
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    super.dispose();
  }
}
