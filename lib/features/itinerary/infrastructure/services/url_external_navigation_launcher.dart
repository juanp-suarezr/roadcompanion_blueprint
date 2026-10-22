import 'package:flutter/services.dart';
import '../../../../domain/entities/coordinates.dart';
import '../../domain/entities/trip_itinerary.dart';
import '../../domain/services/external_navigation_launcher.dart';

/// Implementación del servicio de exportación y lanzamiento hacia Google Maps y Waze.
///
/// Genera URLs codificadas y delegadas hacia la plataforma nativa o un lanzador inyectable.
class UrlExternalNavigationLauncher implements ExternalNavigationLauncher {
  final Future<bool> Function(String url)? _urlOpener;
  final MethodChannel _controlChannel;

  UrlExternalNavigationLauncher({
    Future<bool> Function(String url)? urlOpener,
    MethodChannel? controlChannel,
  }) : _urlOpener = urlOpener,
       _controlChannel =
           controlChannel ?? const MethodChannel('es.estela/bridge_controls');

  @override
  String buildGoogleMapsUrl(TripItinerary itinerary, {int maxWaypoints = 3}) {
    final origin = itinerary.origin.coordinates;
    final destination = itinerary.destination.coordinates;

    final pendingStops = itinerary.stops.where((s) => !s.isVisited).toList();
    final stopsToInclude = pendingStops.take(maxWaypoints).toList();

    // NOTA DE ESPECIFICACIÓN TÉCNICA:
    // La documentación oficial de Google Maps URLs (https://developers.google.com/maps/documentation/urls/get-started)
    // define los modos: driving, walking, bicycling, transit.
    // 'two-wheeler' no forma parte de la especificación pública estándar de URLs y puede ser ignorado.
    // Por tanto, se utiliza 'driving' (modo vehicular oficial documentado).
    final queryParams = <String, String>{
      'api': '1',
      'origin':
          '${origin.latitude.toStringAsFixed(6)},${origin.longitude.toStringAsFixed(6)}',
      'destination':
          '${destination.latitude.toStringAsFixed(6)},${destination.longitude.toStringAsFixed(6)}',
      'travelmode': 'driving',
    };

    if (stopsToInclude.isNotEmpty) {
      final waypointsValue = stopsToInclude
          .map(
            (s) =>
                '${s.coordinates.latitude.toStringAsFixed(6)},${s.coordinates.longitude.toStringAsFixed(6)}',
          )
          .join('|');
      queryParams['waypoints'] = waypointsValue;
    }

    final uri = Uri.https('www.google.com', '/maps/dir/', queryParams);
    return uri.toString();
  }

  @override
  String buildWazeUrl(TripItinerary itinerary) {
    final target = itinerary.nextActiveDestination.coordinates;

    final queryParams = <String, String>{
      'll':
          '${target.latitude.toStringAsFixed(6)},${target.longitude.toStringAsFixed(6)}',
      'navigate': 'yes',
    };

    final uri = Uri.https('waze.com', '/ul', queryParams);
    return uri.toString();
  }

  @override
  String buildQuickGoogleMapsUrl({
    Coordinates? destinationCoordinates,
    String? destinationQuery,
    Coordinates? origin,
  }) {
    final queryParams = <String, String>{'api': '1', 'travelmode': 'driving'};

    if (destinationCoordinates != null) {
      queryParams['destination'] =
          '${destinationCoordinates.latitude.toStringAsFixed(6)},${destinationCoordinates.longitude.toStringAsFixed(6)}';
    } else if (destinationQuery != null && destinationQuery.trim().isNotEmpty) {
      queryParams['destination'] = destinationQuery.trim();
    } else {
      throw ArgumentError(
        'Se requiere destino (coordenadas o consulta textual).',
      );
    }

    if (origin != null) {
      queryParams['origin'] =
          '${origin.latitude.toStringAsFixed(6)},${origin.longitude.toStringAsFixed(6)}';
    } else {
      queryParams['dir_action'] = 'navigate';
    }

    final uri = Uri.https('www.google.com', '/maps/dir/', queryParams);
    return uri.toString();
  }

  @override
  String buildQuickWazeUrl({
    Coordinates? destinationCoordinates,
    String? destinationQuery,
  }) {
    final queryParams = <String, String>{'navigate': 'yes'};

    if (destinationCoordinates != null) {
      queryParams['ll'] =
          '${destinationCoordinates.latitude.toStringAsFixed(6)},${destinationCoordinates.longitude.toStringAsFixed(6)}';
    } else if (destinationQuery != null && destinationQuery.trim().isNotEmpty) {
      queryParams['q'] = destinationQuery.trim();
    } else {
      throw ArgumentError(
        'Se requiere destino (coordenadas o consulta textual).',
      );
    }

    final uri = Uri.https('waze.com', '/ul', queryParams);
    return uri.toString();
  }

  @override
  Future<NavigationExportResult> launchGoogleMaps(
    TripItinerary itinerary, {
    int maxWaypoints = 3,
    bool launchExternal = true,
  }) async {
    final pendingStops = itinerary.stops.where((s) => !s.isVisited).toList();
    final includedCount = pendingStops.length > maxWaypoints
        ? maxWaypoints
        : pendingStops.length;
    final omittedCount = pendingStops.length > maxWaypoints
        ? pendingStops.length - maxWaypoints
        : 0;

    final url = buildGoogleMapsUrl(itinerary, maxWaypoints: maxWaypoints);

    String? warning;
    if (omittedCount > 0) {
      warning =
          'Google Maps en navegadores móviles admite un número acotado de paradas intermedias (hasta $maxWaypoints). '
          'Se exportaron las primeras $includedCount de ${pendingStops.length} paradas pendientes. '
          'Las $omittedCount restantes permanecen guardadas en tu itinerario de REstelar. '
          'Aviso: la ruta se abre en modo conducción vehicular (driving), ya que Google Maps no admite modo motocicleta en URLs universales.';
    }

    if (!launchExternal) {
      return NavigationExportResult(
        success: true,
        url: url,
        warningMessage: warning,
        exportedStopsCount: includedCount,
        omittedStopsCount: omittedCount,
        targetName: itinerary.destination.name,
      );
    }

    final opened = await _openUrl(url);
    if (!opened) {
      return NavigationExportResult(
        success: false,
        url: url,
        warningMessage: warning,
        errorMessage:
            'No fue posible abrir Google Maps. Verifica que la aplicación o un navegador web estén disponibles en tu teléfono.',
        exportedStopsCount: includedCount,
        omittedStopsCount: omittedCount,
        targetName: itinerary.destination.name,
      );
    }

    return NavigationExportResult(
      success: true,
      url: url,
      warningMessage: warning,
      exportedStopsCount: includedCount,
      omittedStopsCount: omittedCount,
      targetName: itinerary.destination.name,
    );
  }

  @override
  Future<NavigationExportResult> launchWaze(
    TripItinerary itinerary, {
    bool launchExternal = true,
  }) async {
    final target = itinerary.nextActiveDestination;
    final url = buildWazeUrl(itinerary);

    String? warning;
    final pendingCount = itinerary.pendingStopsCount;
    if (pendingCount > 0) {
      warning =
          'Waze no admite paradas intermedias múltiples vía enlace externo. '
          'Se ha enviado la navegación hacia la siguiente parada activa: "${target.name}". '
          'El itinerario completo se conserva en REstelar para continuar tras cada tramo.';
    }

    if (!launchExternal) {
      return NavigationExportResult(
        success: true,
        url: url,
        warningMessage: warning,
        exportedStopsCount: 1,
        omittedStopsCount: pendingCount > 1 ? pendingCount - 1 : 0,
        targetName: target.name,
      );
    }

    final opened = await _openUrl(url);
    if (!opened) {
      return NavigationExportResult(
        success: false,
        url: url,
        warningMessage: warning,
        errorMessage:
            'No fue posible abrir Waze. Verifica que la aplicación esté instalada o prueba abrir la ruta en Google Maps.',
        exportedStopsCount: 1,
        omittedStopsCount: pendingCount > 1 ? pendingCount - 1 : 0,
        targetName: target.name,
      );
    }

    return NavigationExportResult(
      success: true,
      url: url,
      warningMessage: warning,
      exportedStopsCount: 1,
      omittedStopsCount: pendingCount > 1 ? pendingCount - 1 : 0,
      targetName: target.name,
    );
  }

  @override
  Future<NavigationExportResult> launchQuickGoogleMaps({
    Coordinates? destinationCoordinates,
    String? destinationQuery,
    Coordinates? origin,
    String targetName = '',
    bool launchExternal = true,
  }) async {
    try {
      final url = buildQuickGoogleMapsUrl(
        destinationCoordinates: destinationCoordinates,
        destinationQuery: destinationQuery,
        origin: origin,
      );

      final label = targetName.isNotEmpty
          ? targetName
          : (destinationQuery ?? 'Destino seleccionado');

      if (!launchExternal) {
        return NavigationExportResult(
          success: true,
          url: url,
          targetName: label,
          exportedStopsCount: 1,
        );
      }

      final opened = await _openUrl(url);
      if (!opened) {
        return NavigationExportResult(
          success: false,
          url: url,
          targetName: label,
          errorMessage:
              'No fue posible abrir Google Maps. Verifica que la aplicación o un navegador web estén disponibles en tu teléfono.',
        );
      }

      return NavigationExportResult(
        success: true,
        url: url,
        targetName: label,
        exportedStopsCount: 1,
      );
    } catch (e) {
      return NavigationExportResult(
        success: false,
        errorMessage: 'Error al generar navegación rápida de Google Maps: $e',
      );
    }
  }

  @override
  Future<NavigationExportResult> launchQuickWaze({
    Coordinates? destinationCoordinates,
    String? destinationQuery,
    String targetName = '',
    bool launchExternal = true,
  }) async {
    try {
      final url = buildQuickWazeUrl(
        destinationCoordinates: destinationCoordinates,
        destinationQuery: destinationQuery,
      );

      final label = targetName.isNotEmpty
          ? targetName
          : (destinationQuery ?? 'Destino seleccionado');

      if (!launchExternal) {
        return NavigationExportResult(
          success: true,
          url: url,
          targetName: label,
          exportedStopsCount: 1,
        );
      }

      final opened = await _openUrl(url);
      if (!opened) {
        return NavigationExportResult(
          success: false,
          url: url,
          targetName: label,
          errorMessage:
              'No fue posible abrir Waze. Verifica que la aplicación esté instalada o prueba abrir la ruta en Google Maps.',
        );
      }

      return NavigationExportResult(
        success: true,
        url: url,
        targetName: label,
        exportedStopsCount: 1,
      );
    } catch (e) {
      return NavigationExportResult(
        success: false,
        errorMessage: 'Error al generar navegación rápida de Waze: $e',
      );
    }
  }

  Future<bool> _openUrl(String url) async {
    if (_urlOpener != null) {
      return _urlOpener(url);
    }

    try {
      final success = await _controlChannel.invokeMethod<bool>('launchUrl', {
        'url': url,
      });
      return success ?? false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
