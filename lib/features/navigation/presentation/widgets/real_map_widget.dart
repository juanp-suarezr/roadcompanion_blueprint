import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../domain/entities/coordinates.dart';

/// Visor cartográfico interactivo real basado en [FlutterMap].
///
/// Proporciona renderizado de carreteras reales, calles, cruces y nombres geográficos
/// con soporte para el tema oscuro oficial de ESTELA (CartoDB Dark Matter) y claro (OpenStreetMap).
class RealMapWidget extends StatelessWidget {
  final MapController mapController;
  final LatLng initialCenter;
  final double initialZoom;
  final Coordinates? riderPosition;
  final double? riderHeading;
  final double? accuracyMeters;
  final List<Coordinates>? routeGeometry;
  final Coordinates? destinationCoordinates;
  final VoidCallback? onRecenter;

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
    this.destinationCoordinates,
    this.onRecenter,
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

    // URL del servidor de teselas cartográficas
    final tileUrl = isDark
        ? 'https://{s}.basemaps.cartocdn.com/rastertiles/dark_all/{z}/{x}/{y}.png'
        : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

    final subdomains = isDark ? const ['a', 'b', 'c', 'd'] : const <String>[];

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
            // Capa de teselas cartográficas (CartoDB Dark Matter / OSM)
            TileLayer(
              urlTemplate: tileUrl,
              subdomains: subdomains,
              userAgentPackageName: 'app.roadcompanion.estela',
              tileProvider: NetworkTileProvider(),
            ),

            // Capa de polilíneas de ruta calculada o GPX
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
              // Trazo vial luminoso de ESTELA
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

            // Atribución de fuente de datos abierta
            const RichAttributionWidget(
              alignment: AttributionAlignment.bottomLeft,
              attributions: [
                TextSourceAttribution(
                  '© OpenStreetMap, © CARTO',
                  textStyle: TextStyle(fontSize: 9.0, color: Colors.white70),
                ),
              ],
            ),
          ],
        ),

        // Controles de zoom y centrado sobre el mapa
        Positioned(
          right: 14.0,
          bottom: 120.0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Botón Recentrar en mi ubicación GPS
              if (onRecenter != null && riderPosition != null) ...[
                _buildMapFloatingButton(
                  icon: Icons.my_location,
                  tooltip: 'Centrar en mi ubicación',
                  onPressed: onRecenter!,
                  isDark: isDark,
                  isHighlighted: true,
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
    return Material(
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
