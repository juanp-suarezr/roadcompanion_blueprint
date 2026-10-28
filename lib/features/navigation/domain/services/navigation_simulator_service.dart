import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../../../domain/entities/coordinates.dart';
import '../../../../domain/entities/maneuver.dart';
import '../../../../domain/entities/maneuver_type.dart';
import '../entities/simulated_maneuver_step.dart';
import 'tripper_ble_service.dart';
import 'tripper_protocol.dart';

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

/// Servicio desacoplado que orquesta la simulación virtual de navegación
/// y su sincronización opcional con el Royal Enfield Tripper Pod físico.
///
/// Principios clave:
/// 1. Aislamiento estricto: No modifica coordenadas GPS reales ni interfiere con navegación real.
/// 2. Determinismo: 8 maniobras predecibles y reproducibles sin requerir internet.
/// 3. Compatibilidad física: Envía al Pod únicamente instrucciones con codificación validada en hardware.
/// 4. Desconexión protegida: Al detener no envía CMD_SET_TIME ni desconecta BLE localmente.
class NavigationSimulatorService extends ChangeNotifier {
  final TripperBleService? _bleService;
  final List<SimulatedManeuverStep> _steps;

  SimulationStatus _status = SimulationStatus.stopped;
  SimulationSpeed _speed = SimulationSpeed.kmh30;
  bool _transmitToBle = false;
  bool _nightMode = false;

  int _currentStepIndex = 0;
  double _currentVirtualDistanceMeters = 0.0;
  Timer? _tickerTimer;
  final Duration _tickInterval;

  String? _lastSimulatedInstruction;
  String? _lastTransmittedHex;
  DateTime? _lastTransmissionTime;
  String? _lastTransmissionResult;
  String? _lastError;
  int _generatedInstructionsCount = 0;
  int _transmittedInstructionsCount = 0;

  NavigationSimulatorService({
    TripperBleService? bleService,
    List<SimulatedManeuverStep>? customSteps,
    Duration tickInterval = const Duration(seconds: 1),
    bool transmitToBleDefault = false,
  }) : _bleService = bleService,
       _steps = customSteps ?? _buildDefaultDeterministicScenario(),
       _tickInterval = tickInterval,
       _transmitToBle = transmitToBleDefault {
    _resetStepDistance();
  }

  // --- Getters de estado ---
  SimulationStatus get status => _status;
  SimulationSpeed get speed => _speed;
  bool get isRunning => _status == SimulationStatus.running;
  bool get isPaused => _status == SimulationStatus.paused;
  bool get isStopped => _status == SimulationStatus.stopped;
  bool get isCompleted => _status == SimulationStatus.completed;
  bool get transmitToBle => _transmitToBle;
  bool get nightMode => _nightMode;

  int get currentStepIndex => _currentStepIndex;
  int get totalSteps => _steps.length;
  List<SimulatedManeuverStep> get steps => List.unmodifiable(_steps);

  SimulatedManeuverStep get currentStep {
    if (_steps.isEmpty) {
      throw StateError('La lista de maniobras de simulación está vacía.');
    }
    return _steps[_currentStepIndex.clamp(0, _steps.length - 1)];
  }

  double get currentVirtualDistanceMeters => _currentVirtualDistanceMeters;

  /// Distancia restante total calculada sumando el paso actual y los posteriores.
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

  // --- Getters de telemetría y diagnóstico ---
  String? get lastSimulatedInstruction => _lastSimulatedInstruction;
  String? get lastTransmittedHex => _lastTransmittedHex;
  DateTime? get lastTransmissionTime => _lastTransmissionTime;
  String? get lastTransmissionResult => _lastTransmissionResult;
  String? get lastError => _lastError;
  int get generatedInstructionsCount => _generatedInstructionsCount;
  int get transmittedInstructionsCount => _transmittedInstructionsCount;

  // --- Controles de simulación ---

  /// Inicia o reinicia la simulación virtual.
  void start() {
    if (_status == SimulationStatus.completed) {
      reset();
    }
    if (_status == SimulationStatus.running) return;

    _status = SimulationStatus.running;
    _startTimer();
    _syncCurrentManeuver();
    notifyListeners();
  }

  /// Pausa el avance temporal del simulador manteniendo el progreso actual.
  void pause() {
    if (_status != SimulationStatus.running) return;
    _stopTimer();
    _status = SimulationStatus.paused;
    notifyListeners();
  }

  /// Reanuda la simulación desde el punto y distancia exactos en que fue pausada.
  void resume() {
    if (_status != SimulationStatus.paused) return;
    _status = SimulationStatus.running;
    _startTimer();
    _syncCurrentManeuver();
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

  /// Detiene y finaliza la simulación, limpiando tareas periódicas y avisando al BLE.
  void stop() {
    _stopTimer();
    _status = SimulationStatus.stopped;
    if (_transmitToBle) {
      _bleService?.stopNavigation();
    }
    notifyListeners();
  }

  /// Reinicia el simulador al primer paso (0% de avance).
  void reset() {
    _stopTimer();
    _status = SimulationStatus.stopped;
    _currentStepIndex = 0;
    _resetStepDistance();
    if (_transmitToBle) {
      _bleService?.stopNavigation();
    }
    notifyListeners();
  }

  /// Configura la velocidad virtual (10, 30 o 60 km/h).
  void setSpeed(SimulationSpeed newSpeed) {
    if (_speed == newSpeed) return;
    _speed = newSpeed;
    notifyListeners();
  }

  /// Habilita o deshabilita la transmisión física de tramas al Tripper Pod.
  void setTransmitToBle(bool enable) {
    if (_transmitToBle == enable) return;
    _transmitToBle = enable;
    if (_status == SimulationStatus.running) {
      if (enable) {
        _syncCurrentManeuver();
      } else {
        _bleService?.stopNavigation();
        _lastTransmissionResult = 'Transmisión física desactivada (simulación local)';
      }
    }
    notifyListeners();
  }

  /// Activa o desactiva el modo nocturno para el cálculo de bits de intensidad.
  void setNightMode(bool enable) {
    if (_nightMode == enable) return;
    _nightMode = enable;
    if (_status == SimulationStatus.running && _transmitToBle) {
      _syncCurrentManeuver();
    }
    notifyListeners();
  }

  /// Avanza manualmente al siguiente paso sin esperar al temporizador.
  void stepNext() {
    if (_currentStepIndex < _steps.length - 1) {
      _currentStepIndex++;
      _resetStepDistance();
      _syncCurrentManeuver();
    } else {
      _currentVirtualDistanceMeters = 0.0;
      _status = SimulationStatus.completed;
      _stopTimer();
      if (_transmitToBle) {
        _bleService?.stopNavigation();
      }
    }
    notifyListeners();
  }

  /// Retrocede manualmente al paso anterior.
  void stepPrevious() {
    if (_currentStepIndex > 0) {
      _currentStepIndex--;
      _resetStepDistance();
      if (_status == SimulationStatus.completed) {
        _status = SimulationStatus.paused;
      }
      _syncCurrentManeuver();
      notifyListeners();
    }
  }

  /// Salto directo a un índice de maniobra específico.
  void jumpToStep(int index) {
    if (index < 0 || index >= _steps.length) return;
    _currentStepIndex = index;
    _resetStepDistance();
    _syncCurrentManeuver();
    notifyListeners();
  }

  /// Sincroniza explícitamente la maniobra y distancia virtual actual hacia el transporte BLE.
  Future<bool> syncCurrentManeuver() => _syncCurrentManeuver();

  /// Avanza el avance temporal un delta de tiempo explícito en segundos (ideal para tests y simulación fina).
  void advanceTime(double seconds) {
    if (_status != SimulationStatus.running) return;

    final distanceDelta = _speed.metersPerSecond * seconds;
    _currentVirtualDistanceMeters -= distanceDelta;

    if (_currentVirtualDistanceMeters <= 0.0) {
      if (_currentStepIndex < _steps.length - 1) {
        _currentStepIndex++;
        _resetStepDistance();
        _syncCurrentManeuver();
      } else {
        _currentVirtualDistanceMeters = 0.0;
        _status = SimulationStatus.completed;
        _stopTimer();
        if (_transmitToBle) {
          _bleService?.stopNavigation();
        }
      }
    } else {
      // Si la distancia cambió notablemente en el mismo paso, actualizar telemetría
      _lastSimulatedInstruction =
          '${currentStep.stepNumber}. ${currentStep.maneuver.instructionText} (${_currentVirtualDistanceMeters.toInt()}m)';
    }

    notifyListeners();
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

  Future<bool> _syncCurrentManeuver() async {
    _generatedInstructionsCount++;
    final step = currentStep;
    final distInt = _currentVirtualDistanceMeters.toInt().clamp(0, 65535);
    _lastSimulatedInstruction =
        '${step.stepNumber}. ${step.maneuver.instructionText} (${distInt}m)';

    if (!_transmitToBle) {
      _lastTransmissionResult =
          'Simulación local activa (transmisión BLE desactivada)';
      return false;
    }

    final ble = _bleService;
    if (ble == null) {
      _lastTransmissionResult = 'Servicio BLE no inyectado en el simulador.';
      return false;
    }

    if (!ble.currentState.isReadyForNavigation) {
      _lastTransmissionResult =
          'Tripper Pod no conectado o no autenticado (${ble.currentState.displayName}).';
      return false;
    }

    if (!step.isSupportedByTripper || step.tripperManeuverCode == null) {
      _lastTransmissionResult =
          '[OMITIDO] Maniobra no compatible con hardware: ${step.compatibilityNote}';
      return false;
    }

    final packet = step.buildProtocolPacket(
      distanceMeters: distInt,
      nightMode: _nightMode,
    );

    if (packet == null) {
      _lastTransmissionResult = 'Error al construir trama binaria.';
      return false;
    }

    final hex = TripperProtocol.toHexString(packet);
    _lastTransmittedHex = hex;
    _lastTransmissionTime = DateTime.now();

    try {
      final ok = await ble.sendRawPacket(packet);
      if (ok) {
        _transmittedInstructionsCount++;
        _lastTransmissionResult =
            'OK (Escritura GATT aceptada en Android. Verificar visualmente en Pod).';
      } else {
        _lastTransmissionResult =
            'Fallo de escritura en característica GATT de RE_DISP.';
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
        compatibilityNote:
            'Código verificado 0x15 (Giro derecha, aproximación 250m)',
      ),

      // 4. Giro a la derecha (próximo / activo)
      SimulatedManeuverStep(
        stepNumber: 4,
        maneuver: Maneuver(
          instructionText: 'Gira a la derecha en Cll. 72',
          type: ManeuverType.right,
          location: Coordinates(4.6600, -74.0595),
          roadName: 'Calle 72',
          distanceMeters: 25.0,
        ),
        initialDistanceMeters: 25,
        isSupportedByTripper: true,
        tripperManeuverCode: TripperProtocol.maneuverTurnRight,
        compatibilityNote:
            'Código verificado 0x15 (Giro activo 25m, intensidad 0x40)',
      ),

      // 5. Continuar recto
      SimulatedManeuverStep(
        stepNumber: 5,
        maneuver: Maneuver(
          instructionText: 'Continúa recto por Cll. 72 durante 400 metros',
          type: ManeuverType.straight,
          location: Coordinates(4.6605, -74.0560),
          roadName: 'Calle 72',
          distanceMeters: 400.0,
        ),
        initialDistanceMeters: 400,
        isSupportedByTripper: true,
        tripperManeuverCode: TripperProtocol.maneuverStraight,
        compatibilityNote: 'Código verificado 0x09 (Recto 400m)',
      ),

      // 6. Aproximación a un giro a la izquierda
      SimulatedManeuverStep(
        stepNumber: 6,
        maneuver: Maneuver(
          instructionText:
              'En 300 m, prepárate para girar a la izquierda por Cra. 15',
          type: ManeuverType.left,
          location: Coordinates(4.6610, -74.0530),
          roadName: 'Carrera 15',
          distanceMeters: 300.0,
        ),
        initialDistanceMeters: 300,
        isSupportedByTripper: true,
        tripperManeuverCode: TripperProtocol.maneuverTurnLeft,
        compatibilityNote:
            'Código verificado 0x14 (Giro izquierda, aproximación 300m)',
      ),

      // 7. Giro a la izquierda (próximo / activo)
      SimulatedManeuverStep(
        stepNumber: 7,
        maneuver: Maneuver(
          instructionText: 'Gira a la izquierda en Cra. 15 hacia el norte',
          type: ManeuverType.left,
          location: Coordinates(4.6620, -74.0520),
          roadName: 'Carrera 15',
          distanceMeters: 20.0,
        ),
        initialDistanceMeters: 20,
        isSupportedByTripper: true,
        tripperManeuverCode: TripperProtocol.maneuverTurnLeft,
        compatibilityNote:
            'Código verificado 0x14 (Giro activo 20m, intensidad 0x40)',
      ),

      // 8. Llegada al destino
      SimulatedManeuverStep(
        stepNumber: 8,
        maneuver: Maneuver(
          instructionText: 'Has llegado a tu destino. ¡Fin de ruta!',
          type: ManeuverType.arrive,
          location: Coordinates(4.6660, -74.0510),
          roadName: 'Cra. 15 con Cll. 76',
          distanceMeters: 0.0,
        ),
        initialDistanceMeters: 0,
        isSupportedByTripper: true,
        tripperManeuverCode: TripperProtocol.maneuverDestination,
        compatibilityNote: 'Código verificado 0x00 (Destino alcanzado)',
      ),
    ];
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }
}
