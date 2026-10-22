import 'dart:async';
import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../domain/entities/coordinates.dart';
import '../../domain/entities/destination.dart';
import '../../domain/services/geocoding_service.dart';
import '../../infrastructure/services/nominatim_geocoding_service.dart';

/// Modal para buscar y seleccionar destinos geográficos en tiempo real con debounce.
class DestinationSearchSheet extends StatefulWidget {
  final GeocodingService geocodingService;
  final Coordinates? userLocation;
  final ValueChanged<Destination> onDestinationSelected;

  const DestinationSearchSheet({
    super.key,
    required this.geocodingService,
    this.userLocation,
    required this.onDestinationSelected,
  });

  static Future<Destination?> show(
    BuildContext context, {
    GeocodingService? geocodingService,
    Coordinates? userLocation,
  }) {
    return showModalBottomSheet<Destination>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DestinationSearchSheet(
        geocodingService: geocodingService ?? NominatimGeocodingService(),
        userLocation: userLocation,
        onDestinationSelected: (dest) {
          Navigator.of(ctx).pop(dest);
        },
      ),
    );
  }

  @override
  State<DestinationSearchSheet> createState() => _DestinationSearchSheetState();
}

class _DestinationSearchSheetState extends State<DestinationSearchSheet> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  bool _isLoading = false;
  String? _errorMessage;
  bool _needsLocationForCategory = false;
  List<Destination> _results = [];
  bool _hasSearched = false;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounceTimer?.cancel();
    if (query.trim().length < 2) {
      setState(() {
        _results = [];
        _isLoading = false;
        _errorMessage = null;
        _needsLocationForCategory = false;
        _hasSearched = false;
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _executeSearch(query);
    });
  }

  Future<void> _executeSearch(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.length < 2) return;

    final isCategory = isCategoryQuery(cleanQuery);

    // Si la búsqueda es por categoría y no hay GPS, se solicita la ubicación al usuario
    // y no se ejecutan consultas globales irrelevantes que devuelvan resultados de otros países.
    if (isCategory && widget.userLocation == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = null;
        _needsLocationForCategory = true;
        _hasSearched = true;
        _results = [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _needsLocationForCategory = false;
      _hasSearched = true;
    });

    try {
      final List<Destination> rawResults;
      if (isCategory && widget.userLocation != null) {
        final categoryKey = resolveCategoryKey(cleanQuery);
        rawResults = await widget.geocodingService.searchNearbyCategory(
          category: categoryKey,
          center: widget.userLocation!,
          limit: 15,
        );
      } else {
        rawResults = await widget.geocodingService.search(
          cleanQuery,
          proximityHint: widget.userLocation,
          limit: 10,
        );
      }

      final rankedResults = rankDestinations(
        results: rawResults,
        query: cleanQuery,
        userLocation: widget.userLocation,
      );

      if (!mounted) return;
      setState(() {
        _results = rankedResults;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage =
            'No se pudo conectar con el servicio de búsqueda local. Verifica tu conexión a internet o reintenta.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.86,
      ),
      padding: EdgeInsets.only(
        top: 14.0,
        left: 20.0,
        right: 20.0,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16.0,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.nightBlue : AppColors.whiteSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24.0)),
        border: Border.all(
          color: isDark ? const Color(0xFF264660) : AppColors.silver,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tirador decorativo
          Center(
            child: Container(
              width: 38.0,
              height: 4.0,
              decoration: BoxDecoration(
                color: isDark ? AppColors.cardNavy : AppColors.silver,
                borderRadius: BorderRadius.circular(2.0),
              ),
            ),
          ),
          const SizedBox(height: 14.0),

          // Título
          Row(
            children: [
              Icon(
                Icons.search,
                size: 20.0,
                color: isDark ? AppColors.cyanLuminous : AppColors.electricBlue,
              ),
              const SizedBox(width: 8.0),
              Text(
                'BUSCAR DESTINO',
                style: AppTypography.badgeLabel.copyWith(
                  color: isDark
                      ? AppColors.cyanLuminous
                      : AppColors.electricBlue,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 20.0),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Cerrar',
              ),
            ],
          ),
          const SizedBox(height: 12.0),

          // Campo de búsqueda con autocompletado y debounce
          TextField(
            controller: _searchController,
            autofocus: true,
            onChanged: _onQueryChanged,
            textInputAction: TextInputAction.search,
            onSubmitted: (q) => _executeSearch(q),
            style: TextStyle(
              fontSize: 15.0,
              color: isDark ? AppColors.coldWhite : AppColors.primaryTextLight,
            ),
            decoration: InputDecoration(
              hintText: 'Municipio, dirección o punto de interés...',
              hintStyle: TextStyle(
                color: isDark
                    ? AppColors.secondaryText
                    : AppColors.secondaryTextLight,
                fontSize: 14.0,
              ),
              prefixIcon: Icon(
                Icons.location_on_outlined,
                color: isDark ? AppColors.cyanLuminous : AppColors.electricBlue,
              ),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18.0),
                      onPressed: () {
                        _searchController.clear();
                        _onQueryChanged('');
                      },
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 10.0),

          // Chips de categorías frecuentes de motociclista
          SizedBox(
            height: 36.0,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildQuickCategoryChip(
                  icon: Icons.local_gas_station,
                  label: 'Gasolineras',
                  categoryKey: 'fuel',
                  isDark: isDark,
                ),
                const SizedBox(width: 6.0),
                _buildQuickCategoryChip(
                  icon: Icons.church,
                  label: 'Iglesias',
                  categoryKey: 'place_of_worship',
                  isDark: isDark,
                ),
                const SizedBox(width: 6.0),
                _buildQuickCategoryChip(
                  icon: Icons.shopping_bag_outlined,
                  label: 'C. Comerciales',
                  categoryKey: 'mall',
                  isDark: isDark,
                ),
                const SizedBox(width: 6.0),
                _buildQuickCategoryChip(
                  icon: Icons.two_wheeler,
                  label: 'Talleres Moto',
                  categoryKey: 'motorcycle_repair',
                  isDark: isDark,
                ),
                const SizedBox(width: 6.0),
                _buildQuickCategoryChip(
                  icon: Icons.tire_repair,
                  label: 'Montallantas',
                  categoryKey: 'tyres',
                  isDark: isDark,
                ),
                const SizedBox(width: 6.0),
                _buildQuickCategoryChip(
                  icon: Icons.content_cut,
                  label: 'Barberías',
                  categoryKey: 'hairdresser',
                  isDark: isDark,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12.0),

          // Estado de carga o resultados
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 36.0),
              child: Center(
                child: Column(
                  children: [
                    SizedBox(
                      width: 28.0,
                      height: 28.0,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                    SizedBox(height: 12.0),
                    Text(
                      'Buscando destinos en la red vial...',
                      style: TextStyle(fontSize: 12.0),
                    ),
                  ],
                ),
              ),
            )
          else if (_needsLocationForCategory)
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: isDark ? AppColors.cardNavy : const Color(0xFFF1F6FA),
                borderRadius: BorderRadius.circular(12.0),
                border: Border.all(
                  color: isDark ? const Color(0xFF2E4D68) : AppColors.silver,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.my_location_outlined,
                    size: 34.0,
                    color: isDark
                        ? AppColors.cyanLuminous
                        : AppColors.electricBlue,
                  ),
                  const SizedBox(height: 10.0),
                  Text(
                    'Búsqueda local de "${_searchController.text}"',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.0,
                      color: isDark
                          ? AppColors.coldWhite
                          : AppColors.primaryTextLight,
                    ),
                  ),
                  const SizedBox(height: 6.0),
                  Text(
                    'Para buscar establecimientos cercanos sin mostrar resultados de otros países, activa la ubicación GPS de tu teléfono.\n\nTambién puedes buscar indicando una ciudad o municipio concreto (ej. "Pereira", "Guadalupe").',
                    style: TextStyle(
                      fontSize: 12.0,
                      color: isDark
                          ? AppColors.secondaryText
                          : AppColors.secondaryTextLight,
                      height: 1.35,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10.0),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.wifi_off,
                        color: AppColors.error,
                        size: 20.0,
                      ),
                      const SizedBox(width: 10.0),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            fontSize: 12.0,
                            color: AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10.0),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _executeSearch(_searchController.text),
                      icon: const Icon(Icons.refresh, size: 16.0),
                      label: const Text('Reintentar'),
                      style: TextButton.styleFrom(
                        foregroundColor: isDark
                            ? AppColors.cyanLuminous
                            : AppColors.electricBlue,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else if (_hasSearched && _results.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32.0),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.location_off_outlined,
                      size: 38.0,
                      color: isDark
                          ? AppColors.secondaryText
                          : AppColors.secondaryTextLight,
                    ),
                    const SizedBox(height: 10.0),
                    Text(
                      'No se encontraron lugares para "${_searchController.text}".\nPrueba indicando el municipio o vía principal.',
                      style: TextStyle(
                        fontSize: 13.0,
                        color: isDark
                            ? AppColors.secondaryText
                            : AppColors.secondaryTextLight,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _results.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 6.0),
                itemBuilder: (context, index) {
                  final dest = _results[index];

                  double? distanceKm;
                  if (widget.userLocation != null) {
                    distanceKm =
                        widget.userLocation!.distanceTo(dest.coordinates) /
                        1000.0;
                  }

                  return Material(
                    color: isDark
                        ? AppColors.cardNavy
                        : AppColors.lightBackground,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.0),
                      side: BorderSide(
                        color: isDark
                            ? const Color(0xFF264660)
                            : AppColors.silver,
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 6.0,
                      ),
                      leading: CircleAvatar(
                        radius: 20.0,
                        backgroundColor: isDark
                            ? AppColors.surfaceNavy
                            : const Color(0xFFE2EDF7),
                        child: Icon(
                          getDestinationCategoryIcon(dest.category),
                          size: 20.0,
                          color: isDark
                              ? AppColors.cyanLuminous
                              : AppColors.electricBlue,
                        ),
                      ),
                      title: Text(
                        dest.title,
                        style: TextStyle(
                          fontSize: 15.0,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppColors.coldWhite
                              : AppColors.primaryTextLight,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 2.0),
                        child: Text(
                          dest.subtitle,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: isDark
                                ? AppColors.secondaryText
                                : AppColors.secondaryTextLight,
                            height: 1.25,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      trailing: distanceKm != null
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8.0,
                                vertical: 4.0,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppColors.surfaceNavy
                                    : const Color(0xFFE8F2FA),
                                borderRadius: BorderRadius.circular(6.0),
                              ),
                              child: Text(
                                '${distanceKm.toStringAsFixed(1)} km',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: isDark
                                      ? AppColors.cyanLuminous
                                      : AppColors.electricBlue,
                                ),
                              ),
                            )
                          : const Icon(Icons.arrow_forward_ios, size: 14.0),
                      onTap: () => widget.onDestinationSelected(dest),
                    ),
                  );
                },
              ),
            ),
          if (_results.isNotEmpty) ...[
            const SizedBox(height: 8.0),
            Center(
              child: Text(
                'OpenStreetMap Nominatim • Licencia ODbL',
                style: TextStyle(
                  fontSize: 10.0,
                  color: isDark
                      ? AppColors.secondaryTextDark
                      : AppColors.secondaryTextLight,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickCategoryChip({
    required IconData icon,
    required String label,
    required String categoryKey,
    required bool isDark,
  }) {
    return ActionChip(
      avatar: Icon(
        icon,
        size: 16.0,
        color: isDark ? AppColors.cyanLuminous : AppColors.surfaceNavy,
      ),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12.0,
          fontWeight: FontWeight.w700,
          color: isDark ? AppColors.coldWhite : AppColors.primaryTextLight,
        ),
      ),
      backgroundColor: isDark ? AppColors.cardNavy : const Color(0xFFE8F1F8),
      side: BorderSide(
        color: isDark ? const Color(0xFF2E4D68) : AppColors.silver,
        width: 1.0,
      ),
      onPressed: () {
        _searchController.text = label;
        _executeSearch(label);
      },
    );
  }
}

/// Determina el icono temático para una categoría geográfica dada.
IconData getDestinationCategoryIcon(String? category) {
  if (category == null) return Icons.place;
  switch (category.toLowerCase()) {
    case 'fuel':
    case 'gas_station':
      return Icons.local_gas_station;
    case 'place_of_worship':
    case 'church':
      return Icons.church;
    case 'mall':
    case 'shop=mall':
    case 'commercial':
      return Icons.shopping_bag_outlined;
    case 'motorcycle':
    case 'motorcycle_repair':
    case 'car_repair':
      return Icons.two_wheeler;
    case 'tyres':
    case 'vulcanizer':
    case 'montallantas':
      return Icons.tire_repair;
    case 'hairdresser':
    case 'barber':
      return Icons.content_cut;
    case 'restaurant':
    case 'cafe':
    case 'fast_food':
      return Icons.restaurant;
    case 'hotel':
    case 'motel':
    case 'guest_house':
      return Icons.hotel;
    case 'peak':
    case 'volcano':
    case 'mountain':
      return Icons.terrain;
    case 'city':
    case 'town':
    case 'village':
    case 'municipality':
      return Icons.location_city;
    case 'hospital':
    case 'clinic':
    case 'pharmacy':
      return Icons.local_hospital;
    default:
      return Icons.place;
  }
}

/// Resuelve el identificador de categoría normalizado para consulta en Nominatim/OSM.
String resolveCategoryKey(String query) {
  final q = query.trim().toLowerCase();
  if (q.contains('gasolin') ||
      q.contains('combustible') ||
      q.contains('estacion de servicio') ||
      q.contains('estaciones de servicio') ||
      q.contains('bomba') ||
      q.contains('eds') ||
      q.contains('terpel') ||
      q.contains('primax') ||
      q.contains('texaco') ||
      q.contains('biomax') ||
      q.contains('mobil') ||
      q.contains('esso')) {
    return 'fuel';
  }
  if (q.contains('iglesia') ||
      q.contains('culto') ||
      q.contains('parroquia') ||
      q.contains('templo') ||
      q.contains('catedral') ||
      q.contains('capilla') ||
      q.contains('santuario')) {
    return 'place_of_worship';
  }
  if (q.contains('centro comercial') ||
      q.contains('centros comerciales') ||
      q.contains('mall') ||
      q.contains('shopping') ||
      q.contains('unicentro')) {
    return 'mall';
  }
  if (q.contains('montallantas') ||
      q.contains('vulcanizadora') ||
      q.contains('vulcanizadoras') ||
      q.contains('reparación de llantas') ||
      q.contains('reparacion de llantas') ||
      q.contains('llantas') ||
      q.contains('pinchazo') ||
      q.contains('pinchazos') ||
      q.contains('parches')) {
    return 'tyres';
  }
  if (q.contains('peluquer') ||
      q.contains('barber') ||
      q.contains('corte de pelo') ||
      q.contains('corte de cabello') ||
      q.contains('salon de belleza') ||
      q.contains('salón de belleza')) {
    return 'hairdresser';
  }
  if (q.contains('taller de moto') ||
      q.contains('talleres de moto') ||
      q.contains('mecanica moto') ||
      q.contains('mecánica moto') ||
      q.contains('motos') ||
      q.contains('motocicletas') ||
      q.contains('taller') ||
      q.contains('mecanic') ||
      q.contains('mecánic') ||
      q.contains('repuestos')) {
    return 'motorcycle_repair';
  }
  if (q.contains('restaurante') ||
      q.contains('comida') ||
      q.contains('almuerzo') ||
      q.contains('cena') ||
      q.contains('desayuno')) {
    return 'restaurant';
  }
  if (q.contains('cafe') ||
      q.contains('café') ||
      q.contains('cafeteria') ||
      q.contains('cafetería')) {
    return 'cafe';
  }
  if (q.contains('hotel') ||
      q.contains('hostal') ||
      q.contains('hospedaje') ||
      q.contains('motel')) {
    return 'hotel';
  }
  if (q.contains('hospital') ||
      q.contains('hospitales') ||
      q.contains('clinica') ||
      q.contains('clínica')) {
    return 'hospital';
  }
  if (q.contains('farmacia') ||
      q.contains('farmacias') ||
      q.contains('drogueria') ||
      q.contains('droguería')) {
    return 'pharmacy';
  }
  return q;
}

/// Verifica si la consulta corresponde a una búsqueda por categoría o proximidad relativa.
bool isCategoryQuery(String query) {
  final q = query.trim().toLowerCase();

  // Nombres de ciudades o municipios reconocidos no deben tratarse como categorías
  const knownCities = [
    'guadalupe',
    'pereira',
    'armenia',
    'manizales',
    'dosquebradas',
    'cartago',
    'medellin',
    'medellín',
    'bogota',
    'bogotá',
    'cali',
    'ibague',
    'ibagué',
    'salento',
    'filandia',
    'santa rosa',
    'santa rosa de cabal',
    'chinchina',
    'chinchiná',
    'neiva',
    'bucaramanga',
    'pasto',
    'popayan',
    'popayán',
  ];
  if (knownCities.contains(q)) return false;

  const categoryKeywords = [
    'gasolina',
    'gasolinas',
    'gasolinera',
    'gasolineras',
    'combustible',
    'estacion de servicio',
    'estaciones de servicio',
    'bomba',
    'bombas',
    'eds',
    'terpel',
    'primax',
    'texaco',
    'biomax',
    'mobil',
    'esso',
    'iglesia',
    'iglesias',
    'culto',
    'templo',
    'templos',
    'parroquia',
    'parroquias',
    'centro comercial',
    'centros comerciales',
    'mall',
    'shopping',
    'unicentro',
    'restaurante',
    'restaurantes',
    'comida',
    'almuerzo',
    'cena',
    'desayuno',
    'cafe',
    'café',
    'cafeteria',
    'cafetería',
    'panaderia',
    'panadería',
    'taller',
    'talleres',
    'taller de motos',
    'talleres de motos',
    'mecanico',
    'mecánico',
    'motos',
    'motocicletas',
    'repuestos',
    'montallantas',
    'vulcanizadora',
    'vulcanizadoras',
    'reparacion de llantas',
    'reparación de llantas',
    'llantas',
    'pinchazo',
    'peluqueria',
    'peluquería',
    'peluquerias',
    'peluquerías',
    'barberia',
    'barbería',
    'barberias',
    'barberías',
    'salon de belleza',
    'salón de belleza',
    'corte de cabello',
    'lavadero',
    'hotel',
    'hoteles',
    'hostal',
    'hospedaje',
    'motel',
    'hospital',
    'hospitales',
    'clinica',
    'clínica',
    'farmacia',
    'farmacias',
    'drogueria',
    'droguería',
    'cajero',
    'cajeros',
    'atm',
    'banco',
    'bancos',
    'peaje',
    'peajes',
  ];

  if (q.contains('cerca') || q.contains('proximo') || q.contains('próximo')) {
    return true;
  }

  for (final kw in categoryKeywords) {
    if (q == kw ||
        q.startsWith('$kw ') ||
        q.endsWith(' $kw') ||
        q.contains(' $kw ')) {
      return true;
    }
    if (q.contains(kw) && kw.length >= 6) {
      return true;
    }
  }
  return false;
}

/// Comprueba si un destino coincide con la categoría semántica buscada.
bool matchesCategory(Destination d, String query) {
  final q = query.trim().toLowerCase();
  final cat = (d.category ?? '').toLowerCase();
  final title = d.title.toLowerCase();
  final subtitle = d.subtitle.toLowerCase();

  // Combustibles
  if (q.contains('gasolin') ||
      q.contains('combustible') ||
      q.contains('estacion de servicio') ||
      q.contains('eds') ||
      q.contains('bomba')) {
    if (cat == 'fuel' || cat == 'gas_station') return true;
    if (title.contains('terpel') ||
        title.contains('primax') ||
        title.contains('texaco') ||
        title.contains('mobil') ||
        title.contains('biomax') ||
        title.contains('gasolinera') ||
        title.contains('estación de servicio') ||
        title.contains('estacion de servicio') ||
        title.contains('eds')) {
      return true;
    }
  }

  // Iglesias y lugares de culto
  if (q.contains('iglesia') ||
      q.contains('culto') ||
      q.contains('parroquia') ||
      q.contains('templo') ||
      q.contains('catedral') ||
      q.contains('capilla') ||
      q.contains('santuario')) {
    if (cat == 'place_of_worship' || cat == 'church') return true;
    if (title.contains('iglesia') ||
        title.contains('parroquia') ||
        title.contains('templo') ||
        title.contains('catedral') ||
        title.contains('capilla') ||
        title.contains('santuario')) {
      return true;
    }
  }

  // Centros comerciales
  if (q.contains('centro comercial') ||
      q.contains('centros comerciales') ||
      q.contains('mall') ||
      q.contains('shopping') ||
      q.contains('unicentro')) {
    if (cat == 'mall' || cat == 'shopping_mall' || cat == 'commercial') {
      return true;
    }
    if (title.contains('centro comercial') ||
        title.contains('mall') ||
        title.contains('unicentro') ||
        title.contains('plaza')) {
      return true;
    }
  }

  // Montallantas y reparación de llantas
  if (q.contains('montallantas') ||
      q.contains('vulcanizadora') ||
      q.contains('vulcanizadoras') ||
      q.contains('llantas') ||
      q.contains('pinchazo') ||
      q.contains('parches')) {
    if (cat == 'tyres' || cat == 'vulcanizer' || cat == 'montallantas') {
      return true;
    }
    if (title.contains('montallantas') ||
        title.contains('llantas') ||
        title.contains('vulcanizadora') ||
        title.contains('servillantas')) {
      return true;
    }
  }

  // Peluquerías y barberías
  if (q.contains('peluquer') ||
      q.contains('barber') ||
      q.contains('corte de cabello') ||
      q.contains('salon de belleza') ||
      q.contains('salón de belleza')) {
    if (cat == 'hairdresser' || cat == 'barber') return true;
    if (title.contains('peluquería') ||
        title.contains('peluqueria') ||
        title.contains('barbería') ||
        title.contains('barberia') ||
        title.contains('barber') ||
        title.contains('salón') ||
        title.contains('salon')) {
      return true;
    }
  }

  // Alimentos
  if (q.contains('restaurante') ||
      q.contains('comida') ||
      q.contains('cafe') ||
      q.contains('café') ||
      q.contains('panaderia') ||
      q.contains('panadería')) {
    if (cat == 'restaurant' ||
        cat == 'cafe' ||
        cat == 'fast_food' ||
        cat == 'bakery') {
      return true;
    }
    if (title.contains('restaurante') ||
        title.contains('café') ||
        title.contains('cafe') ||
        title.contains('panadería') ||
        title.contains('panaderia')) {
      return true;
    }
  }

  // Talleres y motos
  if (q.contains('taller') ||
      q.contains('mecanic') ||
      q.contains('mecánic') ||
      q.contains('motos') ||
      q.contains('repuestos')) {
    if (cat == 'car_repair' ||
        cat == 'motorcycle' ||
        cat == 'motorcycle_repair') {
      return true;
    }
    if (title.contains('taller') ||
        title.contains('moto') ||
        title.contains('motos') ||
        title.contains('mecánic') ||
        title.contains('mecanic') ||
        title.contains('repuestos')) {
      return true;
    }
  }

  // Alojamiento
  if (q.contains('hotel') ||
      q.contains('hostal') ||
      q.contains('hospedaje') ||
      q.contains('motel')) {
    if (cat == 'hotel' ||
        cat == 'motel' ||
        cat == 'guest_house' ||
        cat == 'hostel') {
      return true;
    }
    if (title.contains('hotel') ||
        title.contains('hostal') ||
        title.contains('hospedaje')) {
      return true;
    }
  }

  // Salud
  if (q.contains('hospital') ||
      q.contains('clinica') ||
      q.contains('clínica') ||
      q.contains('farmacia') ||
      q.contains('drogueria') ||
      q.contains('droguería')) {
    if (cat == 'hospital' || cat == 'clinic' || cat == 'pharmacy') return true;
    if (title.contains('hospital') ||
        title.contains('clínica') ||
        title.contains('clinica') ||
        title.contains('droguería') ||
        title.contains('drogueria') ||
        title.contains('farmacia')) {
      return true;
    }
  }

  // Si no coincide con los patrones específicos, verificar si la categoría o texto coincide
  return cat.contains(q) || title.contains(q) || subtitle.contains(q);
}

/// Ordena y clasifica la lista de resultados de búsqueda:
/// 1. Si [userLocation] es nulo (sin GPS), conserva estrictamente el orden devuelto por el proveedor.
/// 2. Si es una búsqueda por categoría (ej. "gasolineras", "restaurantes", "talleres cerca"):
///    Prioriza los lugares que cumplen la categoría y los ordena de menor a mayor distancia.
/// 3. Si es una búsqueda por lugar específico (ej. "Armenia", "Salento", "Nevado del Ruiz"):
///    Prioriza coincidencia exacta y nominal de primer nivel; utiliza proximidad como desempate.
List<Destination> rankDestinations({
  required List<Destination> results,
  required String query,
  required Coordinates? userLocation,
}) {
  if (results.isEmpty) return [];

  // Si no se dispone de coordenadas del usuario, respetar estrictamente el orden del proveedor
  if (userLocation == null) {
    return results;
  }

  final cleanQuery = query.trim().toLowerCase();
  final isCategory = isCategoryQuery(cleanQuery);

  final sorted = List<Destination>.from(results);

  if (isCategory) {
    // Modo Categoría / Servicios Cercanos:
    // Prioridad a elementos que son del tipo solicitado, ordenados por distancia ascendente
    sorted.sort((a, b) {
      final aIsCat = matchesCategory(a, cleanQuery);
      final bIsCat = matchesCategory(b, cleanQuery);

      if (aIsCat != bIsCat) {
        return aIsCat ? -1 : 1; // Primero los que cumplen la categoría
      }

      // Ordenar por distancia ascendente
      final distA = userLocation.distanceTo(a.coordinates);
      final distB = userLocation.distanceTo(b.coordinates);
      return distA.compareTo(distB);
    });
    return sorted;
  }

  // Modo Lugar Específico (ej. "Armenia", "Salento", "Manizales Centro"):
  int matchTier(Destination d) {
    final title = d.title.trim().toLowerCase();
    if (title == cleanQuery) {
      return 0; // Coincidencia exacta de nombre
    }

    if (title.startsWith(cleanQuery)) {
      return 1; // Empieza con el término
    }

    if (title.contains(cleanQuery)) {
      return 2; // Contiene el término en el título
    }
    final subtitle = d.subtitle.trim().toLowerCase();
    if (subtitle.contains(cleanQuery)) {
      return 3; // Aparece en el subtítulo (municipio, vía)
    }
    return 4; // Otros


  }

  sorted.sort((a, b) {
    final tierA = matchTier(a);
    final tierB = matchTier(b);

    if (tierA != tierB) {
      return tierA.compareTo(tierB);
    }

    // A igual nivel de relevancia por nombre, priorizar el más cercano
    final distA = userLocation.distanceTo(a.coordinates);
    final distB = userLocation.distanceTo(b.coordinates);
    return distA.compareTo(distB);
  });

  return sorted;
}
