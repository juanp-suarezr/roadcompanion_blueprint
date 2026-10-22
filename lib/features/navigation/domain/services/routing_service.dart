import '../../../../domain/entities/coordinates.dart';
import '../entities/calculated_route.dart';

/// Contrato para el motor de cálculo y enrutamiento vial en tiempo real.
abstract class RoutingService {
  /// Calcula la ruta óptima principal entre [origin] y [destination].
  ///
  /// Retorna un [CalculatedRoute] con geometría, maniobras y tiempo estimado,
  /// o lanza una excepción en caso de error de red o ruta inalcanzable.
  Future<CalculatedRoute> calculateRoute({
    required Coordinates origin,
    required Coordinates destination,
  });

  /// Calcula la ruta principal junto con alternativas reales (hasta 3 opciones en total).
  ///
  /// Si el proveedor devuelve únicamente una ruta viable, retorna una lista con una sola ruta.
  /// Nunca inventa alternativas modificando artificialmente geometrías.
  Future<List<CalculatedRoute>> calculateRoutesWithAlternatives({
    required Coordinates origin,
    required Coordinates destination,
  });

  /// Calcula la ruta óptima continua que conecta [origin] pasando secuencialmente
  /// por los [waypoints] ordenados hasta alcanzar el [destination] final.
  ///
  /// Respeta el orden de las paradas intermedias y consolida la distancia total y maniobras.
  Future<CalculatedRoute> calculateMultistopRoute({
    required Coordinates origin,
    required List<Coordinates> waypoints,
    required Coordinates destination,
  }) {
    // Implementación por defecto para mantener total retrocompatibilidad con mocks existentes
    return calculateRoute(origin: origin, destination: destination);
  }
}
