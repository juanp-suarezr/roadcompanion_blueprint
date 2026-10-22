import '../../../../domain/entities/coordinates.dart';
import '../entities/trip_itinerary.dart';

/// Resultado detallado de la exportación y lanzamiento hacia un navegador externo.
class NavigationExportResult {
  /// Indica si la URL fue generada y abierta exitosamente.
  final bool success;

  /// URL o Deep Link final generado.
  final String? url;

  /// Advertencia de incompatibilidad o limitación (ej. waypoints omitidos o navegación por tramos).
  final String? warningMessage;

  /// Mensaje de error si la aplicación o el navegador no pudieron abrirse.
  final String? errorMessage;

  /// Cantidad de paradas intermedias que pudieron incluirse en el enlace.
  final int exportedStopsCount;

  /// Cantidad de paradas intermedias omitidas debido a los límites de la app externa.
  final int omittedStopsCount;

  /// Nombre del destino inmediato hacia el que se abrió la navegación.
  final String targetName;

  const NavigationExportResult({
    required this.success,
    this.url,
    this.warningMessage,
    this.errorMessage,
    this.exportedStopsCount = 0,
    this.omittedStopsCount = 0,
    this.targetName = '',
  });

  /// Indica si hubo paradas intermedias que la app externa no pudo admitir.
  bool get hasOmittedStops => omittedStopsCount > 0;
}

/// Contrato para generar y lanzar itinerarios hacia navegadores externos oficiales (Google Maps y Waze).
abstract class ExternalNavigationLauncher {
  /// Construye y lanza la ruta en Google Maps mediante Maps URLs oficiales.
  ///
  /// [maxWaypoints] define el umbral de paradas intermedias admitidas (por defecto 3
  /// para garantizar compatibilidad con navegadores móviles según la documentación oficial de Google).
  /// Si [launchExternal] es false, únicamente genera la URL sin abrir la aplicación.
  Future<NavigationExportResult> launchGoogleMaps(
    TripItinerary itinerary, {
    int maxWaypoints = 3,
    bool launchExternal = true,
  });

  /// Construye y lanza la siguiente parada activa o destino final en Waze mediante Deep Link oficial.
  ///
  /// Nota de limitación: Waze no soporta múltiples waypoints mediante enlaces externos.
  Future<NavigationExportResult> launchWaze(
    TripItinerary itinerary, {
    bool launchExternal = true,
  });

  /// Construye la URL codificada oficial para Google Maps.
  String buildGoogleMapsUrl(TripItinerary itinerary, {int maxWaypoints = 3});

  /// Construye el Deep Link oficial para Waze hacia la siguiente parada activa.
  String buildWazeUrl(TripItinerary itinerary);

  /// Construye la URL oficial de Google Maps para navegación rápida hacia un destino
  /// (coordenadas o consulta textual).
  ///
  /// Si [origin] no es especificado, se omite el origen explícito y se emplea
  /// `dir_action=navigate` para navegar desde la ubicación actual del dispositivo.
  String buildQuickGoogleMapsUrl({
    Coordinates? destinationCoordinates,
    String? destinationQuery,
    Coordinates? origin,
  });

  /// Construye el enlace oficial de Waze para navegación rápida hacia un destino.
  /// Si se indican [destinationCoordinates], se usa `ll=LAT,LON&navigate=yes`.
  /// Si únicamente se indica [destinationQuery], se usa `q=QUERY&navigate=yes`.
  String buildQuickWazeUrl({
    Coordinates? destinationCoordinates,
    String? destinationQuery,
  });

  /// Lanza la navegación rápida en Google Maps hacia un destino sin necesidad de itinerario previo.
  Future<NavigationExportResult> launchQuickGoogleMaps({
    Coordinates? destinationCoordinates,
    String? destinationQuery,
    Coordinates? origin,
    String targetName = '',
    bool launchExternal = true,
  });

  /// Lanza la navegación rápida en Waze hacia un destino sin necesidad de itinerario previo.
  Future<NavigationExportResult> launchQuickWaze({
    Coordinates? destinationCoordinates,
    String? destinationQuery,
    String targetName = '',
    bool launchExternal = true,
  });
}
