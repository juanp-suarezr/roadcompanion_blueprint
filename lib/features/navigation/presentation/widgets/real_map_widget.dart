import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../domain/entities/coordinates.dart';
import 'real_map_tile_config.dart';

/// Visor cartográfico interactivo real basado en [FlutterMap].
///
/// Proporciona renderizado de carreteras reales, calles, cruces y nombres geográficos.
/// Si se configura una clave CARTO (vía `--dart-define=CARTO_API_KEY=...` o [cartoApiKey]),
/// renderiza el tema oscuro CartoDB Dark Matter. Si no se provee clave, conmuta automáticamente
/// a las teselas estándar de OpenStreetMap para evitar marcas de agua y garantizar un mapa 100% funcional.
class RealMapWidget extends StatelessWidget {
  final MapController mapController;
  final LatLng initialCenter;
  final double initialZoom;
  final Coordinates? riderPosition;
  final double? riderHeading;
  final double? accuracyMeters;
  final List<Coordinates>? routeGeometry;
  final List<List<Coordinates>>? alternativeGeometries;
  final Coordinates? destinationCoordinates;
  final VoidCallback? onRecenter;
  final MapTileProvider tileProvider;
  final String? cartoApiKey;
  final double controlsBottomOffset;
  final List<Marker>? additionalMarkers;

  const RealMapWidget({
    super.key,
    required this.mapController,
    this.initialCenter = const LatLng(
      5.0689,
      -75.5174,
    ), // Manizales / Caldas por defecto
    this.initialZoom = 13.5,
    this.riderPosition,
    this.riderHeading,
    this.accuracyMeters,
    this.routeGeometry,
    this.alternativeGeometries,
    this.destinationCoordinates,
    this.onRecenter,
    this.tileProvider = MapTileProvider.auto,
    this.cartoApiKey,
    this.controlsBottomOffset = 120.0,
    this.additionalMarkers,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Convertir coordenadas de dominio a LatLng de latlong2
    final polylinePoints = routeGeometry != null && routeGeometry!.isNotEmpty
        ? routeGeometry!.map((c) => LatLng(c.latitude, c.longitude)).toList()
        : <LatLng>[];

    final markers = <Marker>[];

    // 1. Marcador de Destino
    if (destinationCoordinates != null) {
      markers.add(
        Marker(
          point: LatLng(
            destinationCoordinates!.latitude,
            destinationCoordinates!.longitude,
          ),
          width: 44.0,
          height: 44.0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(6.0),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.0),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 6.0,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(Icons.flag, color: Colors.white, size: 16.0),
              ),
            ],
          ),
        ),
      );
    }

    // 2. Marcador del motociclista en tiempo real (Rider)
    if (riderPosition != null) {
      final riderLatLng = LatLng(
        riderPosition!.latitude,
        riderPosition!.longitude,
      );

      markers.add(
        Marker(
          point: riderLatLng,
          width: 50.0,
          height: 50.0,
          child: _RiderLocationMarker(
            heading: riderHeading,
            accuracyMeters: accuracyMeters,
          ),
        ),
      );
    }

    // 3. Marcadores adicionales (POIs, paradas intermedias, origen)
    if (additionalMarkers != null && additionalMarkers!.isNotEmpty) {
      markers.addAll(additionalMarkers!);
    }

    final tileConfig = RealMapTileConfig(
      provider: tileProvider,
      customCartoApiKey: cartoApiKey,
      isDark: isDark,
    );

    // Si se exigió explícitamente CARTO sin proveer clave, mostrar error explicativo
    if (tileConfig.hasConfigurationError) {
      return Container(
        color: isDark ? AppColors.nightBlue : AppColors.lightBackground,
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.vpn_key_off_outlined,
                size: 54.0,
                color: AppColors.error,
              ),
              const SizedBox(height: 16.0),
              Text(
                'Clave de CARTO requerida',
                style: AppTypography.sectionTitle.copyWith(
                  color: isDark
                      ? AppColors.coldWhite
                      : AppColors.primaryTextLight,
                ),
              ),
              const SizedBox(height: 10.0),
              Text(
                'Has configurado el proveedor de mapas CARTO pero no se detectó una clave API válida.\n\n'
                'Para activarlo de forma segura en Android o Flutter, ejecuta o compila con:\n'
                'flutter run --dart-define=CARTO_API_KEY=tu_clave\n\n'
                'O selecciona el proveedor OpenStreetMap estándar (gratuito y sin marcas de agua).',
                style: TextStyle(
                  fontSize: 13.0,
                  height: 1.4,
                  color: isDark
                      ? AppColors.secondaryTextDark
                      : AppColors.secondaryTextLight,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        // Mapa interactivo real
        FlutterMap(
          mapController: mapController,
          options: MapOptions(
            initialCenter: riderPosition != null
                ? LatLng(riderPosition!.latitude, riderPosition!.longitude)
                : initialCenter,
            initialZoom: initialZoom,
            minZoom: 4.0,
            maxZoom: 19.0,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all,
            ),
          ),
          children: [
            // Capa de teselas cartográficas (CartoDB Dark Matter / OSM estándar)
            TileLayer(
              urlTemplate: tileConfig.tileUrl,
              subdomains: tileConfig.subdomains,
              userAgentPackageName: 'app.roadcompanion.restelar',
              tileProvider: NetworkTileProvider(),
            ),

            // Capa de polilíneas de rutas alternativas (estilo atenuado/secundario)
            if (alternativeGeometries != null &&
                alternativeGeometries!.isNotEmpty) ...[
              PolylineLayer(
                polylines: alternativeGeometries!
                    .where((geom) => geom.isNotEmpty)
                    .map(
                      (geom) => Polyline(
                        points: geom
                            .map((c) => LatLng(c.latitude, c.longitude))
                            .toList(),
                        strokeWidth: 4.5,
                        color: isDark
                            ? const Color(0xFF627D98).withValues(alpha: 0.75)
                            : const Color(0xFF829AB1).withValues(alpha: 0.8),
                      ),
                    )
                    .toList(),
              ),
            ],

            // Capa de polilíneas de ruta calculada o GPX principal seleccionada
            if (polylinePoints.isNotEmpty) ...[
              // Sombra / contorno de alto contraste
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: polylinePoints,
                    strokeWidth: 8.0,
                    color: (isDark ? AppColors.nightBlue : Colors.black)
                        .withValues(alpha: 0.6),
                  ),
                ],
              ),
              // Trazo vial luminoso de REstelar
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: polylinePoints,
                    strokeWidth: 5.0,
                    color: isDark
                        ? AppColors.cyanLuminous
                        : AppColors.electricBlue,
                  ),
                ],
              ),
            ],

            // Capa de marcadores (Posición del rider y destino)
            MarkerLayer(markers: markers),

            // Atribución permanente del proveedor de datos abierta
            SimpleAttributionWidget(
              alignment: Alignment.bottomLeft,
              source: Text(
                tileConfig.attributionText,
                style: const TextStyle(fontSize: 8.5, color: Colors.white70),
              ),
            ),
          ],
        ),

        // Aviso discreto cuando se utiliza el fallback de OSM en modo oscuro
        if (tileConfig.darkFallbackNotice != null)
          Positioned(
            top: 10.0,
            left: 16.0,
            right: 16.0,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12.0,
                vertical: 6.0,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 14.0,
                    color: AppColors.cyanLuminous,
                  ),
                  const SizedBox(width: 8.0),
                  Expanded(
                    child: Text(
                      tileConfig.darkFallbackNotice!,
                      style: const TextStyle(
                        fontSize: 11.0,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Controles de zoom y centrado sobre el mapa
        Positioned(
          right: 14.0,
          bottom: controlsBottomOffset,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Botón Recentrar en mi ubicación GPS
              if (onRecenter != null) ...[
                _buildMapFloatingButton(
                  icon: Icons.my_location,
                  tooltip: 'Centrar en mi ubicación',
                  onPressed: onRecenter!,
                  isDark: isDark,
                  isHighlighted: riderPosition != null,
                ),
                const SizedBox(height: 10.0),
              ],

              // Zoom In
              _buildMapFloatingButton(
                icon: Icons.add,
                tooltip: 'Acercar',
                onPressed: () {
                  final zoom = mapController.camera.zoom;
                  mapController.move(mapController.camera.center, zoom + 1);
                },
                isDark: isDark,
              ),
              const SizedBox(height: 6.0),

              // Zoom Out
              _buildMapFloatingButton(
                icon: Icons.remove,
                tooltip: 'Alejar',
                onPressed: () {
                  final zoom = mapController.camera.zoom;
                  mapController.move(mapController.camera.center, zoom - 1);
                },
                isDark: isDark,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMapFloatingButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    required bool isDark,
    bool isHighlighted = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: isHighlighted
            ? (isDark ? AppColors.surfaceNavy : AppColors.whiteSurface)
            : (isDark ? AppColors.cardNavy : AppColors.whiteSurface),
        shape: const CircleBorder(),
        elevation: 4.0,
        shadowColor: Colors.black54,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(10.0),
            child: Icon(
              icon,
              size: 20.0,
              color: isHighlighted
                  ? (isDark ? AppColors.cyanLuminous : AppColors.electricBlue)
                  : (isDark ? AppColors.coldWhite : AppColors.primaryTextLight),
            ),
          ),
        ),
      ),
    );
  }
}

class _RiderLocationMarker extends StatelessWidget {
  final double? heading;
  final double? accuracyMeters;

  const _RiderLocationMarker({this.heading, this.accuracyMeters});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Halo exterior translúcido
          Container(
            width: 44.0,
            height: 44.0,
            decoration: BoxDecoration(
              color: AppColors.cyanLuminous.withValues(alpha: 0.22),
              shape: BoxShape.circle,
            ),
          ),
          // Borde blanco de alto contraste
          Container(
            width: 22.0,
            height: 22.0,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 4.0,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
          // Centro azul cian o flecha de rumbo
          if (heading != null && heading! >= 0)
            Transform.rotate(
              angle: (heading! * pi) / 180.0,
              child: const Icon(
                Icons.navigation,
                size: 16.0,
                color: AppColors.surfaceNavy,
              ),
            )
          else
            Container(
              width: 14.0,
              height: 14.0,
              decoration: const BoxDecoration(
                color: AppColors.cyanLuminous,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }
}
