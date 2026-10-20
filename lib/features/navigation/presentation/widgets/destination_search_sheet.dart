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
        _hasSearched = false;
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _executeSearch(query);
    });
  }

  Future<void> _executeSearch(String query) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _hasSearched = true;
    });

    try {
      final results = await widget.geocodingService.search(
        query,
        proximityHint: widget.userLocation,
      );

      if (!mounted) return;
      setState(() {
        _results = results;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage =
            'No se pudo conectar con el servicio de búsqueda. Verifica tu conexión a internet.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.82,
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
          const SizedBox(height: 14.0),

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
          else if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10.0),
              ),
              child: Row(
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

                  return Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.cardNavy
                          : AppColors.lightBackground,
                      borderRadius: BorderRadius.circular(12.0),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF264660)
                            : AppColors.silver,
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14.0,
                        vertical: 2.0,
                      ),
                      leading: CircleAvatar(
                        backgroundColor: isDark
                            ? AppColors.surfaceNavy
                            : const Color(0xFFE2EDF7),
                        child: Icon(
                          Icons.place,
                          size: 20.0,
                          color: isDark
                              ? AppColors.cyanLuminous
                              : AppColors.electricBlue,
                        ),
                      ),
                      title: Text(
                        dest.title,
                        style: TextStyle(
                          fontSize: 14.0,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppColors.coldWhite
                              : AppColors.primaryTextLight,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        dest.subtitle,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark
                              ? AppColors.secondaryText
                              : AppColors.secondaryTextLight,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: distanceKm != null
                          ? Text(
                              '${distanceKm.toStringAsFixed(1)} km',
                              style: TextStyle(
                                fontSize: 11.0,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? AppColors.cyanLuminous
                                    : AppColors.electricBlue,
                              ),
                            )
                          : const Icon(Icons.arrow_forward_ios, size: 14.0),
                      onTap: () => widget.onDestinationSelected(dest),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
