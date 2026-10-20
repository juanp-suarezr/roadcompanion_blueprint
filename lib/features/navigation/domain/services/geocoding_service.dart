import '../../../../domain/entities/coordinates.dart';
import '../entities/destination.dart';

/// Contrato para el servicio de geocodificación y búsqueda de lugares.
abstract class GeocodingService {
  /// Busca lugares y direcciones a partir de una consulta de texto [query].
  ///
  /// Opcionalmente pondera resultados cercanos a [proximityHint] si se suministra.
  Future<List<Destination>> search(
    String query, {
    Coordinates? proximityHint,
    int limit = 6,
  });

  /// Geocodificación inversa: obtiene el nombre legible de una coordenada.
  Future<Destination?> reverseGeocode(Coordinates coordinates);
}
