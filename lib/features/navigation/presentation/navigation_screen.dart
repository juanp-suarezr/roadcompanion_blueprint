import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/widgets/storm_badge.dart';
import '../../../../domain/entities/coordinates.dart';
import '../../../../domain/entities/maneuver.dart';
import '../../../../domain/services/route_progress_calculator.dart';
import '../domain/entities/calculated_route.dart';
import '../domain/entities/destination.dart';
import '../domain/entities/gps_position.dart';
import '../domain/entities/imported_gpx_route.dart';
import '../domain/entities/navigation_issue_report.dart';
import '../domain/entities/saved_favorite_route.dart';
import '../domain/repositories/session_repository.dart';
import '../domain/services/geocoding_service.dart';
import '../domain/services/location_service.dart';
import '../domain/services/navigation_diagnostic_logger.dart';
import '../domain/services/routing_service.dart';
import '../domain/services/smart_navigation_memory_service.dart';
import '../domain/services/voice_navigation_service.dart';
import '../domain/services/navigation_maneuver_engine.dart';
import '../infrastructure/services/geolocator_location_service.dart';
import '../infrastructure/services/nominatim_geocoding_service.dart';
import '../infrastructure/services/osrm_routing_service.dart';
import '../infrastructure/services/flutter_tts_voice_navigation_service.dart';
import '../domain/entities/gpx_tracking_status.dart';
import '../domain/services/tripper_ble_service.dart';
import '../infrastructure/services/flutter_blue_plus_tripper_service.dart';
import 'screens/tripper_diagnostic_screen.dart';
import 'demo_navigation_controller.dart';
import 'state/gpx_route_tracker.dart';
import 'state/imported_route_state.dart';
import 'widgets/active_turn_by_turn_hud.dart';
import 'widgets/destination_search_sheet.dart';
import 'widgets/favorite_routes_sheet.dart';
import 'widgets/gpx_live_tracking_panel.dart';
import 'widgets/gpx_route_card.dart';
import 'widgets/gpx_track_view.dart';
import 'widgets/maneuver_display.dart';
import 'widgets/navigation_permission_dialog.dart';
import 'widgets/navigation_report_sheet.dart';
import 'widgets/navigation_session_diagnostic_sheet.dart';
import 'widgets/progress_stats_bar.dart';
import 'widgets/real_map_widget.dart';
import 'widgets/route_overview_card.dart';
import 'widgets/saved_routes_sheet.dart';
import 'widgets/schematic_road_view.dart';
import 'widgets/session_summary_dialog.dart';
import 'widgets/simulation_controls.dart';

/// Modos de operación disponibles en la pantalla de navegación.
enum NavigationScreenMode {
  /// Mapa cartográfico interactivo real con búsqueda de destinos y enrutamiento vial OSRM.
  realMap,

  /// Seguimiento satelital de ruta GPX importada.
  gpx,

  /// Simulación interactiva de demostración con datos puros del dominio (Honda → Norcasia).
  demo,
}

/// Pantalla principal de navegación de REstelar.
///
/// Integra tres experiencias complementarias:
/// 1. Mapa cartográfico real (OpenStreetMap / CartoDB Dark Matter) con búsqueda y cálculo de rutas.
/// 2. Seguimiento y biblioteca de rutas GPX.
/// 3. Simulación determinista de demostración.
class NavigationScreen extends StatefulWidget {
  final ImportedRouteState? routeState;
  final LocationService? locationService;
  final SessionRepository? sessionRepository;
  final RouteProgressCalculator? calculator;
  final GeocodingService? geocodingService;
  final RoutingService? routingService;
  final SmartNavigationMemoryService? memoryService;
  final TripperBleService? tripperBleService;
  final VoiceNavigationService? voiceService;
  final NavigationManeuverEngine? maneuverEngine;
  final NavigationScreenMode? initialMode;

  const NavigationScreen({
    super.key,
    this.routeState,
    this.locationService,
    this.sessionRepository,
    this.calculator,
    this.geocodingService,
    this.routingService,
    this.memoryService,
    this.tripperBleService,
    this.voiceService,
    this.maneuverEngine,
    this.initialMode,
  });

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  late final DemoNavigationController _demoController;
  late final MapController _mapController;

  late final LocationService _locationService;
  late final GeocodingService _geocodingService;
  late final RoutingService _routingService;
  late final SmartNavigationMemoryService _memoryService;
  late final TripperBleService _tripperBleService;
  late final VoiceNavigationService _voiceService;
  late final NavigationManeuverEngine _maneuverEngine;

  ImportedRouteState? _localRouteState;
  late NavigationScreenMode _currentMode;

  // Estado del mapa y enrutamiento en tiempo real
  Destination? _selectedDestination;
  CalculatedRoute? _calculatedRoute;
  List<CalculatedRoute> _availableRoutes = const [];
  int _selectedRouteIndex = 0;
  bool _isCalculatingRoute = false;
  String? _routeErrorMessage;
  bool _isNavigatingCalculatedRoute = false;

  // Estado de ubicación GPS actual para el mapa
  Coordinates? _currentRiderCoordinates;
  double? _riderHeading;
  double? _accuracyMeters;
  StreamSubscription<GpsPosition>? _gpsLocationSubscription;

  // Tracker activo (para rutas calculadas o GPX)
  GpxRouteTracker? _activeTracker;
  String? _lastTrackedRouteName;

  @override
  void initState() {
    super.initState();
    _demoController = DemoNavigationController();
    _mapController = MapController();

    _memoryService = widget.memoryService ?? SmartNavigationMemoryService();
    _memoryService.load();

    _locationService =
        widget.locationService ?? const GeolocatorLocationService();
    _geocodingService = widget.geocodingService ?? NominatimGeocodingService();
    _routingService =
        widget.routingService ??
        OsrmRoutingService(memoryService: _memoryService);
    _tripperBleService =
        widget.tripperBleService ?? FlutterBluePlusTripperService();
    _voiceService = widget.voiceService ?? FlutterTtsVoiceNavigationService();
    _maneuverEngine = widget.maneuverEngine ?? NavigationManeuverEngine();

    _currentMode = widget.initialMode ?? NavigationScreenMode.realMap;

    _voiceService.init();
    _initGpsListener();
  }

  ImportedRouteState _resolveRouteState(BuildContext context) {
    if (widget.routeState != null) return widget.routeState!;
    final scoped = ImportedRouteScope.maybeOf(context);
    if (scoped != null) return scoped;
    return _localRouteState ??= ImportedRouteState();
  }

  void _startListeningGps() {
    _gpsLocationSubscription?.cancel();
    _gpsLocationSubscription = _locationService.getPositionStream().listen((
      pos,
    ) {
      if (!mounted) return;
      setState(() {
        _currentRiderCoordinates = pos.coordinates;
        _riderHeading = pos.headingDegrees;
        _accuracyMeters = pos.accuracyMeters;
      });
    }, onError: (_) {});
  }

  void _initGpsListener() {
    _locationService.checkPermission().then((permission) {
      if (permission == LocationPermissionResult.granted && mounted) {
        _startListeningGps();
      }
    });
  }

  void _syncTracker(ImportedRouteState state) {
    final route = state.currentRoute;
    if (route == null) {
      if (_currentMode == NavigationScreenMode.gpx) {
        _activeTracker?.dispose();
        _activeTracker = null;
        _lastTrackedRouteName = null;
        _currentMode = NavigationScreenMode.realMap;
      }
      return;
    }

    if (_activeTracker == null || _lastTrackedRouteName != route.name) {
      _activeTracker?.dispose();
      _lastTrackedRouteName = route.name;
      _activeTracker = GpxRouteTracker(
        route: route,
        locationService: _locationService,
        calculator: widget.calculator ?? const RouteProgressCalculator(),
        sessionRepository: widget.sessionRepository,
      );
      _currentMode = NavigationScreenMode.gpx;
    }
  }

  @override
  void dispose() {
    _activeTracker?.removeListener(_onActiveTrackerProgress);
    _voiceService.dispose();
    _gpsLocationSubscription?.cancel();
    _demoController.dispose();
    _activeTracker?.dispose();
    _localRouteState?.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _openDestinationSearch() async {
    final destination = await DestinationSearchSheet.show(
      context,
      geocodingService: _geocodingService,
      userLocation: _currentRiderCoordinates,
    );

    if (destination != null && mounted) {
      _selectDestinationAndRoute(destination);
    }
  }

  Future<void> _selectDestinationAndRoute(Destination destination) async {
    setState(() {
      _selectedDestination = destination;
      _isCalculatingRoute = true;
      _routeErrorMessage = null;
      _calculatedRoute = null;
      _availableRoutes = const [];
      _selectedRouteIndex = 0;
      _isNavigatingCalculatedRoute = false;
    });

    // Origen: ubicación actual del usuario o fallback céntrico
    final Coordinates origin =
        _currentRiderCoordinates ?? Coordinates(5.0689, -75.5174);

    NavigationDiagnosticLogger.logDestinationSelected(
      destination: destination,
      origin: origin,
    );

    try {
      final routes = await _routingService.calculateRoutesWithAlternatives(
        origin: origin,
        destination: destination.coordinates,
      );

      if (!mounted) return;
      if (routes.isEmpty) {
        setState(() {
          _isCalculatingRoute = false;
          _routeErrorMessage =
              'No se encontraron rutas viales disponibles hacia "${destination.title}".';
        });
        return;
      }

      setState(() {
        _availableRoutes = routes;
        _selectedRouteIndex = 0;
        _calculatedRoute = routes.first;
        _isCalculatingRoute = false;
        _currentMode = NavigationScreenMode.realMap;
      });

      // Centrar el mapa en todos los trazados calculados para que el usuario pueda compararlos
      final allCoords = routes.expand((r) => r.geometry).toList();
      _fitMapToCoordinates(
        allCoords.isNotEmpty ? allCoords : routes.first.geometry,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCalculatingRoute = false;
        _routeErrorMessage =
            'No se pudo calcular la ruta vial hacia "${destination.title}". Verifica tu conexión.';
      });
    }
  }

  void _selectRouteAlternative(int index) {
    if (index < 0 || index >= _availableRoutes.length) return;
    setState(() {
      _selectedRouteIndex = index;
      _calculatedRoute = _availableRoutes[index];
    });
    // Ajustar encuadre al cambiar de ruta seleccionada
    _fitMapToCoordinates(_availableRoutes[index].geometry);
  }

  Future<void> _openFavoriteRoutes() async {
    final fav = await FavoriteRoutesSheet.show(
      context,
      memoryService: _memoryService,
    );
    if (fav != null && mounted) {
      final destination = Destination(
        id: 'fav_${fav.id}',
        title: fav.destinationTitle,
        subtitle:
            fav.notes ??
            'Ruta guardada (${fav.distanceKm.toStringAsFixed(1)} km, ${fav.formattedDuration})',
        coordinates: fav.destination,
      );
      _selectDestinationAndRoute(destination);
    }
  }

  Future<void> _handleSaveFavoriteRoute(
    CalculatedRoute route,
    Destination destination,
  ) async {
    final originCoord = _currentRiderCoordinates ?? route.origin;
    final fav = SavedFavoriteRoute(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: destination.title,
      origin: originCoord,
      originTitle: 'Mi ubicación',
      destination: destination.coordinates,
      destinationTitle: destination.title,
      savedAt: DateTime.now(),
      distanceKm: route.totalDistanceKm,
      estimatedDuration: route.estimatedDuration,
      notes: route.summary,
      preferences: {
        'hasTolls': false,
        'hasUnpaved': route.validation.warnings.any(
          (w) => w.toLowerCase().contains('destapad'),
        ),
      },
    );
    await _memoryService.saveFavoriteRoute(fav);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ruta a "${destination.title}" guardada en tus favoritas.',
          ),
          backgroundColor: AppColors.cyanLuminous,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleReportRoadIssue({
    CalculatedRoute? route,
    Coordinates? initialLocation,
  }) async {
    final loc =
        initialLocation ??
        _currentRiderCoordinates ??
        (route != null && route.geometry.isNotEmpty
            ? route.geometry.first
            : Coordinates(4.833360, -75.672461));

    final report = await NavigationReportSheet.show(
      context,
      location: loc,
      initialRoadSegment: route?.summary,
      memoryService: _memoryService,
    );

    if (report != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Reporte vial "${report.typeLabel}" registrado en la memoria de REstelar.',
          ),
          backgroundColor: AppColors.cardNavy,
          behavior: SnackBarBehavior.floating,
        ),
      );

      // Si el reporte es un portón cerrado o destino inaccesible confirmado y coincide con la ruta activa, recalcular
      if (report.status == ReportVerificationStatus.confirmed &&
          (report.type == NavigationIssueType.lockedGate ||
              report.type == NavigationIssueType.inaccessibleDestination)) {
        if (_selectedDestination != null) {
          _selectDestinationAndRoute(_selectedDestination!);
        }
      }
    }
  }

  void _fitMapToCoordinates(List<Coordinates> coords) {
    if (coords.isEmpty) return;
    try {
      final latLngs = coords
          .map((c) => LatLng(c.latitude, c.longitude))
          .toList();
      final bounds = LatLngBounds.fromPoints(latLngs);
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50.0)),
      );
    } catch (_) {}
  }

  void _onActiveTrackerProgress() {
    if (!_isNavigatingCalculatedRoute || _activeTracker == null) return;

    final pos = _activeTracker!.currentPosition;
    if (pos != null) {
      if (mounted) {
        setState(() {
          _currentRiderCoordinates = pos.coordinates;
          _riderHeading = pos.headingDegrees;
          _accuracyMeters = pos.accuracyMeters;
        });
      }
      final step = _maneuverEngine.resolveStep(
        currentCoordinates: pos.coordinates,
        progress: _activeTracker!.currentProgress,
      );
      if (step != null) {
        _voiceService.processManeuverGuidance(
          maneuverIndex: step.maneuverIndex,
          maneuver: step.activeManeuver,
          distanceToManeuverMeters: step.distanceToManeuverMeters,
          currentSpeedKmh: pos.speedKmh ?? 0.0,
        );
      }
    }

    if (_activeTracker!.status == GpxTrackingStatus.offRoute) {
      _voiceService.announceOffRoute();
    } else if (_activeTracker!.status == GpxTrackingStatus.completed) {
      _voiceService.announceDestinationReached();
    }
  }

  Future<void> _startCalculatedRouteNavigation() async {
    if (_calculatedRoute == null) return;

    final hasPermission =
        await NavigationPermissionDialog.ensureLocationPermission(
          context,
          locationService: _locationService,
        );
    if (!hasPermission || !mounted) return;
    await NavigationPermissionDialog.ensureNotificationPermission();

    // Cancelar el listener pasivo de baja prioridad para no duplicar flujos de ubicación en segundo plano
    _gpsLocationSubscription?.cancel();
    _gpsLocationSubscription = null;

    final gpxCompatible = ImportedGpxRoute.fromCalculatedRoute(
      _calculatedRoute!,
    );

    _activeTracker?.removeListener(_onActiveTrackerProgress);
    _activeTracker?.dispose();
    _activeTracker = GpxRouteTracker(
      route: gpxCompatible,
      locationService: _locationService,
      calculator: widget.calculator ?? const RouteProgressCalculator(),
      sessionRepository: widget.sessionRepository,
    );

    _maneuverEngine.setRoute(_calculatedRoute!);
    _voiceService.resetGuidance();
    _activeTracker!.addListener(_onActiveTrackerProgress);

    final started = await _activeTracker!.startTracking();
    if (!mounted) return;

    if (started) {
      setState(() {
        _isNavigatingCalculatedRoute = true;
      });
      _voiceService.speak(
        'Iniciando navegación hacia ${_selectedDestination?.title ?? "tu destino"}.',
      );
    } else if (_activeTracker!.permissionError != null) {
      _startListeningGps();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_activeTracker!.permissionError!),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _cancelCalculatedRoute() {
    _activeTracker?.removeListener(_onActiveTrackerProgress);
    _voiceService.stop();
    _voiceService.resetGuidance();
    _maneuverEngine.clear();
    _activeTracker?.stopTracking();
    _startListeningGps();
    setState(() {
      _selectedDestination = null;
      _calculatedRoute = null;
      _availableRoutes = const [];
      _selectedRouteIndex = 0;
      _isNavigatingCalculatedRoute = false;
      _routeErrorMessage = null;
    });
  }

  Future<void> _handleImportGpx(ImportedRouteState state) async {
    final success = await state.importGpxRoute();
    if (!mounted) return;

    if (success) {
      setState(() {
        _currentMode = NavigationScreenMode.gpx;
        _cancelCalculatedRoute();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            state.infoMessage ?? 'Ruta GPX importada correctamente.',
          ),
          backgroundColor: AppColors.electricBlue,
          duration: const Duration(seconds: 3),
        ),
      );
    } else if (state.errorMessage == null && state.infoMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(state.infoMessage!),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _openSavedRoutes(ImportedRouteState state) {
    SavedRoutesSheet.show(
      context,
      savedRoutes: state.savedRoutes,
      activeRouteName: state.currentRoute?.name,
      onSelectRoute: (id) {
        state.selectSavedRoute(id);
        setState(() {
          _currentMode = NavigationScreenMode.gpx;
          _cancelCalculatedRoute();
        });
      },
      onDeleteRoute: (id) => state.deleteSavedRoute(id),
      onImportNew: () => _handleImportGpx(state),
    );
  }

  Future<void> _onStopSession(GpxRouteTracker tracker) async {
    _activeTracker?.removeListener(_onActiveTrackerProgress);
    await tracker.stopTracking();
    await _voiceService.stop();
    _voiceService.resetGuidance();
    _maneuverEngine.clear();
    _startListeningGps();
    if (!mounted) return;

    if (tracker.lastSavedSession != null) {
      await SessionSummaryDialog.show(context, tracker.lastSavedSession!);
    }
    setState(() {
      _isNavigatingCalculatedRoute = false;
    });
  }

  Future<void> _recenterMapOnUser() async {
    if (_currentRiderCoordinates != null) {
      _mapController.move(
        LatLng(
          _currentRiderCoordinates!.latitude,
          _currentRiderCoordinates!.longitude,
        ),
        15.5,
      );
      return;
    }

    final hasPermission =
        await NavigationPermissionDialog.ensureLocationPermission(
          context,
          locationService: _locationService,
        );
    if (!hasPermission || !mounted) return;

    _startListeningGps();
    try {
      final pos = await _locationService.getPositionStream().first.timeout(
        const Duration(seconds: 4),
      );
      if (mounted) {
        setState(() {
          _currentRiderCoordinates = pos.coordinates;
          _riderHeading = pos.headingDegrees;
          _accuracyMeters = pos.accuracyMeters;
        });
        _mapController.move(
          LatLng(pos.coordinates.latitude, pos.coordinates.longitude),
          15.5,
        );
      }
    } catch (_) {}
  }

  Future<void> _startGpxRouteTracking() async {
    if (_activeTracker == null) return;
    _activeTracker!.startTracking();
  }

  NavigationManeuverStep? _resolveCurrentManeuverStep() {
    if (_calculatedRoute == null) return null;
    final pos =
        _currentRiderCoordinates ??
        _activeTracker?.currentPosition?.coordinates;
    if (pos == null) return null;
    return _maneuverEngine.resolveStep(
      currentCoordinates: pos,
      progress: _activeTracker?.currentProgress,
    );
  }

  Maneuver? _resolveActiveManeuver() {
    final step = _resolveCurrentManeuverStep();
    if (step != null) {
      return step.activeManeuver;
    }
    if (_calculatedRoute == null ||
        _calculatedRoute!.routePlan.maneuvers.isEmpty) {
      return null;
    }
    return _calculatedRoute!.routePlan.maneuvers.first;
  }

  int get trackerRouteLength =>
      _activeTracker?.route.allCoordinates.length ?? 1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final routeState = _resolveRouteState(context);

    return ListenableBuilder(
      listenable: routeState,
      builder: (context, _) {
        _syncTracker(routeState);

        return Scaffold(
          resizeToAvoidBottomInset: false,
          appBar: AppBar(
            title: const Text('Navegación Asistida'),
            actions: [
              // Selector visual de modo (Mapa Real / GPX / Demo)
              _buildModeBadge(),
              IconButton(
                tooltip: 'Biblioteca de rutas GPX',
                icon: const Icon(Icons.folder_open_outlined),
                onPressed: () => _openSavedRoutes(routeState),
              ),
              IconButton(
                tooltip: 'Importar ruta GPX',
                icon: const Icon(Icons.file_open_outlined),
                onPressed: routeState.isLoading
                    ? null
                    : () => _handleImportGpx(routeState),
              ),
              if (_activeTracker != null)
                IconButton(
                  tooltip: 'Panel de Diagnóstico GPS',
                  icon: const Icon(
                    Icons.troubleshoot_rounded,
                    color: AppColors.cyanLuminous,
                  ),
                  onPressed: () {
                    NavigationSessionDiagnosticSheet.show(
                      context,
                      tracker: _activeTracker!,
                      maneuverEngine: _maneuverEngine,
                      voiceService: _voiceService,
                    );
                  },
                ),
              IconButton(
                tooltip: 'Laboratorio Tripper Pod & GPS',
                icon: const Icon(
                  Icons.two_wheeler_rounded,
                  color: AppColors.primaryGold,
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TripperDiagnosticScreen(
                        activeTracker: _activeTracker,
                        bleService: _tripperBleService,
                        voiceService: _voiceService,
                      ),
                    ),
                  );
                },
              ),
              PopupMenuButton<NavigationScreenMode>(
                tooltip: 'Modo de navegación',
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (mode) {
                  setState(() => _currentMode = mode);
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: NavigationScreenMode.realMap,
                    child: Row(
                      children: [
                        Icon(
                          Icons.map_rounded,
                          size: 18,
                          color: AppColors.success,
                        ),
                        SizedBox(width: 10),
                        Text('Mapa con GPS Real'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: NavigationScreenMode.demo,
                    child: Row(
                      children: [
                        Icon(
                          Icons.science_outlined,
                          size: 18,
                          color: AppColors.cyanLuminous,
                        ),
                        SizedBox(width: 10),
                        Text('Simulación DEMO'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: NavigationScreenMode.gpx,
                    child: Row(
                      children: [
                        Icon(
                          Icons.route_outlined,
                          size: 18,
                          color: AppColors.electricBlue,
                        ),
                        SizedBox(width: 10),
                        Text('Seguimiento GPX'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 6.0),
            ],
          ),
          body: SafeArea(child: _buildCurrentModeContent(isDark, routeState)),
        );
      },
    );
  }

  Widget _buildModeBadge() {
    switch (_currentMode) {
      case NavigationScreenMode.realMap:
        final hasFix = _currentRiderCoordinates != null;
        final accuracyText = _accuracyMeters != null
            ? ' (±${_accuracyMeters!.toStringAsFixed(0)}m)'
            : '';
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 7.0,
                vertical: 3.0,
              ),
              decoration: BoxDecoration(
                color: hasFix
                    ? AppColors.success.withValues(alpha: 0.15)
                    : AppColors.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(
                  color: hasFix
                      ? AppColors.success.withValues(alpha: 0.4)
                      : AppColors.warning.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    hasFix
                        ? Icons.gps_fixed_rounded
                        : Icons.gps_not_fixed_rounded,
                    size: 12.0,
                    color: hasFix ? AppColors.success : AppColors.warning,
                  ),
                  const SizedBox(width: 4.0),
                  Text(
                    hasFix ? 'GPS REAL$accuracyText' : 'BUSCANDO GPS',
                    style: TextStyle(
                      fontSize: 10.0,
                      fontWeight: FontWeight.w800,
                      color: hasFix ? AppColors.success : AppColors.warning,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () =>
                  setState(() => _currentMode = NavigationScreenMode.demo),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
              ),
              child: const Text(
                'DEMO',
                style: TextStyle(fontSize: 11.0, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      case NavigationScreenMode.gpx:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const StormBadge(
              label: 'GPX',
              icon: Icons.route_outlined,
              variant: StormBadgeVariant.success,
            ),
            TextButton(
              onPressed: () =>
                  setState(() => _currentMode = NavigationScreenMode.demo),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
              ),
              child: const Text(
                'DEMO',
                style: TextStyle(fontSize: 11.0, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      case NavigationScreenMode.demo:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const StormBadge(
              label: 'MODO DEMO',
              icon: Icons.science_outlined,
              variant: StormBadgeVariant.info,
            ),
            TextButton(
              onPressed: () =>
                  setState(() => _currentMode = NavigationScreenMode.realMap),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
              ),
              child: const Text(
                'GPS REAL',
                style: TextStyle(fontSize: 11.0, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
    }
  }

  Widget _buildCurrentModeContent(bool isDark, ImportedRouteState routeState) {
    if (_currentMode == NavigationScreenMode.demo) {
      return _buildDemoContent(isDark, routeState);
    }

    if (_currentMode == NavigationScreenMode.gpx && routeState.hasRoute) {
      return _buildGpxContent(isDark, routeState);
    }

    // Modo principal: Mapa Real interactivo con búsqueda y enrutamiento
    return _buildRealMapContent(isDark, routeState);
  }

  Widget _buildRealMapContent(bool isDark, ImportedRouteState routeState) {
    final activeGeometry = _calculatedRoute?.geometry;
    final unselectedGeometries = _availableRoutes
        .asMap()
        .entries
        .where((entry) => entry.key != _selectedRouteIndex)
        .map((entry) => entry.value.geometry)
        .toList();

    final double mapControlsBottomOffset = _isNavigatingCalculatedRoute
        ? 230.0
        : (_calculatedRoute != null ? 300.0 : 85.0);

    return Stack(
      children: [
        // 1. Visor del mapa cartográfico real
        Positioned.fill(
          child: RealMapWidget(
            mapController: _mapController,
            initialCenter: _currentRiderCoordinates != null
                ? LatLng(
                    _currentRiderCoordinates!.latitude,
                    _currentRiderCoordinates!.longitude,
                  )
                : const LatLng(5.0689, -75.5174),
            riderPosition: _currentRiderCoordinates,
            riderHeading: _riderHeading,
            accuracyMeters: _accuracyMeters,
            routeGeometry: activeGeometry,
            alternativeGeometries: unselectedGeometries,
            destinationCoordinates: _selectedDestination?.coordinates,
            onRecenter: _recenterMapOnUser,
            controlsBottomOffset: mapControlsBottomOffset,
          ),
        ),

        // 2. Barra superior de búsqueda (cuando NO se está navegando activamente)
        if (!_isNavigatingCalculatedRoute)
          Positioned(
            top: 14.0,
            left: 16.0,
            right: 16.0,
            child: _buildSearchBar(isDark),
          ),

        // 3. Indicador de cálculo de ruta en curso
        if (_isCalculatingRoute)
          Positioned(
            top: 80.0,
            left: 20.0,
            right: 20.0,
            child: _buildCalculatingBanner(isDark),
          ),

        // 4. Banner de error si la ruta falla
        if (_routeErrorMessage != null)
          Positioned(
            top: 80.0,
            left: 20.0,
            right: 20.0,
            child: _buildErrorBanner(_routeErrorMessage!),
          ),

        // Banner de error si la importación GPX falla
        if (routeState.errorMessage != null)
          Positioned(
            top: 80.0,
            left: 16.0,
            right: 16.0,
            child: _buildGpxErrorCard(routeState, isDark),
          ),

        // 5. Tarjeta de resumen y selección de alternativas (antes de iniciar navegación)
        if (_calculatedRoute != null &&
            _selectedDestination != null &&
            !_isNavigatingCalculatedRoute)
          Positioned(
            bottom: 16.0,
            left: 16.0,
            right: 16.0,
            child: RouteOverviewCard(
              destination: _selectedDestination!,
              routes: _availableRoutes.isNotEmpty
                  ? _availableRoutes
                  : [_calculatedRoute!],
              selectedRouteIndex: _selectedRouteIndex,
              onSelectRoute: _selectRouteAlternative,
              onStartNavigation: _startCalculatedRouteNavigation,
              onCancel: _cancelCalculatedRoute,
              onSaveFavorite: () {
                final currentRoute = _availableRoutes.isNotEmpty
                    ? _availableRoutes[_selectedRouteIndex]
                    : _calculatedRoute!;
                _handleSaveFavoriteRoute(currentRoute, _selectedDestination!);
              },
              onReportIssue: () {
                final currentRoute = _availableRoutes.isNotEmpty
                    ? _availableRoutes[_selectedRouteIndex]
                    : _calculatedRoute!;
                _handleReportRoadIssue(route: currentRoute);
              },
            ),
          ),

        // 6. HUD de navegación giro a giro en tiempo real (durante la navegación activa)
        if (_isNavigatingCalculatedRoute && _activeTracker != null)
          ListenableBuilder(
            listenable: _activeTracker!,
            builder: (context, _) {
              final step = _resolveCurrentManeuverStep();
              final activeManeuver =
                  step?.activeManeuver ?? _resolveActiveManeuver();
              final distanceMeters =
                  step?.distanceToManeuverMeters ??
                  (_activeTracker!.remainingDistanceMeters > 0
                      ? (_activeTracker!.remainingDistanceMeters / 10).clamp(
                          50.0,
                          500.0,
                        )
                      : 0.0);

              return ActiveTurnByTurnHud(
                tracker: _activeTracker!,
                currentManeuver: activeManeuver,
                distanceToManeuverMeters: distanceMeters,
                isVoiceMuted: _voiceService.isMuted,
                onToggleVoiceMute: () {
                  setState(() {
                    _voiceService.toggleMute();
                  });
                },
                onPause: _activeTracker!.pauseTracking,
                onResume: _activeTracker!.resumeTracking,
                onStop: () => _onStopSession(_activeTracker!),
                onOpenDiagnostics: () {
                  NavigationSessionDiagnosticSheet.show(
                    context,
                    tracker: _activeTracker!,
                    maneuverEngine: _maneuverEngine,
                    voiceService: _voiceService,
                  );
                },
              );
            },
          ),

        // Botón flotante para reportar problema vial durante la navegación activa
        if (_isNavigatingCalculatedRoute)
          Positioned(
            left: 16.0,
            bottom: 230.0,
            child: FloatingActionButton.small(
              heroTag: 'report_issue_btn',
              backgroundColor: isDark
                  ? AppColors.cardNavy
                  : AppColors.whiteSurface,
              foregroundColor: AppColors.warning,
              tooltip: 'Reportar incidencia vial o portón cerrado',
              onPressed: () => _handleReportRoadIssue(
                route: _calculatedRoute,
                initialLocation: _currentRiderCoordinates,
              ),
              child: const Icon(Icons.report_problem_outlined, size: 20.0),
            ),
          ),

        // 7. Botones flotantes inferiores: Importar ruta GPX y Rutas Favoritas
        if (!_isNavigatingCalculatedRoute && _calculatedRoute == null)
          Positioned(
            left: 16.0,
            bottom: 24.0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Material(
                  color: isDark ? AppColors.nightBlue : AppColors.whiteSurface,
                  elevation: 4.0,
                  borderRadius: BorderRadius.circular(24.0),
                  child: FilledButton.tonalIcon(
                    onPressed: () => _handleImportGpx(routeState),
                    icon: const Icon(Icons.file_upload_outlined, size: 16.0),
                    label: const Text('Importar ruta GPX'),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
                const SizedBox(width: 8.0),
                Material(
                  color: isDark ? AppColors.nightBlue : AppColors.whiteSurface,
                  elevation: 4.0,
                  borderRadius: BorderRadius.circular(24.0),
                  child: FilledButton.tonalIcon(
                    onPressed: _openFavoriteRoutes,
                    icon: const Icon(
                      Icons.star_rounded,
                      size: 18.0,
                      color: AppColors.cyanLuminous,
                    ),
                    label: const Text('Favoritas'),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Material(
      color: isDark ? AppColors.nightBlue : AppColors.whiteSurface,
      elevation: 6.0,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(16.0),
      child: InkWell(
        onTap: _openDestinationSearch,
        borderRadius: BorderRadius.circular(16.0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16.0),
            border: Border.all(
              color: isDark ? const Color(0xFF264660) : AppColors.silver,
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.search,
                color: isDark ? AppColors.cyanLuminous : AppColors.electricBlue,
                size: 22.0,
              ),
              const SizedBox(width: 12.0),
              Expanded(
                child: Text(
                  _selectedDestination?.title ??
                      'Buscar destino o municipio...',
                  style: TextStyle(
                    fontSize: 14.0,
                    fontWeight: FontWeight.w600,
                    color: _selectedDestination != null
                        ? (isDark
                              ? AppColors.coldWhite
                              : AppColors.primaryTextLight)
                        : (isDark
                              ? AppColors.secondaryText
                              : AppColors.secondaryTextLight),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_selectedDestination != null)
                IconButton(
                  icon: const Icon(Icons.close, size: 18.0),
                  onPressed: _cancelCalculatedRoute,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCalculatingBanner(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: BoxDecoration(
        color: isDark ? AppColors.nightBlue : AppColors.whiteSurface,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: AppColors.cyanLuminous),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10.0)],
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 20.0,
            height: 20.0,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          SizedBox(width: 14.0),
          Expanded(
            child: Text(
              'Calculando ruta vial con motor OSRM...',
              style: TextStyle(fontSize: 13.0, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
      decoration: BoxDecoration(
        color: const Color(0xFFFDEDED),
        borderRadius: BorderRadius.circular(10.0),
        border: Border.all(color: AppColors.error),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 20.0),
          const SizedBox(width: 10.0),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12.0, color: Color(0xFF5F2120)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16.0),
            onPressed: () => setState(() => _routeErrorMessage = null),
          ),
        ],
      ),
    );
  }

  Widget _buildGpxContent(bool isDark, ImportedRouteState routeState) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_activeTracker != null)
            ListenableBuilder(
              listenable: _activeTracker!,
              builder: (context, _) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GpxLiveTrackingPanel(
                      tracker: _activeTracker!,
                      onStart: _startGpxRouteTracking,
                      onPause: _activeTracker!.pauseTracking,
                      onResume: _activeTracker!.resumeTracking,
                      onStop: () => _onStopSession(_activeTracker!),
                    ),
                    const SizedBox(height: 14.0),
                    GpxTrackView(
                      route: routeState.currentRoute!,
                      currentRiderPosition:
                          _activeTracker!.currentPosition?.coordinates,
                      projectedPoint:
                          _activeTracker!.currentProgress?.projectedPoint,
                      recentTrail: _activeTracker!.recentTrail,
                      onRecenter: () => setState(() {}),
                    ),
                    const SizedBox(height: 14.0),
                    GpxRouteCard(
                      route: routeState.currentRoute!,
                      onClearRoute: () {
                        routeState.clearRoute();
                        setState(
                          () => _currentMode = NavigationScreenMode.demo,
                        );
                      },
                      onImportAnother: () => _openSavedRoutes(routeState),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildGpxErrorCard(ImportedRouteState routeState, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14.0),
      decoration: BoxDecoration(
        color: const Color(0xFFFDEDED),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: const Color(0xFFEF5350), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.error_outline,
                color: Color(0xFFC62828),
                size: 22.0,
              ),
              const SizedBox(width: 10.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Error al importar archivo GPX',
                      style: TextStyle(
                        fontSize: 13.0,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFB71C1C),
                      ),
                    ),
                    const SizedBox(height: 4.0),
                    Text(
                      routeState.errorMessage!,
                      style: const TextStyle(
                        fontSize: 12.0,
                        height: 1.3,
                        color: Color(0xFF5F2120),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18.0),
                color: const Color(0xFF5F2120),
                tooltip: 'Descartar error',
                onPressed: routeState.clearMessages,
              ),
            ],
          ),
          const SizedBox(height: 8.0),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _handleImportGpx(routeState),
              icon: const Icon(Icons.refresh, size: 16.0),
              label: const Text('Reintentar importación'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFB71C1C),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDemoContent(bool isDark, ImportedRouteState routeState) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (routeState.errorMessage != null) ...[
            _buildGpxErrorCard(routeState, isDark),
            const SizedBox(height: 14.0),
          ],
          // Banner de aviso de modo demo
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 14.0,
              vertical: 10.0,
            ),
            decoration: BoxDecoration(
              color: isDark ? AppColors.cardNavy : const Color(0xFFE9F2FA),
              borderRadius: BorderRadius.circular(10.0),
              border: Border.all(
                color: isDark ? AppColors.cyanLuminous : AppColors.electricBlue,
                width: 1.0,
              ),
            ),
            child: Row(
              children: [
                const StormBadge(
                  label: 'DEMO',
                  icon: Icons.science_outlined,
                  variant: StormBadgeVariant.info,
                ),
                const SizedBox(width: 10.0),
                Expanded(
                  child: Text(
                    'Simulación activa: Honda → La Dorada → Norcasia (54 km). Datos calculados con el motor de dominio puro.',
                    style: TextStyle(
                      fontSize: 12.0,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.coldWhite
                          : AppColors.primaryTextLight,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14.0),

          AnimatedBuilder(
            animation: _demoController,
            builder: (context, _) {
              final progress = _demoController.currentProgress;
              final maneuver = _demoController.currentManeuver;
              final distanceToManeuver =
                  _demoController.distanceToManeuverMeters;
              final totalDistance =
                  _demoController.routePlan.totalDistanceMeters;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ManeuverDisplay(
                    maneuver: maneuver,
                    distanceMeters: distanceToManeuver,
                  ),
                  const SizedBox(height: 14.0),
                  SchematicRoadView(
                    geometry: _demoController.geometry,
                    progressFraction: _demoController.stepFraction,
                  ),
                  const SizedBox(height: 14.0),
                  ProgressStatsBar(
                    progress: progress,
                    totalDistanceMeters: totalDistance,
                  ),
                  const SizedBox(height: 14.0),
                  SimulationControls(
                    isPlaying: _demoController.isPlaying,
                    onTogglePlayPause: _demoController.togglePlayPause,
                    onStepForward: _demoController.stepForward,
                    onStepBackward: _demoController.stepBackward,
                    onReset: _demoController.resetSimulation,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
