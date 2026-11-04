import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../../../domain/entities/coordinates.dart';
import '../../../../domain/entities/maneuver.dart';
import '../../../../domain/entities/maneuver_type.dart';
import '../../../../domain/services/route_progress_calculator.dart';
import '../../domain/entities/calculated_route.dart';
import '../../domain/entities/destination.dart';
import '../../domain/entities/gps_position.dart';
import '../../domain/entities/gpx_tracking_status.dart';
import '../../domain/entities/imported_gpx_route.dart';
import '../../domain/entities/road_curvature.dart';
import '../../domain/entities/tripper_connection_state.dart';
import '../../domain/entities/tripper_maneuver_payload.dart';
import '../../domain/repositories/session_repository.dart';
import '../../domain/services/auto_navigation_source_arbiter.dart';
import '../../domain/services/location_service.dart';
import '../../domain/services/navigation_diagnostic_logger.dart';
import '../../domain/services/navigation_maneuver_engine.dart';
import '../../domain/services/navigation_source.dart';
import '../../domain/services/tripper_ble_service.dart';
import '../../domain/services/tripper_protocol.dart';
import '../../domain/services/voice_navigation_service.dart';
import '../../presentation/state/gpx_route_tracker.dart';
import 'flutter_blue_plus_tripper_service.dart';
import 'flutter_tts_voice_navigation_service.dart';
import 'geolocator_location_service.dart';

/// Administrador centralizado y persistente de la sesión de navegación interna.
///
/// Garantiza un ciclo de vida desacoplado de los widgets de pantalla:
/// - La navegación no se destruye al cambiar de pestaña, ir a Ajustes o volver a Home.
/// - Permanece activa en segundo plano mediante Android Foreground Service y BLE.
/// - Prioriza la navegación interna frente a notificaciones externas en modo AUTO.
/// - Implementa control de cadencia y reintentos hacia el display del Tripper Pod.
class InternalNavigationSessionManager extends ChangeNotifier {
  static InternalNavigationSessionManager? _instance;

  static InternalNavigationSessionManager get instance =>
      _instance ??= InternalNavigationSessionManager();

  @visibleForTesting
  static void setMockInstance(InternalNavigationSessionManager? mock) {
    _instance = mock;
  }

  @visibleForTesting
  static void resetForTesting() {
    _instance?.stopSession(notifyHardware: false);
    _instance = null;
  }

  CalculatedRoute? _activeRoute;
  Destination? _activeDestination;
  GpxRouteTracker? _activeTracker;
  final NavigationManeuverEngine _maneuverEngine = NavigationManeuverEngine();
  RoadCurvatureInfo? _currentCurvatureInfo;
  int _activeRouteVersion = 1;

  LocationService _locationService = const GeolocatorLocationService();
  TripperBleService _tripperBleService = FlutterBluePlusTripperService();
  VoiceNavigationService _voiceService = FlutterTtsVoiceNavigationService();
  AutoNavigationSourceArbiter? _arbiter;
  SelectedNavigationSourceType Function()? _selectedSourceProvider;

  bool _isNavigating = false;
  NavigationManeuverStep? _lastResolvedStep;
  GpsPosition? _lastGpsPosition;
  double? _riderHeading;
  double? _accuracyMeters;

  // Control de cadencia BLE
  int? _lastBleStepIndex;
  ManeuverType? _lastBleManeuverType;
  int? _lastBleDistanceMeters;
  DateTime? _lastBleSentAt;

  StreamSubscription<TripperConnectionState>? _bleStateSubscription;

  // Callbacks para eventos clave
  void Function(Coordinates)? onOffRouteDetected;
  void Function()? onDestinationReached;

  // Getters
  bool get isNavigating => _isNavigating;
  CalculatedRoute? get activeRoute => _activeRoute;
  Destination? get activeDestination => _activeDestination;
  GpxRouteTracker? get activeTracker => _activeTracker;
  NavigationManeuverEngine get maneuverEngine => _maneuverEngine;
  NavigationManeuverStep? get lastResolvedStep => _lastResolvedStep;
  RoadCurvatureInfo? get currentCurvatureInfo => _currentCurvatureInfo;
  int get activeRouteVersion => _activeRouteVersion;
  GpsPosition? get lastGpsPosition => _lastGpsPosition;
  double? get riderHeading => _riderHeading;
  double? get accuracyMeters => _accuracyMeters;

  /// Inicia o sustituye una sesión de navegación interna activa.
  Future<bool> startSession({
    required CalculatedRoute route,
    Destination? destination,
    LocationService? locationService,
    TripperBleService? bleService,
    VoiceNavigationService? voiceService,
    AutoNavigationSourceArbiter? arbiter,
    SelectedNavigationSourceType Function()? selectedSourceProvider,
    RouteProgressCalculator calculator = const RouteProgressCalculator(),
    SessionRepository? sessionRepository,
    RoadCurvatureInfo? curvatureInfo,
  }) async {
    _activeRoute = route;
    _activeDestination = destination;
    _currentCurvatureInfo = curvatureInfo;
    _locationService = locationService ?? _locationService;
    _tripperBleService = bleService ?? _tripperBleService;
    _voiceService = voiceService ?? _voiceService;
    _arbiter = arbiter ?? _arbiter ?? AutoNavigationSourceArbiter.instance;
    _selectedSourceProvider = selectedSourceProvider ?? _selectedSourceProvider;

    // 1. Declarar a AutoNavigationSourceArbiter que la navegación interna está activa
    _arbiter?.setInternalNavigationActive(true);

    // 2. Notificar inicio al logger de diagnóstico
    final correlationId =
        'internal_nav_${DateTime.now().millisecondsSinceEpoch}';
    NavigationDiagnosticLogger.logCorrelatedEvent(
      step: CorrelatedBridgeTraceStep.internalNavStarted,
      eventId: correlationId,
      source: 'InternalNavigation',
      availableContent:
          'route="${route.summary}", dest="${destination?.title ?? route.destination.toString()}", steps=${route.routePlan.maneuvers.length}',
      result: 'session_started',
    );

    // 3. Preparar tracker con soporte Foreground Service
    _activeTracker?.removeListener(_onTrackerProgress);
    _activeTracker?.dispose();

    final gpxCompatible = ImportedGpxRoute.fromCalculatedRoute(route);
    _activeTracker = GpxRouteTracker(
      route: gpxCompatible,
      locationService: _locationService,
      calculator: calculator,
      sessionRepository: sessionRepository,
      routeVersion: _activeRouteVersion,
    );

    _maneuverEngine.setRoute(route);
    _voiceService.resetGuidance();

    _activeTracker!.addListener(_onTrackerProgress);

    // Iniciar seguimiento GPS con notificación persistente de servicio Foreground
    final started = await _activeTracker!.startTracking(
      enableBackgroundTracking: true,
    );

    if (started) {
      _isNavigating = true;
      _lastBleStepIndex = null;
      _lastBleManeuverType = null;
      _lastBleDistanceMeters = null;
      _lastBleSentAt = null;

      _bleStateSubscription?.cancel();
      _bleStateSubscription = _tripperBleService.stateStream.listen(
        _onBleStateChanged,
      );

      _voiceService.speak(
        'Iniciando navegación hacia ${destination?.title ?? "tu destino"}.',
      );
      notifyListeners();
      return true;
    } else {
      _isNavigating = false;
      _arbiter?.setInternalNavigationActive(false);
      notifyListeners();
      return false;
    }
  }

  void _onBleStateChanged(TripperConnectionState state) {
    if (state.isReadyForNavigation && _isNavigating) {
      _lastBleStepIndex = null;
      _lastBleManeuverType = null;
      _lastBleDistanceMeters = null;
      _lastBleSentAt = null;
      _dispatchCurrentManeuverToBle(force: true);
    }
  }

  void _onTrackerProgress() {
    if (!_isNavigating || _activeTracker == null) return;

    final pos = _activeTracker!.currentPosition;
    if (pos != null) {
      _lastGpsPosition = pos;
      _riderHeading = pos.headingDegrees;
      _accuracyMeters = pos.accuracyMeters;

      final step = _maneuverEngine.resolveStep(
        currentCoordinates: pos.coordinates,
        progress: _activeTracker!.currentProgress,
        currentSegmentIndex: _activeTracker!.currentSegmentIndex,
        gpsAccuracy: pos.accuracyMeters,
        gpsSpeed: pos.speedKmh,
        movementHeading: pos.headingDegrees,
      );

      if (step != null) {
        _lastResolvedStep = step;
        _voiceService.processManeuverGuidance(
          maneuverIndex: step.maneuverIndex,
          maneuver: step.activeManeuver,
          distanceToManeuverMeters: step.distanceToManeuverMeters,
          currentSpeedKmh: pos.speedKmh ?? 0.0,
        );
      }

      _dispatchCurrentManeuverToBle();
    }

    if (_activeTracker!.status == GpxTrackingStatus.offRoute) {
      _voiceService.announceOffRoute();
      if (pos != null) {
        onOffRouteDetected?.call(pos.coordinates);
      }
    } else if (_activeTracker!.status == GpxTrackingStatus.completed) {
      _voiceService.announceDestinationReached();
      stopSession();
      onDestinationReached?.call();
    }

    notifyListeners();
  }

  /// Despacha la maniobra actual al hardware Tripper Pod respetando cadencia y fuente.
  void _dispatchCurrentManeuverToBle({bool force = false}) {
    if (!_isNavigating) return;

    final selected =
        _selectedSourceProvider?.call() ?? SelectedNavigationSourceType.auto;
    final isAllowedSource =
        selected == SelectedNavigationSourceType.internal ||
        selected == SelectedNavigationSourceType.auto;

    if (!isAllowedSource ||
        !_tripperBleService.currentState.isReadyForNavigation) {
      return;
    }

    final step = _lastResolvedStep ?? _fallbackStraightStep();
    if (step == null) return;

    final opcode = TripperProtocol.mapManeuverToTripperCode(
      step.activeManeuver.type,
    );

    if (opcode == null) {
      _tripperBleService.clearActiveNavPacket(
        reason:
            'Maniobra interna desconocida (${step.activeManeuver.type.name})',
      );
      return;
    }

    final dist = step.distanceToManeuverMeters.round().clamp(0, 99999);
    final now = DateTime.now();

    // Comprobar política de cadencia:
    // - Enviar si stepIndex o tipo de maniobra cambió
    // - Enviar si delta de distancia >= 10m
    // - Enviar si transcurrieron >= 1500ms desde el último envío
    // - Enviar si force == true (ej. reconexión BLE)
    final stepChanged =
        _lastBleStepIndex != step.maneuverIndex ||
        _lastBleManeuverType != step.activeManeuver.type;
    final distDelta = (_lastBleDistanceMeters != null)
        ? (dist - _lastBleDistanceMeters!).abs()
        : 9999;
    final elapsedMs = (_lastBleSentAt != null)
        ? now.difference(_lastBleSentAt!).inMilliseconds
        : 99999;

    if (force || stepChanged || distDelta >= 10 || elapsedMs >= 1500) {
      _lastBleStepIndex = step.maneuverIndex;
      _lastBleManeuverType = step.activeManeuver.type;
      _lastBleDistanceMeters = dist;
      _lastBleSentAt = now;

      final payload = TripperManeuverPayload.fromManeuver(
        type: step.activeManeuver.type,
        distanceMeters: dist,
        nextStreet: step.activeManeuver.roadName ?? '',
        timestamp: now,
      );

      _tripperBleService.sendManeuver(payload);

      NavigationDiagnosticLogger.logCorrelatedEvent(
        step: CorrelatedBridgeTraceStep.internalManeuverGenerated,
        eventId: 'ble_tx_${now.millisecondsSinceEpoch}',
        source: 'InternalNavigation',
        availableContent:
            'opcode=0x${opcode.toRadixString(16).padLeft(2, "0")}, dist=${dist}m, road="${payload.nextStreet}"',
        result: 'dispatched_to_ble',
      );
    }
  }

  NavigationManeuverStep? _fallbackStraightStep() {
    if (_activeTracker == null || _activeRoute == null) return null;
    return NavigationManeuverStep(
      activeManeuver: Maneuver(
        type: ManeuverType.straight,
        location: _activeRoute!.destination,
        instructionText: 'Continuar por la vía principal',
        roadName: _activeRoute!.summary.isNotEmpty
            ? _activeRoute!.summary
            : 'Carretera',
      ),
      distanceToManeuverMeters: _activeTracker!.remainingDistanceMeters,
      maneuverIndex: 9999,
      isLastManeuver: false,
    );
  }

  /// Actualiza la ruta activa tras un recálculo exitoso manteniendo la sesión viva.
  Future<void> updateRouteAfterRecalculation(CalculatedRoute newRoute) async {
    _activeRoute = newRoute;
    _activeRouteVersion++;
    _maneuverEngine.setRoute(newRoute);

    final gpxCompatible = ImportedGpxRoute.fromCalculatedRoute(newRoute);
    _activeTracker?.removeListener(_onTrackerProgress);
    _activeTracker?.dispose();

    _activeTracker = GpxRouteTracker(
      route: gpxCompatible,
      locationService: _locationService,
      calculator: const RouteProgressCalculator(),
      routeVersion: _activeRouteVersion,
    );

    _activeTracker!.addListener(_onTrackerProgress);
    await _activeTracker!.startTracking(enableBackgroundTracking: true);

    _lastBleStepIndex = null;
    _lastBleManeuverType = null;
    _lastBleDistanceMeters = null;
    _lastBleSentAt = null;

    NavigationDiagnosticLogger.logCorrelatedEvent(
      step: CorrelatedBridgeTraceStep.internalRecalculationStarted,
      eventId: 'recalc_v$_activeRouteVersion',
      source: 'InternalNavigation',
      availableContent:
          'version=$_activeRouteVersion, summary="${newRoute.summary}"',
      result: 'recalculated_route_active',
    );

    notifyListeners();
  }

  /// Detiene la navegación interna de forma limpia.
  Future<void> stopSession({bool notifyHardware = true}) async {
    if (!_isNavigating && _activeTracker == null) return;

    _isNavigating = false;
    _arbiter?.setInternalNavigationActive(false);

    _activeTracker?.removeListener(_onTrackerProgress);
    await _activeTracker?.stopTracking();
    _activeTracker?.dispose();
    _activeTracker = null;

    _bleStateSubscription?.cancel();
    _bleStateSubscription = null;

    _maneuverEngine.clear();
    await _voiceService.stop();
    _voiceService.resetGuidance();

    if (notifyHardware) {
      _tripperBleService.clearActiveNavPacket(
        reason: 'Navegación interna finalizada',
      );
      _tripperBleService.stopNavigation();
    }

    _activeRoute = null;
    _activeDestination = null;
    _lastResolvedStep = null;
    _currentCurvatureInfo = null;
    _lastBleStepIndex = null;
    _lastBleManeuverType = null;
    _lastBleDistanceMeters = null;
    _lastBleSentAt = null;

    NavigationDiagnosticLogger.logCorrelatedEvent(
      step: CorrelatedBridgeTraceStep.internalNavEnded,
      eventId: 'internal_nav_stop_${DateTime.now().millisecondsSinceEpoch}',
      source: 'InternalNavigation',
      availableContent: 'reason="Session stopped"',
      result: 'session_stopped',
    );

    notifyListeners();
  }

  @override
  void dispose() {
    stopSession();
    super.dispose();
  }
}
