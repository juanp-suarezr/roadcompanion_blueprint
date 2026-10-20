import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/widgets/storm_badge.dart';
import '../domain/repositories/session_repository.dart';
import '../domain/services/location_service.dart';
import '../../../../domain/services/route_progress_calculator.dart';
import 'demo_navigation_controller.dart';
import 'state/gpx_route_tracker.dart';
import 'state/imported_route_state.dart';
import 'widgets/gpx_live_tracking_panel.dart';
import 'widgets/gpx_route_card.dart';
import 'widgets/gpx_track_view.dart';
import 'widgets/maneuver_display.dart';
import 'widgets/progress_stats_bar.dart';
import 'widgets/saved_routes_sheet.dart';
import 'widgets/schematic_road_view.dart';
import 'widgets/session_summary_dialog.dart';
import 'widgets/simulation_controls.dart';

/// Pantalla de navegación asistida de Road Companion.
///
/// Soporta dos modalidades:
/// 1. Demostración simulada pura (Honda → Norcasia).
/// 2. Seguimiento GPS en tiempo real sobre rutas GPX importadas y persistentes.
class NavigationScreen extends StatefulWidget {
  final ImportedRouteState? routeState;
  final LocationService? locationService;
  final SessionRepository? sessionRepository;
  final RouteProgressCalculator? calculator;

  const NavigationScreen({
    super.key,
    this.routeState,
    this.locationService,
    this.sessionRepository,
    this.calculator,
  });

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  late final DemoNavigationController _demoController;
  ImportedRouteState? _localRouteState;

  GpxRouteTracker? _activeTracker;
  String? _lastTrackedRouteName;

  @override
  void initState() {
    super.initState();
    _demoController = DemoNavigationController();
  }

  ImportedRouteState _resolveRouteState(BuildContext context) {
    if (widget.routeState != null) return widget.routeState!;
    final scoped = ImportedRouteScope.maybeOf(context);
    if (scoped != null) return scoped;
    return _localRouteState ??= ImportedRouteState();
  }

  void _syncTracker(ImportedRouteState state) {
    final route = state.currentRoute;
    if (route == null) {
      if (_activeTracker != null) {
        _activeTracker!.dispose();
        _activeTracker = null;
        _lastTrackedRouteName = null;
      }
      return;
    }

    if (_activeTracker == null || _lastTrackedRouteName != route.name) {
      _activeTracker?.dispose();
      _lastTrackedRouteName = route.name;
      _activeTracker = GpxRouteTracker(
        route: route,
        locationService: widget.locationService,
        calculator: widget.calculator ?? const RouteProgressCalculator(),
        sessionRepository: widget.sessionRepository,
      );
    }
  }

  @override
  void dispose() {
    _demoController.dispose();
    _activeTracker?.dispose();
    _localRouteState?.dispose();
    super.dispose();
  }

  Future<void> _handleImportGpx(ImportedRouteState state) async {
    final success = await state.importGpxRoute();
    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            state.infoMessage ?? 'Ruta GPX importada correctamente.',
          ),
          backgroundColor: AppColors.steelBlue,
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
      onSelectRoute: (id) => state.selectSavedRoute(id),
      onDeleteRoute: (id) => state.deleteSavedRoute(id),
      onImportNew: () => _handleImportGpx(state),
    );
  }

  Future<void> _onStopSession(GpxRouteTracker tracker) async {
    await tracker.stopTracking();
    if (!mounted) return;

    if (tracker.lastSavedSession != null) {
      await SessionSummaryDialog.show(context, tracker.lastSavedSession!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final routeState = _resolveRouteState(context);

    return ListenableBuilder(
      listenable: routeState,
      builder: (context, _) {
        _syncTracker(routeState);
        final hasImportedRoute = routeState.hasRoute;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Navegación Asistida'),
            actions: [
              // Botón de biblioteca de rutas guardadas
              IconButton(
                tooltip: 'Biblioteca de rutas GPX',
                icon: const Icon(Icons.folder_open_outlined),
                onPressed: () => _openSavedRoutes(routeState),
              ),
              // Botón de importar archivo
              IconButton(
                tooltip: 'Importar ruta GPX',
                icon: const Icon(Icons.file_open_outlined),
                onPressed: routeState.isLoading
                    ? null
                    : () => _handleImportGpx(routeState),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Center(
                  child: hasImportedRoute
                      ? const StormBadge(
                          label: 'GPX',
                          icon: Icons.map_outlined,
                          variant: StormBadgeVariant.success,
                        )
                      : const StormBadge(
                          label: 'DEMO',
                          icon: Icons.science_outlined,
                          variant: StormBadgeVariant.info,
                        ),
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 20.0,
                vertical: 12.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Estado de carga durante lectura o importación
                  if (routeState.isLoading) ...[
                    _buildLoadingCard(isDark),
                    const SizedBox(height: 14.0),
                  ],

                  // 2. Estado de error
                  if (routeState.errorMessage != null) ...[
                    _buildErrorCard(routeState, isDark),
                    const SizedBox(height: 14.0),
                  ],

                  // 3. Modo GPX Real
                  if (hasImportedRoute && _activeTracker != null) ...[
                    ListenableBuilder(
                      listenable: _activeTracker!,
                      builder: (context, _) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Banner de recordatorio de pantalla activa en primer plano
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12.0,
                                vertical: 8.0,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppColors.darkSurfaceVariant
                                    : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(8.0),
                                border: Border.all(
                                  color: isDark
                                      ? AppColors.steelBlue.withValues(
                                          alpha: 0.3,
                                        )
                                      : AppColors.silver,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.stay_current_portrait_outlined,
                                    size: 16.0,
                                    color: isDark
                                        ? AppColors.accentBlue
                                        : AppColors.steelBlue,
                                  ),
                                  const SizedBox(width: 8.0),
                                  Expanded(
                                    child: Text(
                                      'Mantén la pantalla activa durante la prueba. El seguimiento en segundo plano no está incluido en este MVP.',
                                      style: TextStyle(
                                        fontSize: 11.0,
                                        color: isDark
                                            ? AppColors.secondaryTextDark
                                            : AppColors.secondaryTextLight,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12.0),

                            // Panel de telemetría y controles de seguimiento GPS
                            GpxLiveTrackingPanel(
                              tracker: _activeTracker!,
                              onStart: _activeTracker!.startTracking,
                              onPause: _activeTracker!.pauseTracking,
                              onResume: _activeTracker!.resumeTracking,
                              onStop: () => _onStopSession(_activeTracker!),
                            ),
                            const SizedBox(height: 14.0),

                            // Visualizador esquemático del trazado con posición del motociclista en vivo
                            GpxTrackView(
                              route: routeState.currentRoute!,
                              currentRiderPosition:
                                  _activeTracker!.currentPosition?.coordinates,
                              projectedPoint: _activeTracker!
                                  .currentProgress
                                  ?.projectedPoint,
                              recentTrail: _activeTracker!.recentTrail,
                              onRecenter: () => setState(() {}),
                            ),
                            const SizedBox(height: 14.0),

                            // Tarjeta de metadatos de la ruta GPX
                            GpxRouteCard(
                              route: routeState.currentRoute!,
                              onClearRoute: routeState.clearRoute,
                              onImportAnother: () =>
                                  _openSavedRoutes(routeState),
                            ),
                            const SizedBox(height: 20.0),
                          ],
                        );
                      },
                    ),
                  ] else ...[
                    // 4. Modo Demostración simulada (fallback interactivo)
                    _buildDemoHeader(isDark, routeState),
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
                              onTogglePlayPause:
                                  _demoController.togglePlayPause,
                              onStepForward: _demoController.stepForward,
                              onStepBackward: _demoController.stepBackward,
                              onReset: _demoController.resetSimulation,
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 20.0),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoadingCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.whiteSurface,
        borderRadius: BorderRadius.circular(14.0),
        border: Border.all(
          color: isDark ? AppColors.accentBlue : AppColors.steelBlue,
          width: 1.0,
        ),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 24.0,
            height: 24.0,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(width: 16.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Procesando archivo GPX...',
                  style: TextStyle(
                    fontSize: 14.0,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppColors.primaryTextDark
                        : AppColors.primaryTextLight,
                  ),
                ),
                Text(
                  'Extrayendo tracks, segmentos y calculando distancias',
                  style: TextStyle(
                    fontSize: 12.0,
                    color: isDark
                        ? AppColors.secondaryTextDark
                        : AppColors.secondaryTextLight,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(ImportedRouteState routeState, bool isDark) {
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

  Widget _buildDemoHeader(bool isDark, ImportedRouteState routeState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Botón visible de acción para importar GPX
        Container(
          margin: const EdgeInsets.only(bottom: 12.0),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => _handleImportGpx(routeState),
                  icon: const Icon(Icons.file_upload_outlined, size: 18.0),
                  label: const Text(
                    'Importar ruta GPX',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14.0),
                  ),
                ),
              ),
              if (routeState.savedRoutes.isNotEmpty) ...[
                const SizedBox(width: 10.0),
                OutlinedButton.icon(
                  onPressed: () => _openSavedRoutes(routeState),
                  icon: const Icon(Icons.folder_outlined, size: 18.0),
                  label: Text('${routeState.savedRoutes.length} guardadas'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: 14.0,
                      horizontal: 14.0,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        // Aviso honesto de simulación
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.darkSurfaceVariant.withValues(alpha: 0.6)
                : const Color(0xFFE9F2FA),
            borderRadius: BorderRadius.circular(10.0),
            border: Border.all(
              color: isDark
                  ? AppColors.accentBlue.withValues(alpha: 0.3)
                  : AppColors.steelBlue.withValues(alpha: 0.3),
              width: 1.0,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 18.0,
                color: isDark ? AppColors.accentBlue : AppColors.steelBlue,
              ),
              const SizedBox(width: 10.0),
              Expanded(
                child: Text(
                  'Simulación activa: Honda → La Dorada → Norcasia (54 km). Datos calculados con el motor de dominio puro.',
                  style: TextStyle(
                    fontSize: 12.0,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.primaryTextDark
                        : AppColors.primaryTextLight,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
