import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../../../domain/entities/coordinates.dart';
import '../../../../domain/entities/route_progress.dart';
import '../../../../domain/services/route_progress_calculator.dart';
import '../../domain/entities/gps_position.dart';
import '../../domain/entities/gpx_tracking_status.dart';
import '../../domain/entities/imported_gpx_route.dart';
import '../../domain/entities/navigation_session.dart';
import '../../domain/repositories/session_repository.dart';
import '../../domain/services/location_service.dart';
import '../../infrastructure/services/geolocator_location_service.dart';

/// Controlador y máquina de estados para el seguimiento GPS en tiempo real
/// de una ruta GPX importada, integrando [RouteProgressCalculator].
class GpxRouteTracker extends ChangeNotifier {
  final ImportedGpxRoute route;
  final LocationService _locationService;
  final RouteProgressCalculator _calculator;
  final SessionRepository? _sessionRepository;
  final DateTime Function() _clock;

  // Umbrales de configuración
  final double offRouteThresholdMeters;
  final int offRouteFilterSamples;
  final double maxAccuracyThresholdMeters;
  final double destinationProximityMeters;
  final int lookaheadSegments;
  final Duration gpsTimeoutDuration;
  final bool isDemoMode;

  // Estado del seguimiento
  GpxTrackingStatus _status = GpxTrackingStatus.idle;
  GpsPosition? _lastPosition;
  RouteProgress? _currentProgress;
  String? _statusMessage;
  String? _permissionError;
  String? _lastGpsError;

  // Telemetría acumulada
  int _lastKnownSegmentIndex = 0;
  double _monotonicDistanceTraveled = 0.0;
  double _offRouteDistanceMeters = 0.0;
  int _consecutiveOffRouteSamples = 0;

  DateTime? _sessionStartTime;
  DateTime? _lastPositionTime;
  Duration? _lastPositionInterval;
  int _totalPositionsReceived = 0;
  Duration _sessionDuration = Duration.zero;
  int _validSamplesCount = 0;
  double _sumAccuracy = 0.0;
  double? _maxSpeedKmh;

  NavigationSession? _lastSavedSession;

  // Suscripciones y temporizadores
  StreamSubscription<GpsPosition>? _positionSubscription;
  Timer? _gpsLostTimer;
  Timer? _elapsedTimer;

  // Rastro reciente (últimas 40 lecturas para dibujar en el lienzo)
  final List<Coordinates> _recentTrail = [];

  // Registro de posiciones con telemetría completa durante la sesión
  final List<GpsPosition> _recordedPositions = [];
  bool _enableBackgroundTracking = false;

  GpxRouteTracker({
    required this.route,
    LocationService? locationService,
    RouteProgressCalculator calculator = const RouteProgressCalculator(),
    SessionRepository? sessionRepository,
    DateTime Function()? clock,
    this.offRouteThresholdMeters = 45.0,
    this.offRouteFilterSamples = 3,
    this.maxAccuracyThresholdMeters = 65.0,
    this.destinationProximityMeters = 50.0,
    this.lookaheadSegments = 8,
    this.gpsTimeoutDuration = const Duration(seconds: 12),
    this.isDemoMode = false,
  }) : _locationService = locationService ?? const GeolocatorLocationService(),
       _calculator = calculator,
       _sessionRepository = sessionRepository,
       _clock = clock ?? DateTime.now;

  // Getters de estado
  GpxTrackingStatus get status => _status;
  bool get isTracking =>
      _status == GpxTrackingStatus.tracking ||
      _status == GpxTrackingStatus.offRoute ||
      _status == GpxTrackingStatus.lowAccuracy;
  bool get isPaused => _status == GpxTrackingStatus.paused;
  bool get isSearching => _status == GpxTrackingStatus.searchingGps;
  bool get isCompleted => _status == GpxTrackingStatus.completed;

  GpsPosition? get currentPosition => _lastPosition;
  RouteProgress? get currentProgress => _currentProgress;
  String? get statusMessage => _statusMessage;
  String? get permissionError => _permissionError;
  String? get lastGpsError => _lastGpsError;

  DateTime? get lastPositionTime => _lastPositionTime;
  int get lastPositionAgeSeconds => _lastPositionTime != null
      ? _clock().difference(_lastPositionTime!).inSeconds
      : -1;
  bool get isPositionStale =>
      _lastPositionTime == null || lastPositionAgeSeconds > 10;
  Duration? get lastPositionInterval => _lastPositionInterval;
  int get totalPositionsReceived => _totalPositionsReceived;

  double get offRouteDistanceMeters => _offRouteDistanceMeters;
  double get distanceTraveledMeters => _monotonicDistanceTraveled;
  double get remainingDistanceMeters =>
      (route.totalGeographicDistanceMeters - _monotonicDistanceTraveled).clamp(
        0.0,
        route.totalGeographicDistanceMeters,
      );
  double get progressPercentage {
    if (route.totalGeographicDistanceMeters == 0.0) return 100.0;
    return ((_monotonicDistanceTraveled / route.totalGeographicDistanceMeters) *
            100.0)
        .clamp(0.0, 100.0);
  }

  double? get currentSpeedKmh => _lastPosition?.speedKmh;
  double? get maxSpeedKmh => _maxSpeedKmh;
  Duration get sessionDuration => _sessionDuration;
  int get validSamplesCount => _validSamplesCount;
  double get averageAccuracyMeters =>
      _validSamplesCount > 0 ? (_sumAccuracy / _validSamplesCount) : 0.0;
  List<Coordinates> get recentTrail => List.unmodifiable(_recentTrail);
  List<GpsPosition> get recordedPositions =>
      List.unmodifiable(_recordedPositions);
  bool get isBackgroundEnabled => _enableBackgroundTracking;
  NavigationSession? get lastSavedSession => _lastSavedSession;

  /// Inicia el seguimiento satelital de la ruta previa verificación de permisos.
  ///
  /// Si [enableBackgroundTracking] es verdadero, solicita iniciar el servicio en primer
  /// plano con notificación persistente para mantener la navegación activa al bloquear
  /// el dispositivo.
  Future<bool> startTracking({bool enableBackgroundTracking = true}) async {
    _cancelSubscriptions();
    _enableBackgroundTracking = enableBackgroundTracking;
    _status = GpxTrackingStatus.searchingGps;
    _statusMessage = 'Verificando permisos y conectando con el sensor GPS...';
    _permissionError = null;
    notifyListeners();

    // 1. Comprobar permisos
    final permission = await _locationService.requestPermission();
    if (permission != LocationPermissionResult.granted) {
      _status = GpxTrackingStatus.stopped;
      switch (permission) {
        case LocationPermissionResult.denied:
          _permissionError =
              'Permiso de ubicación denegado. Se requiere acceso a la ubicación para seguir la ruta.';
          break;
        case LocationPermissionResult.deniedForever:
          _permissionError =
              'Permiso de ubicación denegado permanentemente. Actívalo en los Ajustes del sistema.';
          break;
        case LocationPermissionResult.serviceDisabled:
          _permissionError =
              'El GPS del teléfono está desactivado. Enciende la ubicación para continuar.';
          break;
        case LocationPermissionResult.granted:
          break;
      }
      _statusMessage = _permissionError;
      notifyListeners();
      return false;
    }

    // 2. Iniciar contadores de sesión
    _sessionStartTime ??= _clock();
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_status != GpxTrackingStatus.paused &&
          _status != GpxTrackingStatus.stopped) {
        _sessionDuration += const Duration(seconds: 1);
        notifyListeners();
      }
    });

    _resetGpsTimeout();

    // 3. Suscripción única al flujo de posiciones
    _positionSubscription = _locationService
        .getPositionStream(
          enableBackgroundNotification: enableBackgroundTracking,
          notificationTitle: 'REstelar — Ruta activa: ${route.name}',
          notificationText: 'Siguiendo ruta en segundo plano para motocicleta',
        )
        .listen(
          _handleNewPosition,
          onError: (error) {
            _status = GpxTrackingStatus.gpsLost;
            _lastGpsError = error.toString();
            _statusMessage = 'Error en el proveedor de GPS: $error';
            notifyListeners();
          },
          cancelOnError: false,
        );

    return true;
  }

  /// Pausa el seguimiento de la ruta sin finalizar la sesión.
  void pauseTracking() {
    if (!isTracking && _status != GpxTrackingStatus.searchingGps) return;
    _positionSubscription?.pause();
    _gpsLostTimer?.cancel();
    _status = GpxTrackingStatus.paused;
    _statusMessage = 'Seguimiento pausado.';
    notifyListeners();
  }

  /// Reanuda el seguimiento pausado.
  void resumeTracking() {
    if (_status != GpxTrackingStatus.paused) return;
    _status = GpxTrackingStatus.searchingGps;
    _statusMessage = 'Reanudando señal GPS...';
    _resetGpsTimeout();
    _positionSubscription?.resume();
    notifyListeners();
  }

  /// Detiene y finaliza la sesión de navegación, registrando las métricas locales.
  Future<void> stopTracking({bool isCompleted = false}) async {
    _cancelSubscriptions();

    _status = isCompleted
        ? GpxTrackingStatus.completed
        : GpxTrackingStatus.stopped;
    _statusMessage = isCompleted
        ? '¡Has llegado a tu destino! Ruta completada.'
        : 'Seguimiento finalizado.';

    final now = _clock();
    final session = NavigationSession(
      id: 'session_${now.millisecondsSinceEpoch}',
      routeId: route.name,
      routeName: route.name,
      startTime: _sessionStartTime ?? now,
      endTime: now,
      duration: _sessionDuration,
      distanceTraveledMeters: _monotonicDistanceTraveled,
      totalRouteDistanceMeters: route.totalGeographicDistanceMeters,
      progressPercentage: progressPercentage,
      validGpsSamplesCount: _validSamplesCount,
      averageAccuracyMeters: averageAccuracyMeters,
      maxSpeedKmh: _maxSpeedKmh,
      isCompleted: isCompleted,
    );

    _lastSavedSession = session;

    if (_sessionRepository != null) {
      try {
        await _sessionRepository.saveSession(session);
      } catch (_) {
        // No bloquear la interfaz si falla el guardado de sesión
      }
    }

    notifyListeners();
  }

  void _handleNewPosition(GpsPosition pos) {
    _resetGpsTimeout();
    _lastPosition = pos;
    _totalPositionsReceived++;
    final now = _clock();
    if (_lastPositionTime != null) {
      _lastPositionInterval = now.difference(_lastPositionTime!);
    }
    _lastPositionTime = now;
    _lastGpsError = null;

    // 1. Filtrar lecturas con precisión deficiente
    if (pos.accuracyMeters > maxAccuracyThresholdMeters) {
      if (_status != GpxTrackingStatus.offRoute) {
        _status = GpxTrackingStatus.lowAccuracy;
        _statusMessage =
            'Precisión GPS baja (±${pos.accuracyMeters.toStringAsFixed(0)} m). Esperando mejor señal.';
      }
      notifyListeners();
      return;
    }

    // 2. Acumular estadísticas de calidad GPS
    _validSamplesCount++;
    _sumAccuracy += pos.accuracyMeters;
    if (pos.speedKmh != null) {
      if (_maxSpeedKmh == null || pos.speedKmh! > _maxSpeedKmh!) {
        _maxSpeedKmh = pos.speedKmh!;
      }
    }

    // Guardar punto en el rastro reciente
    _recentTrail.add(pos.coordinates);
    if (_recentTrail.length > 50) {
      _recentTrail.removeAt(0);
    }

    // Registrar posición completa con telemetría para historial de sesión
    _recordedPositions.add(pos);
    if (_recordedPositions.length > 5000) {
      _recordedPositions.removeAt(0);
    }

    // 3. Proyectar sobre la geometría de la ruta con RouteProgressCalculator
    final geometry = route.allCoordinates;
    if (geometry.length < 2) {
      _status = GpxTrackingStatus.tracking;
      notifyListeners();
      return;
    }

    // Asegurar que el lastKnownSegmentIndex no exceda el límite
    final int maxValidSegment = geometry.length - 2;
    final int safeSegmentIndex = _lastKnownSegmentIndex.clamp(
      0,
      maxValidSegment,
    );

    try {
      final progress = _calculator.calculate(
        geometry: geometry,
        currentPosition: pos.coordinates,
        totalDistanceMeters: route.totalGeographicDistanceMeters,
        lastKnownSegmentIndex: safeSegmentIndex,
        maxSegmentLookahead: lookaheadSegments,
      );

      _currentProgress = progress;
      _offRouteDistanceMeters = progress.distanceToRouteMeters;

      // 4. Lógica de detección de desvío y auto-recuperación
      if (progress.distanceToRouteMeters > offRouteThresholdMeters) {
        _consecutiveOffRouteSamples++;
        if (_consecutiveOffRouteSamples >= offRouteFilterSamples) {
          _status = GpxTrackingStatus.offRoute;
          _statusMessage =
              'Desvío de ruta detectado (+${progress.distanceToRouteMeters.toStringAsFixed(0)} m fuera del trazado).';
        }
      } else {
        _consecutiveOffRouteSamples = 0;
        _status = GpxTrackingStatus.tracking;
        _statusMessage = 'Siguiendo ruta GPX.';

        // Avanzar segmento y progreso de forma monotónica sin retrocesos erráticos
        _lastKnownSegmentIndex = progress.closestSegmentIndex;
        if (progress.distanceTraveledMeters >= _monotonicDistanceTraveled) {
          _monotonicDistanceTraveled = progress.distanceTraveledMeters;
        }
      }

      // 5. Verificación de finalización de ruta (cercanía a destino y avance)
      final distanceToDestination = pos.coordinates.distanceTo(
        route.destination,
      );
      if (distanceToDestination <= destinationProximityMeters &&
          progressPercentage >= 85.0) {
        _monotonicDistanceTraveled = route.totalGeographicDistanceMeters;
        stopTracking(isCompleted: true);
        return;
      }
    } catch (e) {
      _statusMessage = 'Cálculo de posición en curso...';
    }

    notifyListeners();
  }

  void _resetGpsTimeout() {
    _gpsLostTimer?.cancel();
    _gpsLostTimer = Timer(gpsTimeoutDuration, () {
      if (isTracking || _status == GpxTrackingStatus.searchingGps) {
        _status = GpxTrackingStatus.gpsLost;
        _statusMessage =
            'Señal satelital perdida. Esperando reanudación de coordenadas GPS...';
        notifyListeners();
      }
    });
  }

  void _cancelSubscriptions() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _gpsLostTimer?.cancel();
    _gpsLostTimer = null;
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
  }

  @override
  void dispose() {
    _cancelSubscriptions();
    super.dispose();
  }
}
