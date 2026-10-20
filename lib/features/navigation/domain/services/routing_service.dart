import '../../../../domain/entities/coordinates.dart';
import '../entities/calculated_route.dart';

/// Contrato para el motor de cálculo y enrutamiento vial en tiempo real.
abstract class RoutingService {
  /// Calcula la ruta óptima entre [origin] y [destination].
  ///
  /// Retorna un [CalculatedRoute] con geometría, maniobras y tiempo estimado,
  /// o lanza una excepción en caso de error de red o ruta inalcanzable.
  Future<CalculatedRoute> calculateRoute({
    required Coordinates origin,
    required Coordinates destination,
  });
}
