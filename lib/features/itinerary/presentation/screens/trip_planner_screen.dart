import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:road_companion/road_companion.dart';

/// Pantalla minimalista de planificación de viajes multiparada en REstelar.
///
/// Permite al motociclista definir un origen, un destino final y paradas intermedias,
/// calcular el itinerario continuo en OSRM, explorar POIs sobre el corredor vial y exportar la ruta.
/// Estado de obtención y disponibilidad del origen GPS en el planificador.
enum GpsOriginStatus {
  idle,
  obtaining,
  available,
  serviceDisabled,
  permissionDenied,
  error,
}

/// Pantalla minimalista de planificación de viajes multiparada en REstelar.
///
/// Permite al motociclista definir un origen, un destino final y paradas intermedias,
/// calcular el itinerario continuo en OSRM, explorar POIs sobre el corredor vial y exportar la ruta.
class TripPlannerScreen extends StatefulWidget {
  final TripItinerary? initialItinerary;
  final RoutingService? routingService;
  final GeocodingService? geocodingService;
  final ExternalNavigationLauncher? navigationLauncher;
  final Coordinates? userCurrentLocation;
  final RoutePoiExplorerService? poiExplorerService;
  final LocationService? locationService;

  const TripPlannerScreen({
    super.key,
    this.initialItinerary,
    this.routingService,
    this.geocodingService,
    this.navigationLauncher,
    this.userCurrentLocation,
    this.poiExplorerService,
    this.locationService,
  });

  @override
  State<TripPlannerScreen> createState() => _TripPlannerScreenState();
}

class _TripPlannerScreenState extends State<TripPlannerScreen> {
  late RoutingService _routingService;
  late GeocodingService _geocodingService;
  late ExternalNavigationLauncher _launcher;
  late RoutePoiExplorerService _poiExplorer;
  late LocationService _locationService;

  late TripItinerary _itinerary;
  bool _isCalculatingRoute = false;
  String? _statusFeedback;
  String? _warningFeedback;

  // Control de origen automático por GPS
  GpsOriginStatus _gpsOriginStatus = GpsOriginStatus.idle;
  GpsPosition? _currentGpsPosition;
  bool _isOriginManual = false;
  String? _gpsWarningMessage;

  final MapController _mapController = MapController();
  bool _isExploringPois = false;
  bool _hasSearchedPois = false;
  String? _poiErrorMessage;
  List<RoutePoi> _discoveredPois = [];
  String _selectedPoiCategory = 'fuel';
  double _corridorRadiusMeters = 2000.0;
  RoutePoi? _selectedPoi;

  @override
  void initState() {
    super.initState();
    _routingService = widget.routingService ?? OsrmRoutingService();
    _geocodingService = widget.geocodingService ?? NominatimGeocodingService();
    _launcher = widget.navigationLauncher ?? UrlExternalNavigationLauncher();
    _poiExplorer = widget.poiExplorerService ?? RoutePoiExplorerService();
    _locationService =
        widget.locationService ?? const GeolocatorLocationService();

    final defaultDest = Destination(
      id: 'default_dest',
      title: 'Villa de Leyva',
      subtitle: 'Boyacá, Colombia',
      coordinates: Coordinates(5.6322, -73.5244),
    );

    if (widget.initialItinerary != null) {
      _itinerary = widget.initialItinerary!;
      if (_itinerary.origin.id == 'current_loc') {
        _isOriginManual = false;
        _fetchGpsOrigin();
      } else {
        _isOriginManual = true;
        _gpsOriginStatus = GpsOriginStatus.available;
      }
    } else {
      final now = DateTime.now();
      if (widget.userCurrentLocation != null) {
        final origin = Destination(
          id: 'current_loc',
          title: 'Mi ubicación actual',
          subtitle: 'GPS local',
          coordinates: widget.userCurrentLocation!,
        );
        _itinerary = TripItinerary(
          id: 'trip_${now.millisecondsSinceEpoch}',
          title: 'Mi Viaje en Moto',
          origin: origin,
          destination: defaultDest,
          createdAt: now,
          updatedAt: now,
        );
        _gpsOriginStatus = GpsOriginStatus.available;
        _isOriginManual = false;
      } else {
        // Marcador provisional mientras se obtiene el GPS real sin bloquear la interfaz
        final placeholderOrigin = Destination(
          id: 'current_loc',
          title: 'Mi ubicación actual',
          subtitle: 'Obteniendo GPS...',
          coordinates: Coordinates(0.0, 0.0),
        );
        _itinerary = TripItinerary(
          id: 'trip_${now.millisecondsSinceEpoch}',
          title: 'Mi Viaje en Moto',
          origin: placeholderOrigin,
          destination: defaultDest,
          createdAt: now,
          updatedAt: now,
        );
        _isOriginManual = false;
        _fetchGpsOrigin();
      }
    }
  }

  /// Consulta la posición GPS actual del dispositivo de manera no bloqueante.
  Future<void> _fetchGpsOrigin({bool force = false}) async {
    if (_isOriginManual && !force) return;

    setState(() {
      _gpsOriginStatus = GpsOriginStatus.obtaining;
      _gpsWarningMessage = null;
    });

    final enabled = await _locationService.isLocationServiceEnabled();
    if (!enabled) {
      if (mounted) {
        setState(() {
          _gpsOriginStatus = GpsOriginStatus.serviceDisabled;
        });
      }
      return;
    }

    final permission = await _locationService.checkPermission();
    if (permission == LocationPermissionResult.denied) {
      final req = await _locationService.requestPermission();
      if (req != LocationPermissionResult.granted) {
        if (mounted) {
          setState(() {
            _gpsOriginStatus = req == LocationPermissionResult.serviceDisabled
                ? GpsOriginStatus.serviceDisabled
                : GpsOriginStatus.permissionDenied;
          });
        }
        return;
      }
    } else if (permission == LocationPermissionResult.deniedForever) {
      if (mounted) {
        setState(() {
          _gpsOriginStatus = GpsOriginStatus.permissionDenied;
        });
      }
      return;
    } else if (permission == LocationPermissionResult.serviceDisabled) {
      if (mounted) {
        setState(() {
          _gpsOriginStatus = GpsOriginStatus.serviceDisabled;
        });
      }
      return;
    }

    try {
      final pos = await _locationService.getCurrentPosition(
        timeLimit: const Duration(seconds: 8),
      );

      if (!mounted) return;

      if (pos == null) {
        setState(() {
          _gpsOriginStatus = GpsOriginStatus.error;
        });
        return;
      }

      // Validar precisión y antigüedad
      String? warning;
      if (pos.accuracyMeters > 50.0) {
        warning =
            'Precisión GPS reducida (±${pos.accuracyMeters.toStringAsFixed(0)} m). '
            'Es recomendable esperar mejor señal a cielo abierto.';
      } else if (pos.age().inSeconds > 120) {
        final mins = (pos.age().inSeconds / 60).toStringAsFixed(1);
        warning =
            'Lectura GPS antigua ($mins min). Pulsa actualizar para refrescar tu posición.';
      }

      final updatedOrigin = Destination(
        id: 'current_loc',
        title: 'Mi ubicación actual',
        subtitle: 'GPS (±${pos.accuracyMeters.toStringAsFixed(0)} m)',
        coordinates: pos.coordinates,
      );

      setState(() {
        _currentGpsPosition = pos;
        _gpsOriginStatus = GpsOriginStatus.available;
        _gpsWarningMessage = warning;
        _isOriginManual = false;
        _itinerary = _itinerary.copyWith(
          origin: updatedOrigin,
          calculatedRoute: null,
        );
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _gpsOriginStatus = GpsOriginStatus.error;
        });
      }
    }
  }

  Future<void> _calculateRoute() async {
    if (!_isOriginManual) {
      if (_gpsOriginStatus == GpsOriginStatus.obtaining) {
        setState(() {
          _statusFeedback =
              'Obteniendo ubicación GPS, por favor espera un momento...';
        });
        return;
      }
      if (_gpsOriginStatus == GpsOriginStatus.serviceDisabled) {
        setState(() {
          _statusFeedback =
              'El GPS está desactivado. Actívalo o define el origen manualmente.';
        });
        return;
      }
      if (_gpsOriginStatus == GpsOriginStatus.permissionDenied) {
        setState(() {
          _statusFeedback =
              'Permiso de ubicación denegado. Concede permiso o define el origen manualmente.';
        });
        return;
      }
      if (_gpsOriginStatus == GpsOriginStatus.error) {
        setState(() {
          _statusFeedback =
              'Error al obtener GPS. Pulsa «Reintentar» o define el origen manualmente.';
        });
        return;
      }
      if (_itinerary.origin.coordinates.latitude == 0.0 &&
          _itinerary.origin.coordinates.longitude == 0.0) {
        setState(() {
          _statusFeedback =
              'Esperando ubicación GPS válida para calcular la ruta.';
        });
        return;
      }
    }

    setState(() {
      _isCalculatingRoute = true;
      _statusFeedback = null;
      _warningFeedback = null;
    });

    try {
      final waypoints = _itinerary.stops.map((s) => s.coordinates).toList();
      final route = await _routingService.calculateMultistopRoute(
        origin: _itinerary.origin.coordinates,
        waypoints: waypoints,
        destination: _itinerary.destination.coordinates,
      );

      setState(() {
        _itinerary = _itinerary.copyWith(
          calculatedRoute: route,
          updatedAt: DateTime.now(),
        );
        _statusFeedback =
            'Itinerario calculado: ${route.totalDistanceKm.toStringAsFixed(1)} km (${route.formattedDuration})';
      });
    } catch (e) {
      setState(() {
        _statusFeedback = 'Error al calcular itinerario: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isCalculatingRoute = false;
        });
      }
    }
  }

  Future<void> _searchPoisAlongRoute() async {
    final route = _itinerary.calculatedRoute;
    if (route == null || route.geometry.length < 2) {
      setState(() {
        _statusFeedback =
            'Calcula primero la ruta para buscar POIs sobre el recorrido.';
      });
      return;
    }

    setState(() {
      _isExploringPois = true;
      _poiErrorMessage = null;
      _hasSearchedPois = true;
      _selectedPoi = null;
    });

    try {
      final results = await _poiExplorer.findPoisAlongRoute(
        routeGeometry: route.geometry,
        category: _selectedPoiCategory,
        corridorRadiusMeters: _corridorRadiusMeters,
        rethrowErrors: true,
      );
      if (mounted) {
        setState(() {
          _discoveredPois = results;
          _isExploringPois = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isExploringPois = false;
          _poiErrorMessage =
              'Error de conexión al consultar puntos de interés: $e';
        });
      }
    }
  }

  void _clearDiscoveredPois() {
    setState(() {
      _discoveredPois = [];
      _selectedPoi = null;
      _hasSearchedPois = false;
      _poiErrorMessage = null;
    });
  }

  void _addPoiToItinerary(RoutePoi poi) {
    try {
      final newStop = poi.toTripStop(orderIndex: _itinerary.stops.length);
      setState(() {
        _itinerary = _itinerary.insertStopAtRoutePosition(
          newStop,
          distanceAlongRouteMeters: poi.distanceAlongRouteMeters,
          routeGeometry: _itinerary.calculatedRoute?.geometry,
        );
        _statusFeedback =
            'Parada añadida: "${poi.name}" en el km ${(poi.distanceAlongRouteMeters / 1000).toStringAsFixed(1)} de la ruta. Recalcula el itinerario para actualizar el tiempo total.';
      });
    } catch (e) {
      setState(() {
        _warningFeedback = 'No fue posible añadir la parada: $e';
      });
    }
  }

  Future<void> _exportToGoogleMaps() async {
    final result = await _launcher.launchGoogleMaps(
      _itinerary,
      maxWaypoints: 3,
    );
    setState(() {
      _warningFeedback = result.warningMessage;
      if (!result.success) {
        _statusFeedback =
            result.errorMessage ?? 'No fue posible abrir Google Maps.';
      } else {
        _statusFeedback = 'Itinerario enviado a Google Maps.';
      }
    });

    if (!result.success && mounted) {
      _showWarningDialog(
        'Aviso de Google Maps',
        result.errorMessage ?? 'No fue posible abrir Google Maps.',
      );
    } else if (result.warningMessage != null && mounted) {
      _showWarningDialog('Aviso de Google Maps', result.warningMessage!);
    }
  }

  Future<void> _exportToWaze() async {
    final result = await _launcher.launchWaze(_itinerary);
    setState(() {
      _warningFeedback = result.warningMessage;
      if (!result.success) {
        _statusFeedback = result.errorMessage ?? 'No fue posible abrir Waze.';
      } else {
        _statusFeedback =
            'Siguiente parada enviada a Waze: "${result.targetName}".';
      }
    });

    if (!result.success && mounted) {
      _showErrorWithAlternativeDialog(
        title: 'Waze no disponible',
        message:
            result.errorMessage ?? 'No se pudo abrir Waze en el dispositivo.',
        alternativeActionTitle: 'Abrir con Google Maps',
        onAlternativeAction: _exportToGoogleMaps,
      );
    } else if (result.warningMessage != null && mounted) {
      _showWarningDialog('Aviso de Waze', result.warningMessage!);
    }
  }

  void _showErrorWithAlternativeDialog({
    required String title,
    required String message,
    required String alternativeActionTitle,
    required VoidCallback onAlternativeAction,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceNavy,
        title: Text(title, style: const TextStyle(color: AppColors.error)),
        content: Text(
          message,
          style: const TextStyle(color: AppColors.coldWhite),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: AppColors.secondaryText),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4285F4),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              onAlternativeAction();
            },
            child: Text(alternativeActionTitle),
          ),
        ],
      ),
    );
  }

  void _showWarningDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceNavy,
        title: Text(
          title,
          style: const TextStyle(color: AppColors.cyanLuminous),
        ),
        content: Text(
          message,
          style: const TextStyle(color: AppColors.coldWhite),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Entendido',
              style: TextStyle(color: AppColors.cyanLuminous),
            ),
          ),
        ],
      ),
    );
  }

  void _promptChangeEndpoint({required bool isOrigin}) {
    final searchController = TextEditingController();
    List<Destination> searchResults = [];
    bool isSearching = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceNavy,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isOrigin
                        ? 'Cambiar Origen del Itinerario'
                        : 'Cambiar Destino Final',
                    style: const TextStyle(
                      color: AppColors.coldWhite,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: searchController,
                    style: const TextStyle(color: AppColors.coldWhite),
                    decoration: InputDecoration(
                      hintText: 'Buscar ciudad o punto de partida/llegada...',
                      hintStyle: const TextStyle(
                        color: AppColors.secondaryText,
                      ),
                      filled: true,
                      fillColor: AppColors.nightBlue,
                      suffixIcon: IconButton(
                        icon: isSearching
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.search,
                                color: AppColors.cyanLuminous,
                              ),
                        onPressed: () async {
                          final query = searchController.text.trim();
                          if (query.length < 2) return;
                          setSheetState(() => isSearching = true);
                          try {
                            final results = await _geocodingService.search(
                              query,
                              proximityHint: isOrigin
                                  ? _itinerary.destination.coordinates
                                  : _itinerary.origin.coordinates,
                            );
                            setSheetState(() {
                              searchResults = results;
                              isSearching = false;
                            });
                          } catch (_) {
                            setSheetState(() => isSearching = false);
                          }
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: searchResults.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Text(
                                'Ingresa un término para buscar el punto deseado.',
                                style: TextStyle(
                                  color: AppColors.secondaryText,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: searchResults.length,
                            itemBuilder: (c, i) {
                              final dest = searchResults[i];
                              return ListTile(
                                leading: Icon(
                                  isOrigin
                                      ? Icons.my_location
                                      : Icons.flag_rounded,
                                  color: isOrigin
                                      ? AppColors.success
                                      : AppColors.error,
                                ),
                                title: Text(
                                  dest.title,
                                  style: const TextStyle(
                                    color: AppColors.coldWhite,
                                  ),
                                ),
                                subtitle: Text(
                                  dest.subtitle,
                                  style: const TextStyle(
                                    color: AppColors.secondaryText,
                                    fontSize: 11,
                                  ),
                                ),
                                onTap: () {
                                  setState(() {
                                    if (isOrigin) {
                                      _isOriginManual = true;
                                      _gpsWarningMessage = null;
                                      _gpsOriginStatus =
                                          GpsOriginStatus.available;
                                      _itinerary = _itinerary.copyWith(
                                        origin: dest,
                                        calculatedRoute: null,
                                      );
                                    } else {
                                      _itinerary = _itinerary.copyWith(
                                        destination: dest,
                                        calculatedRoute: null,
                                      );
                                    }
                                  });
                                  Navigator.of(sheetContext).pop();
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _promptAddStop() {
    final searchController = TextEditingController();
    List<Destination> searchResults = [];
    bool isSearching = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceNavy,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                top: 16,
                left: 16,
                right: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Añadir Parada al Itinerario',
                    style: TextStyle(
                      color: AppColors.coldWhite,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: searchController,
                    style: const TextStyle(color: AppColors.coldWhite),
                    decoration: InputDecoration(
                      hintText: 'Buscar ciudad, gasolinera, mirador...',
                      hintStyle: const TextStyle(
                        color: AppColors.secondaryText,
                      ),
                      filled: true,
                      fillColor: AppColors.nightBlue,
                      suffixIcon: IconButton(
                        icon: isSearching
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.search,
                                color: AppColors.cyanLuminous,
                              ),
                        onPressed: () async {
                          final query = searchController.text.trim();
                          if (query.length < 2) return;
                          setSheetState(() => isSearching = true);
                          try {
                            final results = await _geocodingService.search(
                              query,
                              proximityHint: _itinerary.origin.coordinates,
                            );
                            setSheetState(() {
                              searchResults = results;
                              isSearching = false;
                            });
                          } catch (_) {
                            setSheetState(() => isSearching = false);
                          }
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Accesos directos a categorías rápidas
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildCategoryChip(
                          'Gasolinera',
                          TripStopType.fuel,
                          setSheetState,
                          (cat) async {
                            setSheetState(() => isSearching = true);
                            try {
                              final pois = await _geocodingService
                                  .searchNearbyCategory(
                                    category: 'fuel',
                                    center: _itinerary.origin.coordinates,
                                  );
                              setSheetState(() {
                                searchResults = pois;
                                isSearching = false;
                              });
                            } catch (_) {
                              setSheetState(() => isSearching = false);
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        _buildCategoryChip(
                          'Taller de motos',
                          TripStopType.motorcycleWorkshop,
                          setSheetState,
                          (cat) async {
                            setSheetState(() => isSearching = true);
                            try {
                              final pois = await _geocodingService
                                  .searchNearbyCategory(
                                    category: 'motorcycle_repair',
                                    center: _itinerary.origin.coordinates,
                                  );
                              setSheetState(() {
                                searchResults = pois;
                                isSearching = false;
                              });
                            } catch (_) {
                              setSheetState(() => isSearching = false);
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        _buildCategoryChip(
                          'Barbería',
                          TripStopType.hairdresser,
                          setSheetState,
                          (cat) async {
                            setSheetState(() => isSearching = true);
                            try {
                              final pois = await _geocodingService
                                  .searchNearbyCategory(
                                    category: 'hairdresser',
                                    center: _itinerary.origin.coordinates,
                                  );
                              setSheetState(() {
                                searchResults = pois;
                                isSearching = false;
                              });
                            } catch (_) {
                              setSheetState(() => isSearching = false);
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        _buildCategoryChip(
                          'Restaurante',
                          TripStopType.restaurant,
                          setSheetState,
                          (cat) async {
                            setSheetState(() => isSearching = true);
                            try {
                              final pois = await _geocodingService
                                  .searchNearbyCategory(
                                    category: 'restaurant',
                                    center: _itinerary.origin.coordinates,
                                  );
                              setSheetState(() {
                                searchResults = pois;
                                isSearching = false;
                              });
                            } catch (_) {
                              setSheetState(() => isSearching = false);
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        _buildCategoryChip(
                          'Mirador',
                          TripStopType.viewpoint,
                          setSheetState,
                          (cat) async {
                            setSheetState(() => isSearching = true);
                            try {
                              final pois = await _geocodingService
                                  .searchNearbyCategory(
                                    category: 'viewpoint',
                                    center: _itinerary.origin.coordinates,
                                  );
                              setSheetState(() {
                                searchResults = pois;
                                isSearching = false;
                              });
                            } catch (_) {
                              setSheetState(() => isSearching = false);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: searchResults.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Text(
                                'Ingresa un término o selecciona una categoría.',
                                style: TextStyle(
                                  color: AppColors.secondaryText,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: searchResults.length,
                            itemBuilder: (c, i) {
                              final dest = searchResults[i];
                              return ListTile(
                                leading: const Icon(
                                  Icons.place,
                                  color: AppColors.cyanLuminous,
                                ),
                                title: Text(
                                  dest.title,
                                  style: const TextStyle(
                                    color: AppColors.coldWhite,
                                  ),
                                ),
                                subtitle: Text(
                                  dest.subtitle,
                                  style: const TextStyle(
                                    color: AppColors.secondaryText,
                                    fontSize: 11,
                                  ),
                                ),
                                onTap: () {
                                  final newStop = TripStop(
                                    id: 'stop_${DateTime.now().millisecondsSinceEpoch}',
                                    name: dest.title,
                                    coordinates: dest.coordinates,
                                    orderIndex: _itinerary.stops.length,
                                    type: _mapCategoryToStopType(dest.category),
                                  );
                                  setState(() {
                                    _itinerary = _itinerary.addStop(newStop);
                                  });
                                  Navigator.of(sheetContext).pop();
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCategoryChip(
    String label,
    TripStopType type,
    StateSetter setSheetState,
    void Function(TripStopType) onSelected,
  ) {
    return ActionChip(
      backgroundColor: AppColors.nightBlue,
      label: Text(
        label,
        style: const TextStyle(color: AppColors.cyanLuminous, fontSize: 12),
      ),
      onPressed: () => onSelected(type),
    );
  }

  TripStopType _mapCategoryToStopType(String? category) {
    if (category == null) return TripStopType.custom;
    final lower = category.toLowerCase();
    if (lower.contains('fuel')) return TripStopType.fuel;
    if (lower.contains('repair') ||
        lower.contains('moto') ||
        lower.contains('tyres')) {
      return TripStopType.motorcycleWorkshop;
    }
    if (lower.contains('hairdresser')) return TripStopType.hairdresser;
    if (lower.contains('restaurant') || lower.contains('food')) {
      return TripStopType.restaurant;
    }
    if (lower.contains('viewpoint')) {
      return TripStopType.viewpoint;
    }

    return TripStopType.other;
  }

  @override
  Widget build(BuildContext context) {
    final route = _itinerary.calculatedRoute;

    return Scaffold(
      backgroundColor: AppColors.nightBlue,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceNavy,
        title: const Text(
          'Planificador de Viaje REstelar',
          style: TextStyle(
            color: AppColors.coldWhite,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildEndpointsCard(),
          const SizedBox(height: 16),
          _buildStopsHeader(),
          const SizedBox(height: 8),
          _buildStopsList(),
          const SizedBox(height: 16),
          if (_statusFeedback != null)
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.surfaceNavy,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.cardNavy),
              ),
              child: Text(
                _statusFeedback!,
                style: const TextStyle(
                  color: AppColors.cyanLuminous,
                  fontSize: 13,
                ),
              ),
            ),
          if (_warningFeedback != null)
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.warning),
              ),
              child: Text(
                _warningFeedback!,
                style: const TextStyle(color: AppColors.warning, fontSize: 12),
              ),
            ),
          _buildActionButtons(),
          if (route != null) ...[
            const SizedBox(height: 16),
            _buildRouteSummaryCard(route),
          ],
          const SizedBox(height: 16),
          _buildPoiExplorerSection(route),
        ],
      ),
    );
  }

  Widget _buildOriginRow() {
    Widget leadingIcon;
    String titleText;
    String subtitleText;
    Color titleColor = AppColors.coldWhite;

    if (_isOriginManual) {
      leadingIcon = const Icon(
        Icons.edit_location_alt,
        color: AppColors.cyanLuminous,
        size: 20,
      );
      titleText = _itinerary.origin.name;
      subtitleText = 'Origen manual (${_itinerary.origin.subtitle})';
    } else {
      switch (_gpsOriginStatus) {
        case GpsOriginStatus.obtaining:
          leadingIcon = const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.cyanLuminous,
            ),
          );
          titleText = 'Obteniendo ubicación GPS...';
          subtitleText = 'Buscando satélites';
          break;
        case GpsOriginStatus.available:
          leadingIcon = const Icon(
            Icons.my_location,
            color: AppColors.success,
            size: 20,
          );
          titleText = _itinerary.origin.name;
          subtitleText = _currentGpsPosition != null
              ? 'GPS disponible (±${_currentGpsPosition!.accuracyMeters.toStringAsFixed(0)} m)'
              : 'GPS disponible';
          break;
        case GpsOriginStatus.serviceDisabled:
          leadingIcon = const Icon(
            Icons.location_off,
            color: AppColors.warning,
            size: 20,
          );
          titleText = 'GPS desactivado';
          subtitleText = 'Activa el sensor de ubicación del teléfono';
          titleColor = AppColors.warning;
          break;
        case GpsOriginStatus.permissionDenied:
          leadingIcon = const Icon(
            Icons.location_disabled,
            color: AppColors.error,
            size: 20,
          );
          titleText = 'Permiso de ubicación denegado';
          subtitleText = 'Concede permiso o define el origen manualmente';
          titleColor = AppColors.error;
          break;
        case GpsOriginStatus.error:
          leadingIcon = const Icon(
            Icons.error_outline,
            color: AppColors.error,
            size: 20,
          );
          titleText = 'Error de ubicación';
          subtitleText = 'No se pudo obtener señal GPS';
          titleColor = AppColors.error;
          break;
        case GpsOriginStatus.idle:
          leadingIcon = const Icon(
            Icons.my_location,
            color: AppColors.secondaryText,
            size: 20,
          );
          titleText = _itinerary.origin.name;
          subtitleText = 'Ubicación';
          break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            leadingIcon,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ORIGEN',
                    style: TextStyle(
                      color: AppColors.secondaryText,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    titleText,
                    style: TextStyle(
                      color: titleColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitleText,
                    style: const TextStyle(
                      color: AppColors.secondaryText,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (_isOriginManual)
              TextButton.icon(
                key: const ValueKey('use_my_location_button'),
                icon: const Icon(
                  Icons.my_location,
                  size: 14,
                  color: AppColors.cyanLuminous,
                ),
                label: const Text(
                  'Usar mi ubicación',
                  style: TextStyle(color: AppColors.cyanLuminous, fontSize: 11),
                ),
                onPressed: () => _fetchGpsOrigin(force: true),
              )
            else if (_gpsOriginStatus == GpsOriginStatus.available)
              IconButton(
                key: const ValueKey('refresh_gps_button'),
                icon: const Icon(
                  Icons.refresh,
                  color: AppColors.cyanLuminous,
                  size: 18,
                ),
                tooltip: 'Actualizar ubicación',
                onPressed: () => _fetchGpsOrigin(force: true),
              )
            else if (_gpsOriginStatus == GpsOriginStatus.serviceDisabled ||
                _gpsOriginStatus == GpsOriginStatus.permissionDenied ||
                _gpsOriginStatus == GpsOriginStatus.error)
              IconButton(
                key: const ValueKey('retry_gps_button'),
                icon: const Icon(
                  Icons.refresh,
                  color: AppColors.warning,
                  size: 18,
                ),
                tooltip: 'Reintentar GPS',
                onPressed: () => _fetchGpsOrigin(force: true),
              ),
            IconButton(
              key: const ValueKey('edit_origin_button'),
              icon: const Icon(
                Icons.edit_outlined,
                color: AppColors.cyanLuminous,
                size: 18,
              ),
              tooltip: 'Cambiar Origen',
              onPressed: () => _promptChangeEndpoint(isOrigin: true),
            ),
          ],
        ),
        if (!_isOriginManual && _gpsWarningMessage != null)
          Container(
            key: const ValueKey('gps_warning_banner'),
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: AppColors.warning.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.warning,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _gpsWarningMessage!,
                    style: const TextStyle(
                      color: AppColors.warning,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildEndpointsCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceNavy,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardNavy),
      ),
      child: Column(
        children: [
          _buildOriginRow(),
          const Divider(color: AppColors.cardNavy, height: 20),
          Row(
            children: [
              const Icon(Icons.flag_rounded, color: AppColors.error, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'DESTINO FINAL',
                      style: TextStyle(
                        color: AppColors.secondaryText,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _itinerary.destination.name,
                      style: const TextStyle(
                        color: AppColors.coldWhite,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey('edit_destination_button'),
                icon: const Icon(
                  Icons.edit_outlined,
                  color: AppColors.cyanLuminous,
                  size: 18,
                ),
                tooltip: 'Cambiar Destino Final',
                onPressed: () => _promptChangeEndpoint(isOrigin: false),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStopsHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'PARADAS INTERMEDIAS (${_itinerary.stops.length})',
          style: const TextStyle(
            color: AppColors.cyanLuminous,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
        TextButton.icon(
          icon: const Icon(Icons.add, size: 16, color: AppColors.cyanLuminous),
          label: const Text(
            'Añadir Parada',
            style: TextStyle(color: AppColors.cyanLuminous, fontSize: 12),
          ),
          onPressed: _promptAddStop,
        ),
      ],
    );
  }

  Widget _buildStopsList() {
    if (_itinerary.stops.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.surfaceNavy,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.cardNavy),
        ),
        child: const Center(
          child: Text(
            'Sin paradas intermedias. Pulsa «Añadir Parada» para agregar miradores, gasolineras o puntos de descanso.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
          ),
        ),
      );
    }

    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _itinerary.stops.length,
      // ignore: deprecated_member_use
      onReorder: (oldIndex, newIndex) {
        setState(() {
          _itinerary = _itinerary.reorderStops(oldIndex, newIndex);
        });
      },
      itemBuilder: (ctx, index) {
        final stop = _itinerary.stops[index];
        return Container(
          key: ValueKey(stop.id),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceNavy,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: stop.isVisited ? AppColors.inactive : AppColors.cardNavy,
            ),
          ),
          child: ListTile(
            leading: CircleAvatar(
              radius: 12,
              backgroundColor: stop.isVisited
                  ? AppColors.inactive
                  : AppColors.cyanLuminous,
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.nightBlue,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              stop.name,
              style: TextStyle(
                color: stop.isVisited
                    ? AppColors.secondaryText
                    : AppColors.coldWhite,
                fontSize: 13,
                decoration: stop.isVisited ? TextDecoration.lineThrough : null,
              ),
            ),
            subtitle: Text(
              stop.type.displayName,
              style: const TextStyle(
                color: AppColors.secondaryText,
                fontSize: 10,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    stop.isVisited
                        ? Icons.check_circle
                        : Icons.check_circle_outline,
                    color: stop.isVisited
                        ? AppColors.success
                        : AppColors.secondaryText,
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() {
                      _itinerary = _itinerary.markStopVisited(
                        stop.id,
                        visited: !stop.isVisited,
                      );
                    });
                  },
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    color: AppColors.error,
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() {
                      _itinerary = _itinerary.removeStop(stop.id);
                    });
                  },
                ),
                const Icon(
                  Icons.drag_handle,
                  color: AppColors.secondaryText,
                  size: 20,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRouteSummaryCard(CalculatedRoute route) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceNavy,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.cyanLuminous.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Column(
            children: [
              const Text(
                'DISTANCIA TOTAL',
                style: TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${route.totalDistanceKm.toStringAsFixed(1)} km',
                style: const TextStyle(
                  color: AppColors.cyanLuminous,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Container(width: 1, height: 32, color: AppColors.cardNavy),
          Column(
            children: [
              const Text(
                'TIEMPO ESTIMADO',
                style: TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                route.formattedDuration,
                style: const TextStyle(
                  color: AppColors.coldWhite,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.cyanLuminous,
              foregroundColor: AppColors.nightBlue,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: _isCalculatingRoute
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.route_outlined, size: 20),
            label: Text(
              _isCalculatingRoute
                  ? 'Calculando itinerario...'
                  : 'Calcular Ruta en REstelar (OSRM)',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            onPressed: _isCalculatingRoute ? null : _calculateRoute,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF4285F4),
                  side: const BorderSide(color: Color(0xFF4285F4)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.map, size: 18),
                label: const Text(
                  'Google Maps',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                onPressed: _exportToGoogleMaps,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF33CCFF),
                  side: const BorderSide(color: Color(0xFF33CCFF)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.alt_route, size: 18),
                label: const Text(
                  'Waze',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                onPressed: _exportToWaze,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPoiExplorerSection(CalculatedRoute? route) {
    if (route == null || route.geometry.length < 2) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceNavy,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cardNavy),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.explore_outlined,
              color: AppColors.cyanLuminous,
              size: 28,
            ),
            const SizedBox(height: 8),
            const Text(
              'Explorador de POIs sobre la ruta',
              style: TextStyle(
                color: AppColors.coldWhite,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Calcula primero la ruta en REstelar para habilitar la búsqueda inteligente de gasolineras, talleres, restaurantes y miradores a lo largo de tu recorrido.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
            ),
          ],
        ),
      );
    }

    final mapMarkers = <Marker>[
      // Origen
      Marker(
        point: LatLng(
          _itinerary.origin.coordinates.latitude,
          _itinerary.origin.coordinates.longitude,
        ),
        width: 32,
        height: 32,
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.success,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.my_location, color: Colors.white, size: 16),
        ),
      ),
      // Paradas intermedias existentes
      for (int i = 0; i < _itinerary.stops.length; i++)
        Marker(
          point: LatLng(
            _itinerary.stops[i].coordinates.latitude,
            _itinerary.stops[i].coordinates.longitude,
          ),
          width: 28,
          height: 28,
          child: Container(
            decoration: BoxDecoration(
              color: _itinerary.stops[i].isVisited
                  ? AppColors.inactive
                  : AppColors.cyanLuminous,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.nightBlue, width: 2),
            ),
            child: Center(
              child: Text(
                '${i + 1}',
                style: const TextStyle(
                  color: AppColors.nightBlue,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ),
      // POIs descubiertos en el corredor
      for (final poi in _discoveredPois)
        Marker(
          point: LatLng(poi.coordinates.latitude, poi.coordinates.longitude),
          width: 34,
          height: 34,
          child: GestureDetector(
            onTap: () {
              setState(() {
                _selectedPoi = poi;
              });
            },
            child: Container(
              decoration: BoxDecoration(
                color: _colorForPoiType(poi.type),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _selectedPoi?.id == poi.id
                      ? Colors.white
                      : AppColors.nightBlue,
                  width: _selectedPoi?.id == poi.id ? 2.5 : 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Icon(
                _iconForPoiType(poi.type),
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ),
    ];

    final initialMapCenter = route.geometry.isNotEmpty
        ? LatLng(route.geometry.first.latitude, route.geometry.first.longitude)
        : LatLng(
            _itinerary.origin.coordinates.latitude,
            _itinerary.origin.coordinates.longitude,
          );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceNavy,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardNavy),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'EXPLORADOR DE POIS EN RUTA',
                style: TextStyle(
                  color: AppColors.cyanLuminous,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
              if (_discoveredPois.isNotEmpty)
                Text(
                  '${_discoveredPois.length} encontrados',
                  style: const TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Visor cartográfico interactivo integrado
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 220,
              child: RealMapWidget(
                mapController: _mapController,
                initialCenter: initialMapCenter,
                initialZoom: 11.5,
                routeGeometry: route.geometry,
                destinationCoordinates: _itinerary.destination.coordinates,
                additionalMarkers: mapMarkers,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Selector de categoría a buscar
          const Text(
            'Categoría a explorar:',
            style: TextStyle(
              color: AppColors.secondaryText,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildPoiCategoryChip(
                  'Gasolineras',
                  'fuel',
                  Icons.local_gas_station,
                ),
                const SizedBox(width: 6),
                _buildPoiCategoryChip(
                  'Talleres / Llantas',
                  'motorcycle_repair',
                  Icons.build,
                ),
                const SizedBox(width: 6),
                _buildPoiCategoryChip(
                  'Restaurantes',
                  'restaurant',
                  Icons.restaurant,
                ),
                const SizedBox(width: 6),
                _buildPoiCategoryChip(
                  'Miradores',
                  'viewpoint',
                  Icons.landscape,
                ),
                const SizedBox(width: 6),
                _buildPoiCategoryChip(
                  'Barberías',
                  'hairdresser',
                  Icons.content_cut,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Selector de ancho del corredor
          Row(
            children: [
              const Text(
                'Corredor:',
                style: TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              _buildCorridorChip('1 km', 1000.0),
              const SizedBox(width: 6),
              _buildCorridorChip('2 km', 2000.0),
              const SizedBox(width: 6),
              _buildCorridorChip('5 km', 5000.0),
            ],
          ),
          const SizedBox(height: 12),
          // Botones de acción del explorador
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.cardNavy,
                    foregroundColor: AppColors.cyanLuminous,
                    side: const BorderSide(color: AppColors.cyanLuminous),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: _isExploringPois
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search, size: 18),
                  label: Text(
                    _isExploringPois
                        ? 'Buscando en corredor...'
                        : 'Buscar POIs en Ruta',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  onPressed: _isExploringPois ? null : _searchPoisAlongRoute,
                ),
              ),
              if (_discoveredPois.isNotEmpty || _hasSearchedPois) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _clearDiscoveredPois,
                  child: const Text(
                    'Limpiar',
                    style: TextStyle(
                      color: AppColors.secondaryText,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
          // Estados de retroalimentación
          if (_isExploringPois) ...[
            const SizedBox(height: 14),
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Text(
                  'Consultando establecimientos en OpenStreetMap...',
                  style: TextStyle(color: AppColors.cyanLuminous, fontSize: 12),
                ),
              ),
            ),
          ],
          if (_poiErrorMessage != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.error),
              ),
              child: Text(
                _poiErrorMessage!,
                style: const TextStyle(color: AppColors.error, fontSize: 12),
              ),
            ),
          ],
          if (!_isExploringPois &&
              _discoveredPois.isEmpty &&
              _hasSearchedPois &&
              _poiErrorMessage == null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.cardNavy,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  'No se encontraron POIs de esta categoría dentro del corredor de ${(_corridorRadiusMeters / 1000).toStringAsFixed(1)} km.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
          // Lista de POIs encontrados
          if (_discoveredPois.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'Resultados ordenados por avance de la ruta:',
              style: TextStyle(
                color: AppColors.secondaryText,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _discoveredPois.length,
              itemBuilder: (ctx, index) {
                final poi = _discoveredPois[index];
                final isSelected = _selectedPoi?.id == poi.id;
                return _buildPoiCard(poi, isSelected);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPoiCategoryChip(
    String label,
    String categoryKey,
    IconData icon,
  ) {
    final isSelected = _selectedPoiCategory == categoryKey;
    return ActionChip(
      avatar: Icon(
        icon,
        size: 14,
        color: isSelected ? AppColors.nightBlue : AppColors.cyanLuminous,
      ),
      backgroundColor: isSelected
          ? AppColors.cyanLuminous
          : AppColors.nightBlue,
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? AppColors.nightBlue : AppColors.coldWhite,
          fontSize: 11,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      onPressed: () {
        setState(() {
          _selectedPoiCategory = categoryKey;
          _hasSearchedPois = false;
        });
      },
    );
  }

  Widget _buildCorridorChip(String label, double radiusMeters) {
    final isSelected = _corridorRadiusMeters == radiusMeters;
    return ChoiceChip(
      selected: isSelected,
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: isSelected ? AppColors.nightBlue : AppColors.coldWhite,
        ),
      ),
      selectedColor: AppColors.cyanLuminous,
      backgroundColor: AppColors.nightBlue,
      onSelected: (_) {
        setState(() {
          _corridorRadiusMeters = radiusMeters;
          _hasSearchedPois = false;
        });
      },
    );
  }

  Widget _buildPoiCard(RoutePoi poi, bool isSelected) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.cardNavy : AppColors.nightBlue,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? AppColors.cyanLuminous : AppColors.cardNavy,
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: _colorForPoiType(poi.type),
                child: Icon(
                  _iconForPoiType(poi.type),
                  size: 14,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      poi.name,
                      style: const TextStyle(
                        color: AppColors.coldWhite,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (poi.subtitle.isNotEmpty)
                      Text(
                        poi.subtitle,
                        style: const TextStyle(
                          color: AppColors.secondaryText,
                          fontSize: 10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (poi.hasIncompleteData)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.warning, width: 0.8),
                  ),
                  child: const Text(
                    'Datos básicos',
                    style: TextStyle(color: AppColors.warning, fontSize: 9),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Distancia perpendicular y desvío estimado
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceNavy,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Dist. perpendicular: ~${poi.distanceToRouteMeters.toStringAsFixed(0)} m',
                      style: const TextStyle(
                        color: AppColors.cyanLuminous,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      poi.hasRoadDetour
                          ? 'Desvío vial: ~${poi.roadDetourMeters!.toStringAsFixed(0)} m'
                          : 'Desvío por carretera no calculado',
                      style: TextStyle(
                        color: poi.hasRoadDetour
                            ? AppColors.success
                            : AppColors.secondaryText,
                        fontSize: 10,
                        fontStyle: poi.hasRoadDetour
                            ? FontStyle.normal
                            : FontStyle.italic,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'Aprox. geométrica teórica: ~${poi.estimatedDetourMeters.toStringAsFixed(0)} m (no vial)',
                  style: const TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Km ${(poi.distanceAlongRouteMeters / 1000).toStringAsFixed(1)} del viaje',
                style: const TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                ),
                icon: const Icon(
                  Icons.add_location_alt_outlined,
                  size: 15,
                  color: AppColors.cyanLuminous,
                ),
                label: const Text(
                  'Añadir como parada',
                  style: TextStyle(
                    color: AppColors.cyanLuminous,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: () => _addPoiToItinerary(poi),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _iconForPoiType(TripStopType type) {
    switch (type) {
      case TripStopType.fuel:
        return Icons.local_gas_station;
      case TripStopType.motorcycleWorkshop:
        return Icons.build;
      case TripStopType.restaurant:
        return Icons.restaurant;
      case TripStopType.viewpoint:
        return Icons.landscape;
      case TripStopType.hairdresser:
        return Icons.content_cut;
      default:
        return Icons.place;
    }
  }

  Color _colorForPoiType(TripStopType type) {
    switch (type) {
      case TripStopType.fuel:
        return const Color(0xFFFF9800);
      case TripStopType.motorcycleWorkshop:
        return const Color(0xFF00BCD4);
      case TripStopType.restaurant:
        return const Color(0xFF4CAF50);
      case TripStopType.viewpoint:
        return const Color(0xFF9C27B0);
      case TripStopType.hairdresser:
        return const Color(0xFFE91E63);
      default:
        return AppColors.cyanLuminous;
    }
  }
}
