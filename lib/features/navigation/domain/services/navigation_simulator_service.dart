import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../../../domain/entities/coordinates.dart';
import '../../../../domain/entities/maneuver.dart';
import '../../../../domain/entities/maneuver_type.dart';
import '../entities/pereira_santa_rosa_route.dart';
import '../entities/road_curvature.dart';
import '../entities/simulated_maneuver_step.dart';
import '../entities/simulation_trace_event.dart';
import 'road_curvature_estimator.dart';
import 'routing_service.dart';
import 'tripper_ble_service.dart';
import 'tripper_protocol.dart';

export 'road_curvature_estimator.dart';

/// Estados posibles del ciclo de vida del simulador de navegación.
enum SimulationStatus {
  stopped,
  running,
  paused,
  completed;

  String get displayName {
    switch (this) {
      case SimulationStatus.stopped:
        return 'Detenido';
      case SimulationStatus.running:
        return 'En Curso';
      case SimulationStatus.paused:
        return 'Pausado';
      case SimulationStatus.completed:
        return 'Completado';
    }
  }
}

/// Opciones de velocidad simulada permitidas.
enum SimulationSpeed {
  kmh10(10, 10.0 / 3.6),
  kmh30(30, 30.0 / 3.6),
  kmh60(60, 60.0 / 3.6);

  final int kmh;
  final double metersPerSecond;

  const SimulationSpeed(this.kmh, this.metersPerSecond);

  String get displayName => '$kmh km/h';
}

/// Servicio desacoplado que orquesta la simulación virtual de navegación dinámica por carretera,
/// cálculo continuo de curvas, semáforo de proximidad y sincronización BLE con el Tripper Pod.
class NavigationSimulatorService extends ChangeNotifier {
  final TripperBleService? _bleService;
  List<SimulatedManeuverStep> _steps;
  List<Coordinates> _geometry;
  final List<double> _cumulativeDistances = [];
  final List<double> _maneuverDistancesAlongRoute = [];

  String _routeName;
  SimulationStatus _status = SimulationStatus.stopped;
  SimulationSpeed _speed = SimulationSpeed.kmh30;
  bool _transmitToBle = false;
  bool _nightMode = false;

  int _currentStepIndex = 0;
  double _traveledDistanceMeters = 0.0;
  double _currentVirtualDistanceMeters = 0.0;
  Coordinates _virtualPosition;
  RoadCurvatureInfo _currentCurvatureInfo = RoadCurvatureInfo.undetermined;
  ProximityTrafficLight _trafficLight = ProximityTrafficLight.green;

  Timer? _tickerTimer;
  final Duration _tickInterval;

  bool _isLoadingRoute = false;
  String? _routeLoadError;

  String? _lastSimulatedInstruction;
  String? _lastTransmittedHex;
  DateTime? _lastTransmissionTime;
  String? _lastTransmissionResult;
  String? _lastError;
  int _generatedInstructionsCount = 0;
  int _transmittedInstructionsCount = 0;

  int? _lastBleTransmittedDistance;
  DateTime? _lastBleTransmissionTime;
  final double _bleDistanceUpdateThresholdMeters = 5.0;

  final List<SimulationTraceEvent> _traceHistory = [];
  final StreamController<SimulationTraceEvent> _traceStreamController =
      StreamController<SimulationTraceEvent>.broadcast();

  NavigationSimulatorService({
    TripperBleService? bleService,
    List<SimulatedManeuverStep>? customSteps,
    List<Coordinates>? customGeometry,
    String routeName = PereiraSantaRosaRoute.routeName,
    Duration tickInterval = const Duration(seconds: 1),
    bool transmitToBleDefault = false,
  }) : _bleService = bleService,
       _steps = customSteps ?? _buildDefaultDeterministicScenario(),
       _geometry = List.from(customGeometry ?? PereiraSantaRosaRoute.geometry),
       _routeName = routeName,
       _tickInterval = tickInterval,
       _transmitToBle = transmitToBleDefault,
       _virtualPosition = (customGeometry != null && customGeometry.isNotEmpty)
           ? customGeometry.first
           : PereiraSantaRosaRoute.origin {
    _initGeometryAndDistances();
    _resetStepDistance();
    _updateVirtualPositionAndCurvature();
    _updateTrafficLight();
  }

  // --- Getters de estado ---
  String get routeName => _routeName;
  SimulationStatus get status => _status;
  SimulationSpeed get speed => _speed;
  bool get isRunning => _status == SimulationStatus.running;
  bool get isPaused => _status == SimulationStatus.paused;
  bool get isStopped => _status == SimulationStatus.stopped;
  bool get isCompleted => _status == SimulationStatus.completed;
  bool get transmitToBle => _transmitToBle;
  bool get nightMode => _nightMode;
  bool get isLoadingRoute => _isLoadingRoute;
  String? get routeLoadError => _routeLoadError;

  int get currentStepIndex => _currentStepIndex;
  int get totalSteps => _steps.length;
  List<SimulatedManeuverStep> get steps => List.unmodifiable(_steps);
  List<Coordinates> get geometry => List.unmodifiable(_geometry);
  Coordinates get currentVirtualPosition => _virtualPosition;
  RoadCurvatureInfo get currentCurvature => _currentCurvatureInfo;
  ProximityTrafficLight get trafficLight => _trafficLight;

  SimulatedManeuverStep get currentStep {
    if (_steps.isEmpty) {
      throw StateError('La lista de maniobras de simulación está vacía.');
    }
    return _steps[_currentStepIndex.clamp(0, _steps.length - 1)];
  }

  double get currentVirtualDistanceMeters => _currentVirtualDistanceMeters;
  double get distanceToNextManeuverMeters => _currentVirtualDistanceMeters;
  double get traveledDistanceMeters => _traveledDistanceMeters;

  /// Distancia restante total calculada hasta el final de la ruta.
  double get totalRemainingDistanceMeters {
    if (_status == SimulationStatus.completed) return 0.0;
    double sum = _currentVirtualDistanceMeters;
    for (int i = _currentStepIndex + 1; i < _steps.length; i++) {
      sum += _steps[i].initialDistanceMeters;
    }
    return sum;
  }

  /// Distancia total fija del escenario completo.
  double get totalRouteDistanceMeters {
    double sum = 0.0;
    for (final s in _steps) {
      sum += s.initialDistanceMeters;
    }
    return sum > 0 ? sum : 1.0;
  }

  /// Porcentaje de progreso completado [0.0, 100.0].
  double get progressPercentage {
    if (_status == SimulationStatus.completed) return 100.0;
    final total = totalRouteDistanceMeters;
    final remaining = totalRemainingDistanceMeters;
    final traveled = (total - remaining).clamp(0.0, total);
    return (traveled / total) * 100.0;
  }

  String? get lastSimulatedInstruction => _lastSimulatedInstruction;
  String? get lastTransmittedHex => _lastTransmittedHex;
  DateTime? get lastTransmissionTime => _lastTransmissionTime;
  String? get lastTransmissionResult => _lastTransmissionResult;
  String? get lastError => _lastError;
  int get generatedInstructionsCount => _generatedInstructionsCount;
  int get transmittedInstructionsCount => _transmittedInstructionsCount;

  List<SimulationTraceEvent> get traceHistory =>
      List.unmodifiable(_traceHistory);
  SimulationTraceEvent? get lastTraceEvent =>
      _traceHistory.isNotEmpty ? _traceHistory.last : null;
  Stream<SimulationTraceEvent> get traceStream => _traceStreamController.stream;
  int? get lastBleTransmittedDistance => _lastBleTransmittedDistance;

  @override
  void dispose() {
    _stopTimer();
    _traceStreamController.close();
    super.dispose();
  }

  // --- Configuración y precálculos geométricos ---

  void _initGeometryAndDistances() {
    _cumulativeDistances.clear();
    _maneuverDistancesAlongRoute.clear();

    if (_geometry.isEmpty) return;

    // 1. Distancias acumuladas de vértices
    _cumulativeDistances.add(0.0);
    double accumulated = 0.0;
    for (int i = 1; i < _geometry.length; i++) {
      accumulated += _geometry[i - 1].distanceTo(_geometry[i]);
      _cumulativeDistances.add(accumulated);
    }

    // 2. Asociar cada maniobra a su distancia a lo largo de la ruta
    double stepDistAccum = 0.0;
    for (int m = 0; m < _steps.length; m++) {
      stepDistAccum += _steps[m].initialDistanceMeters;
      _maneuverDistancesAlongRoute.add(stepDistAccum);
    }
  }

  // --- Controles de simulación ---

  /// Inicia o reanuda la simulación virtual.
  void start() {
    if (_status == SimulationStatus.completed) {
      reset();
    }
    if (_status == SimulationStatus.running) return;

    _status = SimulationStatus.running;
    _lastBleTransmittedDistance = null;
    _startTimer();
    _syncCurrentManeuver(reason: 'Inicio de simulación virtual');
    notifyListeners();
  }

  /// Pausa el avance temporal del simulador manteniendo el progreso actual y congelando el estado.
  void pause() {
    if (_status != SimulationStatus.running) return;
    _stopTimer();
    _status = SimulationStatus.paused;
    _recordTraceEvent(
      distanceMeters: _currentVirtualDistanceMeters.toInt(),
      action: SimulationTraceAction.reused,
      reason: 'Simulación pausada (congelando posición y metraje)',
    );
    notifyListeners();
  }

  /// Reanuda la simulación desde el punto y distancia exactos en que fue pausada.
  void resume() {
    if (_status != SimulationStatus.paused) return;
    _status = SimulationStatus.running;
    _startTimer();
    _recordTraceEvent(
      distanceMeters: _currentVirtualDistanceMeters.toInt(),
      action: SimulationTraceAction.reused,
      reason: 'Simulación reanudada',
    );
    _syncCurrentManeuver(reason: 'Reanudación de simulación');
    notifyListeners();
  }

  /// Alterna entre reproducir y pausar.
  void togglePlayPause() {
    if (_status == SimulationStatus.running) {
      pause();
    } else {
      start();
    }
  }

  /// Detiene y finaliza la simulación, cancelando temporizadores y deteniendo envíos en la cola BLE.
  void stop() {
    _stopTimer();
    _status = SimulationStatus.stopped;
    _lastBleTransmittedDistance = null;
    _recordTraceEvent(
      distanceMeters: _currentVirtualDistanceMeters.toInt(),
      action: SimulationTraceAction.omitted,
      reason: 'Simulación detenida por el usuario',
    );
    if (_transmitToBle) {
      _bleService?.stopNavigation();
    }
    notifyListeners();
  }

  /// Reinicia el simulador al primer paso (0% de avance, distancia inicial y color VERDE).
  void reset() {
    _stopTimer();
    _status = SimulationStatus.stopped;
    _currentStepIndex = 0;
    _traveledDistanceMeters = 0.0;
    _lastBleTransmittedDistance = null;
    _lastBleTransmissionTime = null;
    _resetStepDistance();
    _updateVirtualPositionAndCurvature();
    _trafficLight = ProximityTrafficLight.green;
    _recordTraceEvent(
      distanceMeters: _currentVirtualDistanceMeters.toInt(),
      action: SimulationTraceAction.reused,
      reason: 'Simulador reiniciado a estado inicial (0% progreso)',
    );
    if (_transmitToBle) {
      _bleService?.stopNavigation();
    }
    notifyListeners();
  }

  /// Configura la velocidad virtual (10, 30 o 60 km/h) sin saltos artificiales en la posición.
  void setSpeed(SimulationSpeed newSpeed) {
    if (_speed == newSpeed) return;
    _speed = newSpeed;
    _recordTraceEvent(
      distanceMeters: _currentVirtualDistanceMeters.toInt(),
      action: SimulationTraceAction.reused,
      reason: 'Velocidad de simulación ajustada a ${newSpeed.displayName}',
    );
    notifyListeners();
  }

  /// Habilita o deshabilita la transmisión física de tramas al Tripper Pod.
  void setTransmitToBle(bool enable) {
    if (_transmitToBle == enable) return;
    _transmitToBle = enable;
    if (_status == SimulationStatus.running) {
      if (enable) {
        _lastBleTransmittedDistance = null;
        _syncCurrentManeuver(reason: 'Transmisión BLE habilitada en marcha');
      } else {
        _bleService?.stopNavigation();
        _lastTransmissionResult =
            'Transmisión física desactivada (simulación local)';
        _recordTraceEvent(
          distanceMeters: _currentVirtualDistanceMeters.toInt(),
          action: SimulationTraceAction.omitted,
          reason: 'Transmisión física BLE desactivada por el usuario',
        );
      }
    }
    notifyListeners();
  }

  /// Activa o desactiva el modo nocturno para el cálculo de bits de intensidad.
  void setNightMode(bool enable) {
    if (_nightMode == enable) return;
    _nightMode = enable;
    if (_status == SimulationStatus.running && _transmitToBle) {
      _lastBleTransmittedDistance = null;
      _syncCurrentManeuver(reason: 'Modo nocturno alterado ($enable)');
    }
    notifyListeners();
  }

  /// Avanza manualmente al siguiente paso sin esperar al temporizador.
  void stepNext() {
    _lastBleTransmittedDistance = null;
    if (_currentStepIndex < _steps.length - 1) {
      _currentStepIndex++;
      _resetStepDistance();
      _syncCurrentManeuver(
        reason: 'Paso manual adelante (#${currentStep.stepNumber})',
      );
    } else {
      _currentVirtualDistanceMeters = 0.0;
      _status = SimulationStatus.completed;
      _stopTimer();
      _recordTraceEvent(
        distanceMeters: 0,
        action: SimulationTraceAction.omitted,
        reason: 'Fin de ruta alcanzado mediante avance manual',
      );
      if (_transmitToBle) {
        _bleService?.stopNavigation();
      }
    }
    _updateVirtualPositionAndCurvature();
    _updateTrafficLight();
    notifyListeners();
  }

  /// Retrocede manualmente al paso anterior.
  void stepPrevious() {
    if (_currentStepIndex > 0) {
      _currentStepIndex--;
      _resetStepDistance();
      _lastBleTransmittedDistance = null;
      if (_status == SimulationStatus.completed) {
        _status = SimulationStatus.paused;
      }
      _syncCurrentManeuver(
        reason: 'Paso manual atrás (#${currentStep.stepNumber})',
      );
      _updateVirtualPositionAndCurvature();
      _updateTrafficLight();
      notifyListeners();
    }
  }

  /// Salto directo a un índice de maniobra específico.
  void jumpToStep(int index) {
    if (index < 0 || index >= _steps.length) return;
    _currentStepIndex = index;
    _resetStepDistance();
    _lastBleTransmittedDistance = null;
    _syncCurrentManeuver(
      reason: 'Salto directo a paso #${currentStep.stepNumber}',
    );
    _updateVirtualPositionAndCurvature();
    _updateTrafficLight();
    notifyListeners();
  }

  /// Modo de prueba rápida para simular la aproximación a una curva:
  /// Fija la distancia restante a 300 m antes de la curva para observar la progresión
  /// y el cambio Verde -> Amarillo -> Rojo sin recorrer los kilómetros completos.
  void approachQuickCurveTest() {
    _currentVirtualDistanceMeters = 300.0;
    _lastBleTransmittedDistance = null;
    _trafficLight = ProximityTrafficLight.green;
    _updateVirtualPositionAndCurvature();
    _lastSimulatedInstruction =
        '${currentStep.stepNumber}. Aproximación rápida a curva (${_currentVirtualDistanceMeters.toInt()}m)';
    _syncCurrentManeuver(reason: 'Inicio prueba rápida aproximación (300m)');
    notifyListeners();
  }

  /// Carga explícita del escenario canónico Pereira → Santa Rosa de Cabal.
  void loadPereiraSantaRosaScenario() {
    _stopTimer();
    _routeName = PereiraSantaRosaRoute.routeName;
    _geometry = List.from(PereiraSantaRosaRoute.geometry);
    _steps = PereiraSantaRosaRoute.buildCanonicalManeuverSteps();
    _initGeometryAndDistances();
    reset();
  }

  /// Descarga y aplica una ruta real desde el motor OSRM con manejo de carga y errores.
  Future<bool> loadLiveRouteFromOsrm({
    required RoutingService routingService,
    Coordinates? origin,
    Coordinates? destination,
  }) async {
    _isLoadingRoute = true;
    _routeLoadError = null;
    notifyListeners();

    try {
      final o = origin ?? PereiraSantaRosaRoute.origin;
      final d = destination ?? PereiraSantaRosaRoute.destination;
      final calculated = await routingService.calculateRoute(
        origin: o,
        destination: d,
      );

      if (calculated.geometry.length < 2) {
        throw Exception('La geometría devuelta por OSRM es insuficiente.');
      }

      _geometry = List.from(calculated.geometry);
      _routeName = 'Pereira → Santa Rosa de Cabal (OSRM en vivo)';

      // Convertir maniobras OSRM en pasos simulados
      final osrmSteps = <SimulatedManeuverStep>[];
      final maneuvers = calculated.routePlan.maneuvers;
      for (int i = 0; i < maneuvers.length; i++) {
        final m = maneuvers[i];
        final code = TripperProtocol.mapManeuverToTripperCode(m.type);
        final isSupported = code != null;
        final note = isSupported
            ? 'Código ${TripperProtocol.getOpcodeStatus(code).label} 0x${code.toRadixString(16).padLeft(2, '0').toUpperCase()} (${m.type.name})'
            : 'Solo simulación local: maniobra sin opcode Tripper verificado';

        osrmSteps.add(
          SimulatedManeuverStep(
            stepNumber: i + 1,
            maneuver: m,
            initialDistanceMeters: (m.distanceMeters?.toInt() ?? 200).clamp(
              50,
              10000,
            ),
            isSupportedByTripper: isSupported,
            tripperManeuverCode: code,
            compatibilityNote: note,
          ),
        );
      }

      _steps = osrmSteps.isNotEmpty
          ? osrmSteps
          : PereiraSantaRosaRoute.buildCanonicalManeuverSteps();
      _initGeometryAndDistances();
      reset();
      _isLoadingRoute = false;
      notifyListeners();
      return true;
    } catch (e) {
      _routeLoadError =
          'No se pudo conectar con OSRM: $e. Se conserva la ruta local.';
      _isLoadingRoute = false;
      notifyListeners();
      return false;
    }
  }

  /// Sincroniza explícitamente la maniobra y distancia virtual actual hacia el transporte BLE.
  Future<bool> syncCurrentManeuver({String? reason}) =>
      _syncCurrentManeuver(reason: reason ?? 'Sincronización manual explícita');

  /// Registra un evento inmutable en el historial y flujo de trazabilidad.
  void _recordTraceEvent({
    required int distanceMeters,
    String? generatedPacketHex,
    required SimulationTraceAction action,
    required String reason,
  }) {
    if (_steps.isEmpty) return;
    final step = currentStep;
    final nextStep = _currentStepIndex + 1 < _steps.length
        ? _steps[_currentStepIndex + 1]
        : null;
    final opcodeHex = step.tripperManeuverCode != null
        ? '0x${step.tripperManeuverCode!.toRadixString(16).padLeft(2, '0').toUpperCase()}'
        : null;
    final timeSinceLastNavScreenMs = _lastTransmissionTime != null
        ? DateTime.now().difference(_lastTransmissionTime!).inMilliseconds
        : null;
    final bleState = _bleService?.currentState.displayName ?? 'Desconectado';

    final event = SimulationTraceEvent(
      timestamp: DateTime.now(),
      accumulatedDistanceMeters: _traveledDistanceMeters,
      virtualPosition: _virtualPosition,
      stepNumber: step.stepNumber,
      nextStepNumber: nextStep?.stepNumber,
      maneuverIdentifier: step.maneuver.instructionText,
      maneuverType: step.maneuver.type.name,
      opcodeHex: opcodeHex,
      curvatureType: _currentCurvatureInfo.type,
      curvatureDeltaDegrees: _currentCurvatureInfo.bearingDeltaDegrees,
      distanceToManeuverMeters: distanceMeters,
      generatedPacketHex: generatedPacketHex,
      action: action,
      reason: reason,
      timeSinceLastNavScreenMs: timeSinceLastNavScreenMs,
      bleConnectionState: bleState,
    );
    _traceHistory.add(event);
    if (_traceHistory.length > 200) {
      _traceHistory.removeAt(0);
    }
    _traceStreamController.add(event);
  }

  /// Avanza el avance temporal un delta de tiempo explícito en segundos.
  void advanceTime(double seconds) {
    if (_status != SimulationStatus.running) return;

    final distanceDelta = _speed.metersPerSecond * seconds;
    _traveledDistanceMeters = (_traveledDistanceMeters + distanceDelta).clamp(
      0.0,
      totalRouteDistanceMeters,
    );
    _currentVirtualDistanceMeters -= distanceDelta;

    if (_currentVirtualDistanceMeters <= 0.0) {
      if (_currentStepIndex < _steps.length - 1) {
        _currentStepIndex++;
        _resetStepDistance();
        _lastBleTransmittedDistance = null;
        _syncCurrentManeuver(
          reason: 'Avance al siguiente paso (#${currentStep.stepNumber})',
        );
      } else {
        _currentVirtualDistanceMeters = 0.0;
        _status = SimulationStatus.completed;
        _stopTimer();
        _recordTraceEvent(
          distanceMeters: 0,
          action: SimulationTraceAction.cleared,
          reason: 'Fin de recorrido alcanzado. Transmisión BLE finalizada.',
        );
        if (_transmitToBle) {
          _bleService?.stopNavigation();
        }
      }
    } else {
      // Actualizar instrucción simulada con la distancia decreciente exacta
      _lastSimulatedInstruction =
          '${currentStep.stepNumber}. ${currentStep.maneuver.instructionText} (${_currentVirtualDistanceMeters.toInt()}m)';
      _syncDynamicDistanceDuringStep();
    }

    _updateVirtualPositionAndCurvature();
    _updateTrafficLight();

    notifyListeners();
  }

  /// Sincronización continua y prudente de la distancia restante hacia BLE durante el paso activo.
  Future<void> _syncDynamicDistanceDuringStep() async {
    final step = currentStep;
    final distInt = _currentVirtualDistanceMeters.toInt().clamp(0, 65535);
    final now = DateTime.now();

    if (!_transmitToBle) {
      _recordTraceEvent(
        distanceMeters: distInt,
        action: SimulationTraceAction.omitted,
        reason: 'Simulación local activa (transmisión BLE desactivada)',
      );
      return;
    }

    final ble = _bleService;
    if (ble == null || !ble.currentState.isReadyForNavigation) {
      _recordTraceEvent(
        distanceMeters: distInt,
        action: SimulationTraceAction.omitted,
        reason: ble == null
            ? 'Servicio BLE no inyectado'
            : 'Tripper Pod no conectado o no autenticado (${ble.currentState.displayName})',
      );
      return;
    }

    // Si la maniobra no tiene opcode específico asignado, emitir pantalla de resguardo para alimentar el watchdog
    if (!step.isSupportedByTripper || step.tripperManeuverCode == null) {
      final safePacket = TripperProtocol.buildSafeTransitionPacket(
        distanceMeters: distInt,
        nightMode: _nightMode,
      );
      final hex = TripperProtocol.toHexString(safePacket);
      _lastTransmittedHex = hex;
      _lastTransmissionTime = now;
      _lastBleTransmittedDistance = distInt;
      _lastBleTransmissionTime = now;

      try {
        await ble.sendRawPacket(safePacket);
        _recordTraceEvent(
          distanceMeters: distInt,
          generatedPacketHex: hex,
          action: SimulationTraceAction.transmitted,
          reason:
              '[PANTALLA_TRANSICION_SEGURA] Refresco dinámico seguro 0x1C (${distInt}m) para mantener vivo el watchdog sin falsear giro (${step.compatibilityNote})',
        );
      } catch (e) {
        _lastError = e.toString();
      }
      return;
    }

    final lastDist = _lastBleTransmittedDistance;
    final lastTime = _lastBleTransmissionTime;

    final distanceDelta = lastDist == null
        ? double.infinity
        : (lastDist - distInt).abs().toDouble();
    final timeDeltaMs = lastTime == null
        ? 999999
        : now.difference(lastTime).inMilliseconds;

    // Se actualiza si la distancia cambió >= 5m (o en saltos >= 20m)
    // y han transcurrido al menos 750 ms (para cadencia prudente que no sature BLE).
    final shouldTransmit =
        (lastDist == null) ||
        (distanceDelta >= _bleDistanceUpdateThresholdMeters &&
            (timeDeltaMs >= 750 || distanceDelta >= 20.0));

    if (!shouldTransmit) {
      _recordTraceEvent(
        distanceMeters: distInt,
        generatedPacketHex: _lastTransmittedHex,
        action: SimulationTraceAction.throttled,
        reason:
            'Metraje pospuesto por ventana de cadencia (último enviado: ${lastDist}m, actual: ${distInt}m)',
      );
      return;
    }

    int nextManeuver = TripperProtocol.nextManeuverNone;
    if (distInt < 100 && _currentStepIndex + 1 < _steps.length) {
      final nextStep = _steps[_currentStepIndex + 1];
      if (nextStep.isSupportedByTripper &&
          nextStep.tripperManeuverCode != null) {
        nextManeuver = nextStep.tripperManeuverCode!;
      }
    }

    final packet = step.buildProtocolPacket(
      distanceMeters: distInt,
      nightMode: _nightMode,
      nextManeuver: nextManeuver,
    );

    if (packet == null) return;

    final hex = TripperProtocol.toHexString(packet);
    _lastTransmittedHex = hex;
    _lastTransmissionTime = now;
    _lastBleTransmittedDistance = distInt;
    _lastBleTransmissionTime = now;

    try {
      final ok = await ble.sendRawPacket(packet);
      if (ok) {
        _transmittedInstructionsCount++;
        _lastTransmissionResult =
            'OK (Distancia dinámica actualizada a ${distInt}m en Tripper Pod)';
        _recordTraceEvent(
          distanceMeters: distInt,
          generatedPacketHex: hex,
          action: SimulationTraceAction.transmitted,
          reason: lastDist != null
              ? 'Actualización dinámica de distancia: ${lastDist}m -> ${distInt}m'
              : 'Primera emisión de distancia para paso #${step.stepNumber}: ${distInt}m',
        );
      } else {
        _lastTransmissionResult =
            'Fallo de escritura en característica GATT de RE_DISP en ${distInt}m';
      }
    } catch (e) {
      _lastError = e.toString();
      _lastTransmissionResult = 'Excepción al transmitir trama: $e';
    }
  }

  // --- Métodos internos ---

  void _startTimer() {
    _stopTimer();
    _tickerTimer = Timer.periodic(_tickInterval, (_) {
      advanceTime(_tickInterval.inMilliseconds / 1000.0);
    });
  }

  void _stopTimer() {
    _tickerTimer?.cancel();
    _tickerTimer = null;
  }

  void _resetStepDistance() {
    if (_steps.isNotEmpty) {
      _currentVirtualDistanceMeters =
          _steps[_currentStepIndex.clamp(0, _steps.length - 1)]
              .initialDistanceMeters
              .toDouble();
    } else {
      _currentVirtualDistanceMeters = 0.0;
    }
  }

  void _updateVirtualPositionAndCurvature() {
    if (_geometry.isEmpty) return;

    // Calcular posición interpolada sobre la polilínea
    if (_cumulativeDistances.isNotEmpty && _cumulativeDistances.last > 0) {
      final totalGeom = _cumulativeDistances.last;
      final totalStepsDist = totalRouteDistanceMeters;
      // Proporción de avance sobre la geometría
      final ratio = totalStepsDist > 0
          ? (_traveledDistanceMeters / totalStepsDist).clamp(0.0, 1.0)
          : 0.0;
      final geomDistance = ratio * totalGeom;

      _virtualPosition = RoadCurvatureEstimator.interpolateAtDistance(
        _geometry,
        _cumulativeDistances,
        geomDistance,
      );

      _currentCurvatureInfo = RoadCurvatureEstimator.estimate(
        geometry: _geometry,
        traveledDistanceMeters: geomDistance,
        cumulativeDistances: _cumulativeDistances,
        upcomingManeuver: currentStep.maneuver,
        distanceToManeuverMeters: _currentVirtualDistanceMeters,
        geometrySource: GeometrySource.canonicalSimulation,
      );
    } else {
      _virtualPosition = _geometry.first;
      _currentCurvatureInfo = RoadCurvatureInfo.undetermined;
    }
  }

  void _updateTrafficLight() {
    _trafficLight = ProximityTrafficLight.evaluate(
      distanceMeters: _currentVirtualDistanceMeters,
      previousState: _trafficLight,
    );
  }

  Future<bool> _syncCurrentManeuver({String? reason}) async {
    _generatedInstructionsCount++;
    final step = currentStep;
    final distInt = _currentVirtualDistanceMeters.toInt().clamp(0, 65535);
    _lastSimulatedInstruction =
        '${step.stepNumber}. ${step.maneuver.instructionText} (${distInt}m)';

    if (!_transmitToBle) {
      _lastTransmissionResult =
          'Simulación local activa (transmisión BLE desactivada)';
      _recordTraceEvent(
        distanceMeters: distInt,
        action: SimulationTraceAction.omitted,
        reason: reason ?? 'Simulación local activa (BLE desactivado)',
      );
      return false;
    }

    final ble = _bleService;
    if (ble == null) {
      _lastTransmissionResult = 'Servicio BLE no inyectado en el simulador.';
      _recordTraceEvent(
        distanceMeters: distInt,
        action: SimulationTraceAction.omitted,
        reason: 'Servicio BLE no inyectado en simulador',
      );
      return false;
    }

    if (!ble.currentState.isReadyForNavigation) {
      _lastTransmissionResult =
          'Tripper Pod no conectado o no autenticado (${ble.currentState.displayName}).';
      _recordTraceEvent(
        distanceMeters: distInt,
        action: SimulationTraceAction.omitted,
        reason: 'Tripper Pod no conectado (${ble.currentState.displayName})',
      );
      return false;
    }

    if (!step.isSupportedByTripper || step.tripperManeuverCode == null) {
      final safePacket = TripperProtocol.buildSafeTransitionPacket(
        distanceMeters: distInt,
        nightMode: _nightMode,
      );
      final hex = TripperProtocol.toHexString(safePacket);
      _lastTransmittedHex = hex;
      _lastTransmissionTime = DateTime.now();
      _lastBleTransmittedDistance = distInt;
      _lastBleTransmissionTime = _lastTransmissionTime;

      try {
        final ok = await ble.sendRawPacket(safePacket);
        if (ok) {
          _transmittedInstructionsCount++;
          _lastTransmissionResult =
              'OK (Pantalla segura 0x1C emitida para preservar enlace BLE en paso #${step.stepNumber})';
          _recordTraceEvent(
            distanceMeters: distInt,
            generatedPacketHex: hex,
            action: SimulationTraceAction.transmitted,
            reason:
                '[PANTALLA_TRANSICION_SEGURA] Opcode no confirmado; se emite 0x1C para preservar watchdog sin falsear giro (${step.compatibilityNote})',
          );
        }
        return ok;
      } catch (e) {
        _lastError = e.toString();
        _lastTransmissionResult =
            'Excepción al emitir pantalla de resguardo: $e';
        return false;
      }
    }

    int nextManeuver = TripperProtocol.nextManeuverNone;
    if (distInt < 100 && _currentStepIndex + 1 < _steps.length) {
      final nextStep = _steps[_currentStepIndex + 1];
      if (nextStep.isSupportedByTripper &&
          nextStep.tripperManeuverCode != null) {
        nextManeuver = nextStep.tripperManeuverCode!;
      }
    }

    final packet = step.buildProtocolPacket(
      distanceMeters: distInt,
      nightMode: _nightMode,
      nextManeuver: nextManeuver,
    );

    if (packet == null) {
      _lastTransmissionResult = 'Error al construir trama binaria.';
      return false;
    }

    final hex = TripperProtocol.toHexString(packet);
    _lastTransmittedHex = hex;
    _lastTransmissionTime = DateTime.now();
    _lastBleTransmittedDistance = distInt;
    _lastBleTransmissionTime = _lastTransmissionTime;

    try {
      final ok = await ble.sendRawPacket(packet);
      if (ok) {
        _transmittedInstructionsCount++;
        _lastTransmissionResult =
            'OK (Escritura GATT aceptada en Android. Verificar visualmente en Pod).';
        _recordTraceEvent(
          distanceMeters: distInt,
          generatedPacketHex: hex,
          action: SimulationTraceAction.transmitted,
          reason: reason ?? 'Sincronización de maniobra #${step.stepNumber}',
        );
      } else {
        _lastTransmissionResult =
            'Fallo de escritura en característica GATT de RE_DISP.';
        _recordTraceEvent(
          distanceMeters: distInt,
          generatedPacketHex: hex,
          action: SimulationTraceAction.omitted,
          reason: 'Fallo de escritura GATT en RE_DISP',
        );
      }
      return ok;
    } catch (e) {
      _lastError = e.toString();
      _lastTransmissionResult = 'Excepción al transmitir trama: $e';
      return false;
    }
  }

  /// Escenario determinista requerido de 8 maniobras para prueba estática reproducible.
  static List<SimulatedManeuverStep> _buildDefaultDeterministicScenario() {
    return [
      // 1. Inicio de navegación
      SimulatedManeuverStep(
        stepNumber: 1,
        maneuver: Maneuver(
          instructionText: 'Inicia el recorrido por Cra. 7 hacia el norte',
          type: ManeuverType.depart,
          location: Coordinates(4.6534, -74.0628),
          roadName: 'Carrera 7',
          distanceMeters: 600.0,
        ),
        initialDistanceMeters: 600,
        isSupportedByTripper: true,
        tripperManeuverCode: TripperProtocol.maneuverDepart,
        compatibilityNote: 'Código verificado 0x3C (Inicio de ruta)',
      ),

      // 2. Continuar recto (Trama de referencia validada en hardware)
      SimulatedManeuverStep(
        stepNumber: 2,
        maneuver: Maneuver(
          instructionText: 'Continúa recto por Cra. 7 durante 500 metros',
          type: ManeuverType.straight,
          location: Coordinates(4.6570, -74.0610),
          roadName: 'Carrera 7',
          distanceMeters: 500.0,
        ),
        initialDistanceMeters: 500,
        isSupportedByTripper: true,
        tripperManeuverCode: TripperProtocol.maneuverStraight,
        compatibilityNote:
            'Trama de referencia física: 10 11 09 01 F4 01 00... 73 85 (0x09 Recto 500m)',
      ),

      // 3. Aproximación a un giro a la derecha
      SimulatedManeuverStep(
        stepNumber: 3,
        maneuver: Maneuver(
          instructionText:
              'En 250 m, prepárate para girar a la derecha por Cll. 72',
          type: ManeuverType.right,
          location: Coordinates(4.6590, -74.0600),
          roadName: 'Calle 72',
          distanceMeters: 250.0,
        ),
        initialDistanceMeters: 250,
        isSupportedByTripper: true,
        tripperManeuverCode: TripperProtocol.maneuverTurnRight,
        compatibilityNote: 'Código de giro a la derecha (0x15)',
      ),

      // 4. Giro a la derecha
      SimulatedManeuverStep(
        stepNumber: 4,
        maneuver: Maneuver(
          instructionText: 'Gira a la derecha en Calle 72',
          type: ManeuverType.right,
          location: Coordinates(4.6610, -74.0590),
          roadName: 'Calle 72',
          distanceMeters: 100.0,
        ),
        initialDistanceMeters: 100,
        isSupportedByTripper: true,
        tripperManeuverCode: TripperProtocol.maneuverTurnRight,
        compatibilityNote:
            'Código confirmado físicamente 0x15 (Giro a la derecha con progresión de barras y destello comprobado)',
      ),

      // 5. Continuar recto
      SimulatedManeuverStep(
        stepNumber: 5,
        maneuver: Maneuver(
          instructionText: 'Continúa recto por Carrera 11 durante 400 metros',
          type: ManeuverType.straight,
          location: Coordinates(4.6630, -74.0570),
          roadName: 'Carrera 11',
          distanceMeters: 400.0,
        ),
        initialDistanceMeters: 400,
        isSupportedByTripper: true,
        tripperManeuverCode: TripperProtocol.maneuverStraight,
        compatibilityNote: 'Código validado 0x09 (Recto)',
      ),

      // 6. Aproximación a un giro a la izquierda
      SimulatedManeuverStep(
        stepNumber: 6,
        maneuver: Maneuver(
          instructionText:
              'En 200 m, prepárate para girar a la izquierda por Cll. 85',
          type: ManeuverType.left,
          location: Coordinates(4.6650, -74.0550),
          roadName: 'Calle 85',
          distanceMeters: 200.0,
        ),
        initialDistanceMeters: 200,
        isSupportedByTripper: true,
        tripperManeuverCode: TripperProtocol.maneuverTurnLeft,
        compatibilityNote:
            'Código documentado 0x14 (Aproximación giro a la izquierda)',
      ),

      // 7. Giro a la izquierda
      SimulatedManeuverStep(
        stepNumber: 7,
        maneuver: Maneuver(
          instructionText: 'Gira a la izquierda en Calle 85',
          type: ManeuverType.left,
          location: Coordinates(4.6670, -74.0530),
          roadName: 'Calle 85',
          distanceMeters: 80.0,
        ),
        initialDistanceMeters: 80,
        isSupportedByTripper: true,
        tripperManeuverCode: TripperProtocol.maneuverTurnLeft,
        compatibilityNote: 'Código documentado 0x14 (Giro a la izquierda)',
      ),

      // 8. Llegada al destino
      SimulatedManeuverStep(
        stepNumber: 8,
        maneuver: Maneuver(
          instructionText:
              'Has llegado a tu destino en Calle 85. ¡Fin del recorrido!',
          type: ManeuverType.arrive,
          location: Coordinates(4.6680, -74.0520),
          roadName: 'Calle 85 Destino',
          distanceMeters: 0.0,
        ),
        initialDistanceMeters: 0,
        isSupportedByTripper: true,
        tripperManeuverCode: TripperProtocol.maneuverDestination,
        compatibilityNote: 'Código verificado 0x00 (Destino)',
      ),
    ];
  }
}
