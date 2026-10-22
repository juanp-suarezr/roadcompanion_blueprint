import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:road_companion/road_companion.dart';

/// Pantalla ágil de «Ir ahora» / Navegación Rápida para REstelar.
///
/// Permite al motociclista seleccionar rápidamente un destino (por nombre, dirección,
/// coordenadas geográficas o accesos rápidos a POI cercanos) y abrir turn-by-turn
/// en Google Maps o Waze sin exigir un itinerario formal ni cálculo OSRM previo.
class QuickNavigationScreen extends StatefulWidget {
  final LocationService? locationService;
  final GeocodingService? geocodingService;
  final ExternalNavigationLauncher? navigationLauncher;
  final Coordinates? initialLocation;
  final bool enableMapTiles;

  const QuickNavigationScreen({
    super.key,
    this.locationService,
    this.geocodingService,
    this.navigationLauncher,
    this.initialLocation,
    this.enableMapTiles = true,
  });

  @override
  State<QuickNavigationScreen> createState() => _QuickNavigationScreenState();
}

class _QuickNavigationScreenState extends State<QuickNavigationScreen> {
  late LocationService _locationService;
  late GeocodingService _geocodingService;
  late ExternalNavigationLauncher _launcher;

  GpsPosition? _currentGpsPosition;
  GpsOriginStatus _gpsStatus = GpsOriginStatus.obtaining;
  String? _gpsWarningMessage;

  final TextEditingController _searchController = TextEditingController();
  final MapController _mapController = MapController();

  List<Destination> _searchResults = [];
  Destination? _selectedDestination;
  String? _selectedCategory;
  bool _isSearching = false;
  String? _searchErrorMessage;

  bool _isLaunching = false;
  String? _statusFeedback;
  String? _warningFeedback;

  @override
  void initState() {
    super.initState();
    _locationService =
        widget.locationService ?? const GeolocatorLocationService();
    _geocodingService = widget.geocodingService ?? NominatimGeocodingService();
    _launcher = widget.navigationLauncher ?? UrlExternalNavigationLauncher();

    if (widget.initialLocation != null) {
      _currentGpsPosition = GpsPosition(
        coordinates: widget.initialLocation!,
        accuracyMeters: 5.0,
        timestamp: DateTime.now(),
      );
      _gpsStatus = GpsOriginStatus.available;
    } else {
      _fetchCurrentLocation();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Obtiene o refresca la ubicación GPS actual del dispositivo de forma no bloqueante.
  Future<void> _fetchCurrentLocation({bool force = false}) async {
    setState(() {
      _gpsStatus = GpsOriginStatus.obtaining;
      _gpsWarningMessage = null;
    });

    final enabled = await _locationService.isLocationServiceEnabled();
    if (!enabled) {
      if (mounted) {
        setState(() {
          _gpsStatus = GpsOriginStatus.serviceDisabled;
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
            _gpsStatus = req == LocationPermissionResult.serviceDisabled
                ? GpsOriginStatus.serviceDisabled
                : GpsOriginStatus.permissionDenied;
          });
        }
        return;
      }
    } else if (permission == LocationPermissionResult.deniedForever) {
      if (mounted) {
        setState(() {
          _gpsStatus = GpsOriginStatus.permissionDenied;
        });
      }
      return;
    } else if (permission == LocationPermissionResult.serviceDisabled) {
      if (mounted) {
        setState(() {
          _gpsStatus = GpsOriginStatus.serviceDisabled;
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
          _gpsStatus = GpsOriginStatus.error;
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
            'Lectura GPS antigua ($mins min). Pulsa actualizar para refrescar posición.';
      }

      setState(() {
        _currentGpsPosition = pos;
        _gpsStatus = GpsOriginStatus.available;
        _gpsWarningMessage = warning;
      });

      // Centrar el mapa si aún no hay destino seleccionado
      if (_selectedDestination == null) {
        try {
          _mapController.move(
            LatLng(pos.coordinates.latitude, pos.coordinates.longitude),
            14.0,
          );
        } catch (_) {}
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _gpsStatus = GpsOriginStatus.error;
        });
      }
    }
  }

  /// Intenta parsear un texto como par de coordenadas geográficas "lat, lon".
  Coordinates? _tryParseCoordinates(String query) {
    final parts = query.trim().split(RegExp(r'[,;\s]+'));
    if (parts.length == 2) {
      final lat = double.tryParse(parts[0]);
      final lon = double.tryParse(parts[1]);
      if (lat != null &&
          lon != null &&
          lat >= -90.0 &&
          lat <= 90.0 &&
          lon >= -180.0 &&
          lon <= 180.0) {
        return Coordinates(lat, lon);
      }
    }
    return null;
  }

  Future<void> _executeSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _searchResults = [];
        _searchErrorMessage = null;
      });
      return;
    }

    // 1. Detección inmediata de coordenadas geográficas
    final coords = _tryParseCoordinates(trimmed);
    if (coords != null) {
      final coordDest = Destination(
        id: 'coords_${coords.latitude.toStringAsFixed(4)}_${coords.longitude.toStringAsFixed(4)}',
        title:
            'Coordenadas (${coords.latitude.toStringAsFixed(5)}, ${coords.longitude.toStringAsFixed(5)})',
        subtitle: 'Destino geográfico directo',
        coordinates: coords,
      );
      setState(() {
        _searchResults = [coordDest];
        _selectedDestination = coordDest;
        _selectedCategory = null;
        _searchErrorMessage = null;
      });
      _fitMapToSelection(coordDest.coordinates);
      return;
    }

    // 2. Búsqueda por texto (Nominatim)
    setState(() {
      _isSearching = true;
      _searchErrorMessage = null;
      _selectedCategory = null;
    });

    try {
      final results = await _geocodingService.search(
        trimmed,
        proximityHint: _currentGpsPosition?.coordinates,
        limit: 10,
      );

      if (!mounted) return;

      setState(() {
        _isSearching = false;
        _searchResults = results;
        if (results.isEmpty) {
          _searchErrorMessage =
              'No se encontraron lugares para "$trimmed". Verifica la ortografía o ingresa coordenadas.';
        } else {
          _selectedDestination = results.first;
          _fitMapToSelection(results.first.coordinates);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _searchErrorMessage = 'Error de conexión al buscar destino: $e';
      });
    }
  }

  Future<void> _searchNearbyCategory(String categoryKey) async {
    setState(() {
      _selectedCategory = categoryKey;
      _isSearching = true;
      _searchErrorMessage = null;
    });

    final center =
        _currentGpsPosition?.coordinates ?? Coordinates(4.5981, -74.0758);

    try {
      final results = await _geocodingService.searchNearbyCategory(
        category: categoryKey,
        center: center,
        limit: 12,
      );

      if (!mounted) return;

      setState(() {
        _isSearching = false;
        _searchResults = results;
        if (results.isEmpty) {
          _searchErrorMessage =
              'No se encontraron puntos de interés cercanos para esta categoría.';
        } else {
          _selectedDestination = results.first;
          _fitMapToSelection(results.first.coordinates);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _searchErrorMessage = 'Error al consultar categoría cercana: $e';
      });
    }
  }

  void _fitMapToSelection(Coordinates destCoords) {
    try {
      if (_currentGpsPosition != null) {
        final origin = _currentGpsPosition!.coordinates;
        final minLat = origin.latitude < destCoords.latitude
            ? origin.latitude
            : destCoords.latitude;
        final maxLat = origin.latitude > destCoords.latitude
            ? origin.latitude
            : destCoords.latitude;
        final minLon = origin.longitude < destCoords.longitude
            ? origin.longitude
            : destCoords.longitude;
        final maxLon = origin.longitude > destCoords.longitude
            ? origin.longitude
            : destCoords.longitude;

        final centerLat = (minLat + maxLat) / 2;
        final centerLon = (minLon + maxLon) / 2;
        _mapController.move(LatLng(centerLat, centerLon), 12.5);
      } else {
        _mapController.move(
          LatLng(destCoords.latitude, destCoords.longitude),
          14.0,
        );
      }
    } catch (_) {}
  }

  Future<void> _launchNavigation({required bool useGoogleMaps}) async {
    final dest = _selectedDestination;
    final queryText = _searchController.text.trim();

    if (dest == null && queryText.isEmpty) {
      _showWarningDialog(
        'Destino requerido',
        'Por favor busca y selecciona un destino para iniciar navegación.',
      );
      return;
    }

    setState(() {
      _isLaunching = true;
      _statusFeedback = null;
      _warningFeedback = null;
    });

    // Asegurar ubicación reciente antes de generar el enlace si el sensor está activo
    if (_gpsStatus == GpsOriginStatus.available &&
        _currentGpsPosition != null) {
      final ageSeconds = _currentGpsPosition!.age().inSeconds;
      if (ageSeconds > 60) {
        try {
          final freshPos = await _locationService.getCurrentPosition(
            timeLimit: const Duration(seconds: 3),
          );
          if (freshPos != null) {
            _currentGpsPosition = freshPos;
          }
        } catch (_) {}
      }
    }

    NavigationExportResult result;
    final targetLabel = dest?.title ?? queryText;

    if (useGoogleMaps) {
      result = await _launcher.launchQuickGoogleMaps(
        destinationCoordinates: dest?.coordinates,
        destinationQuery: dest == null ? queryText : null,
        origin:
            null, // Omitir origen para que Google Maps navegue desde la ubicación actual
        targetName: targetLabel,
      );
    } else {
      result = await _launcher.launchQuickWaze(
        destinationCoordinates: dest?.coordinates,
        destinationQuery: dest == null ? queryText : null,
        targetName: targetLabel,
      );
    }

    if (!mounted) return;

    setState(() {
      _isLaunching = false;
      _warningFeedback = result.warningMessage;
      if (!result.success) {
        _statusFeedback =
            result.errorMessage ??
            'No fue posible abrir la aplicación de navegación.';
      } else {
        _statusFeedback = useGoogleMaps
            ? 'Navegación rápida abierta en Google Maps.'
            : 'Navegación rápida abierta en Waze.';
      }
    });

    if (!result.success) {
      if (!useGoogleMaps) {
        _showErrorWithAlternativeDialog(
          title: 'Waze no disponible',
          message: result.errorMessage ?? 'No se pudo abrir Waze.',
          alternativeActionTitle: 'Abrir con Google Maps',
          onAlternativeAction: () => _launchNavigation(useGoogleMaps: true),
        );
      } else {
        _showWarningDialog(
          'Aviso de navegación',
          result.errorMessage ?? 'No fue posible abrir Google Maps.',
        );
      }
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.nightBlue,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceNavy,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ir ahora',
              style: TextStyle(
                color: AppColors.coldWhite,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            Text(
              'Navegación rápida directa hacia tu destino',
              style: TextStyle(color: AppColors.secondaryText, fontSize: 11),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildOriginCard(),
                const SizedBox(height: 14),
                _buildDestinationInput(),
                const SizedBox(height: 12),
                _buildCategoryChips(),
                const SizedBox(height: 14),
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
                      style: const TextStyle(
                        color: AppColors.warning,
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (_selectedDestination != null || _currentGpsPosition != null)
                  _buildMapPreview(),
                const SizedBox(height: 14),
                _buildSearchResultsSection(),
              ],
            ),
          ),
          _buildBottomActionDock(),
        ],
      ),
    );
  }

  Widget _buildOriginCard() {
    Widget leading;
    String statusTitle;
    String statusSubtitle;
    Color titleColor = AppColors.coldWhite;

    switch (_gpsStatus) {
      case GpsOriginStatus.obtaining:
        leading = const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.cyanLuminous,
          ),
        );
        statusTitle = 'Mi ubicación actual';
        statusSubtitle = 'Obteniendo señal GPS...';
        break;
      case GpsOriginStatus.available:
        leading = const Icon(
          Icons.my_location,
          color: AppColors.success,
          size: 20,
        );
        statusTitle = 'Mi ubicación actual';
        statusSubtitle = _currentGpsPosition != null
            ? 'GPS disponible (±${_currentGpsPosition!.accuracyMeters.toStringAsFixed(0)} m)'
            : 'GPS disponible';
        break;
      case GpsOriginStatus.serviceDisabled:
        leading = const Icon(
          Icons.location_off,
          color: AppColors.warning,
          size: 20,
        );
        statusTitle = 'GPS desactivado';
        statusSubtitle = 'Activa la ubicación en los ajustes';
        titleColor = AppColors.warning;
        break;
      case GpsOriginStatus.permissionDenied:
        leading = const Icon(
          Icons.location_disabled,
          color: AppColors.error,
          size: 20,
        );
        statusTitle = 'Permiso de ubicación denegado';
        statusSubtitle = 'Concede el permiso para localizarte';
        titleColor = AppColors.error;
        break;
      case GpsOriginStatus.error:
        leading = const Icon(
          Icons.error_outline,
          color: AppColors.error,
          size: 20,
        );
        statusTitle = 'Error de ubicación';
        statusSubtitle = 'No fue posible fijar coordenadas';
        titleColor = AppColors.error;
        break;
      case GpsOriginStatus.idle:
        leading = const Icon(
          Icons.my_location,
          color: AppColors.secondaryText,
          size: 20,
        );
        statusTitle = 'Mi ubicación actual';
        statusSubtitle = 'Ubicación local';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceNavy,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardNavy),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              leading,
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
                      statusTitle,
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      statusSubtitle,
                      style: const TextStyle(
                        color: AppColors.secondaryText,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey('quick_nav_refresh_gps'),
                icon: const Icon(
                  Icons.refresh,
                  color: AppColors.cyanLuminous,
                  size: 20,
                ),
                tooltip: 'Actualizar GPS',
                onPressed: () => _fetchCurrentLocation(force: true),
              ),
            ],
          ),
          if (_gpsWarningMessage != null)
            Container(
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
      ),
    );
  }

  Widget _buildDestinationInput() {
    return TextField(
      key: const ValueKey('quick_nav_destination_input'),
      controller: _searchController,
      style: const TextStyle(color: AppColors.coldWhite, fontSize: 14),
      decoration: InputDecoration(
        labelText: 'DESTINO',
        labelStyle: const TextStyle(
          color: AppColors.cyanLuminous,
          fontSize: 12,
        ),
        hintText: 'Nombre, dirección o coordenadas (lat, lon)...',
        hintStyle: const TextStyle(
          color: AppColors.secondaryText,
          fontSize: 13,
        ),
        filled: true,
        fillColor: AppColors.surfaceNavy,
        prefixIcon: const Icon(Icons.flag_rounded, color: AppColors.error),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_searchController.text.isNotEmpty)
              IconButton(
                icon: const Icon(
                  Icons.clear,
                  color: AppColors.secondaryText,
                  size: 18,
                ),
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _searchResults = [];
                    _selectedDestination = null;
                    _searchErrorMessage = null;
                  });
                },
              ),
            IconButton(
              key: const ValueKey('quick_nav_search_button'),
              icon: _isSearching
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.cyanLuminous,
                      ),
                    )
                  : const Icon(Icons.search, color: AppColors.cyanLuminous),
              onPressed: () => _executeSearch(_searchController.text),
            ),
          ],
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.cardNavy),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.cardNavy),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: AppColors.cyanLuminous,
            width: 1.5,
          ),
        ),
      ),
      onSubmitted: _executeSearch,
    );
  }

  Widget _buildCategoryChips() {
    final categories = [
      {
        'key': 'fuel',
        'label': 'Gasolineras',
        'icon': Icons.local_gas_station_rounded,
      },
      {
        'key': 'motorcycle_repair',
        'label': 'Talleres',
        'icon': Icons.build_circle_rounded,
      },
      {
        'key': 'restaurant',
        'label': 'Restaurantes/Cafés',
        'icon': Icons.restaurant_rounded,
      },
      {
        'key': 'viewpoint',
        'label': 'Miradores',
        'icon': Icons.landscape_rounded,
      },
      {
        'key': 'hairdresser',
        'label': 'Barberías',
        'icon': Icons.content_cut_rounded,
      },
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: categories.map((cat) {
          final isSelected = _selectedCategory == cat['key'];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              key: ValueKey('chip_cat_${cat['key']}'),
              avatar: Icon(
                cat['icon'] as IconData,
                size: 15,
                color: isSelected
                    ? AppColors.nightBlue
                    : AppColors.cyanLuminous,
              ),
              label: Text(
                cat['label'] as String,
                style: TextStyle(
                  color: isSelected ? AppColors.nightBlue : AppColors.coldWhite,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              backgroundColor: isSelected
                  ? AppColors.cyanLuminous
                  : AppColors.surfaceNavy,
              side: BorderSide(
                color: isSelected ? AppColors.cyanLuminous : AppColors.cardNavy,
              ),
              onPressed: () => _searchNearbyCategory(cat['key'] as String),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMapPreview() {
    final originLatLng = _currentGpsPosition != null
        ? LatLng(
            _currentGpsPosition!.coordinates.latitude,
            _currentGpsPosition!.coordinates.longitude,
          )
        : const LatLng(4.5981, -74.0758);

    final destLatLng = _selectedDestination != null
        ? LatLng(
            _selectedDestination!.coordinates.latitude,
            _selectedDestination!.coordinates.longitude,
          )
        : null;

    final markers = <Marker>[
      if (_currentGpsPosition != null)
        Marker(
          point: originLatLng,
          width: 32,
          height: 32,
          child: const Icon(
            Icons.my_location,
            color: AppColors.success,
            size: 24,
          ),
        ),
      if (destLatLng != null)
        Marker(
          point: destLatLng,
          width: 36,
          height: 36,
          child: const Icon(
            Icons.flag_rounded,
            color: AppColors.error,
            size: 30,
          ),
        ),
    ];

    return Container(
      height: 180,
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardNavy),
      ),
      clipBehavior: Clip.antiAlias,
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: destLatLng ?? originLatLng,
          initialZoom: destLatLng != null ? 13.0 : 14.0,
        ),
        children: [
          if (widget.enableMapTiles)
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'es.estela.restelar',
            ),
          MarkerLayer(markers: markers),
        ],
      ),
    );
  }

  Widget _buildSearchResultsSection() {
    if (_isSearching) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: CircularProgressIndicator(color: AppColors.cyanLuminous),
        ),
      );
    }

    if (_searchErrorMessage != null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceNavy,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.cardNavy),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: AppColors.warning, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _searchErrorMessage!,
                style: const TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surfaceNavy,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.cardNavy),
        ),
        child: const Center(
          child: Text(
            'Ingresa un destino o pulsa un acceso de categoría para ver resultados.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'RESULTADOS (${_searchResults.length})',
          style: const TextStyle(
            color: AppColors.cyanLuminous,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _searchResults.length,
          itemBuilder: (ctx, index) {
            final dest = _searchResults[index];
            final isSelected = _selectedDestination?.id == dest.id;

            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected
                      ? AppColors.cyanLuminous
                      : AppColors.cardNavy,
                  width: isSelected ? 1.5 : 1.0,
                ),
              ),
              child: Material(
                color: isSelected
                    ? AppColors.cyanLuminous.withValues(alpha: 0.12)
                    : AppColors.surfaceNavy,
                borderRadius: BorderRadius.circular(8),
                child: ListTile(
                  key: ValueKey('destination_tile_${dest.id}'),
                  dense: true,
                  leading: Icon(
                    isSelected
                        ? Icons.check_circle_rounded
                        : Icons.place_rounded,
                    color: isSelected
                        ? AppColors.cyanLuminous
                        : AppColors.secondaryText,
                  ),
                  title: Text(
                    dest.title,
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.cyanLuminous
                          : AppColors.coldWhite,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                  subtitle: Text(
                    dest.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.secondaryText,
                      fontSize: 11,
                    ),
                  ),
                  onTap: () {
                    setState(() {
                      _selectedDestination = dest;
                    });
                    _fitMapToSelection(dest.coordinates);
                  },
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildBottomActionDock() {
    final hasTarget =
        _selectedDestination != null ||
        _searchController.text.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppColors.surfaceNavy,
        border: Border(top: BorderSide(color: AppColors.cardNavy)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_selectedDestination != null) ...[
              Row(
                children: [
                  const Icon(
                    Icons.flag_rounded,
                    color: AppColors.error,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Destino: ${_selectedDestination!.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.coldWhite,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    key: const ValueKey('launch_google_maps_button'),
                    icon: const Icon(Icons.navigation, size: 18),
                    label: const Text(
                      'Google Maps',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4285F4),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: (_isLaunching || !hasTarget)
                        ? null
                        : () => _launchNavigation(useGoogleMaps: true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    key: const ValueKey('launch_waze_button'),
                    icon: const Icon(Icons.near_me, size: 18),
                    label: const Text(
                      'Waze',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF33CCFF),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: (_isLaunching || !hasTarget)
                        ? null
                        : () => _launchNavigation(useGoogleMaps: false),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
