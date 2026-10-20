import 'coordinates.dart';
import 'maneuver.dart';

const Object _sentinel = Object();

/// Representa el plan de ruta inmutable de navegación por carretera.
///
/// Mantiene la separación estricta entre la distancia directa en línea recta
/// (Haversine) y la distancia real sobre el trazado vial (geometría de carretera).
class RoutePlan {
  /// Coordenada de origen del trayecto.
  final Coordinates origin;

  /// Coordenada de destino final.
  final Coordinates destination;

  /// Colección interna inmutable de maniobras paso a paso.
  final List<Maneuver> _maneuvers;

  /// Geometría detallada del trazado vial (polilínea de coordenadas).
  final List<Coordinates> _geometry;

  /// Distancia total por carretera en metros entregada por el motor de enrutamiento.
  ///
  /// ADVERTENCIA DE CONSISTENCIA: No debe asumirse consistencia estricta o identidad
  /// matemática entre [totalDistanceMeters] (provista por el motor de routing) y el resultado
  /// de [calculateGeometryDistance()] (suma euclidiana de los vértices de [geometry]).
  /// Los proveedores externos suelen aplicar algoritmos de simplificación de polilínea
  /// (como Ramer-Douglas-Peucker) para optimizar la transferencia de datos en red, o calcular
  /// la distancia vial a partir de grafos de aristas viales con curvas y modelos de elevación
  /// que no quedan representados vértice a vértice en la polilínea entregada.
  final double totalDistanceMeters;

  /// Duración estimada del trayecto.
  final Duration estimatedDuration;

  /// Distancia restante por carretera en metros hacia el destino (opcional).
  final double? remainingDistanceMeters;

  /// Crea un plan de ruta inmutable con validación estricta de métricas y colecciones protegidas.
  RoutePlan({
    required this.origin,
    required this.destination,
    required List<Maneuver> maneuvers,
    List<Coordinates> geometry = const [],
    required this.totalDistanceMeters,
    required this.estimatedDuration,
    this.remainingDistanceMeters,
  })  : _maneuvers = List.unmodifiable(maneuvers),
        _geometry = List.unmodifiable(geometry) {
    if (!totalDistanceMeters.isFinite) {
      throw ArgumentError.value(
        totalDistanceMeters,
        'totalDistanceMeters',
        'La distancia total debe ser un número finito.',
      );
    }
    if (totalDistanceMeters < 0.0) {
      throw ArgumentError.value(
        totalDistanceMeters,
        'totalDistanceMeters',
        'La distancia total por carretera no puede ser negativa.',
      );
    }
    if (estimatedDuration.isNegative) {
      throw ArgumentError.value(
        estimatedDuration,
        'estimatedDuration',
        'La duración estimada no puede ser negativa.',
      );
    }
    if (remainingDistanceMeters != null) {
      if (!remainingDistanceMeters!.isFinite) {
        throw ArgumentError.value(
          remainingDistanceMeters,
          'remainingDistanceMeters',
          'La distancia restante debe ser un número finito.',
        );
      }
      if (remainingDistanceMeters! < 0.0) {
        throw ArgumentError.value(
          remainingDistanceMeters,
          'remainingDistanceMeters',
          'La distancia restante por carretera no puede ser negativa.',
        );
      }
      if (remainingDistanceMeters! > totalDistanceMeters) {
        throw ArgumentError.value(
          remainingDistanceMeters,
          'remainingDistanceMeters',
          'La distancia restante ($remainingDistanceMeters m) no puede superar la distancia total por carretera ($totalDistanceMeters m).',
        );
      }
    }
  }

  /// Maniobras paso a paso de la ruta.
  ///
  /// Retorna una vista inmodificable: cualquier intento de alterarla lanzará [UnsupportedError].
  List<Maneuver> get maneuvers => _maneuvers;

  /// Trazado geométrico completo de la ruta por carretera.
  ///
  /// Retorna una vista inmodificable: cualquier intento de alterarla lanzará [UnsupportedError].
  List<Coordinates> get geometry => _geometry;

  /// Calcula la distancia directa ("a vuelo de pájaro") entre el origen y el destino.
  ///
  /// RESPONSABILIDAD:
  /// - Calcular la distancia ortodrómica en línea recta (gran círculo) entre [origin] y [destination]
  ///   mediante la fórmula de Haversine sobre la esfera terrestre.
  ///
  /// LIMITACIONES CRÍTICAS:
  /// - Ignora por completo la red de carreteras, el sentido del tránsito, giros y topografía.
  /// - NO representa la distancia real por carretera ni la distancia restante del viaje.
  /// - NO debe utilizarse para planificar consumos, tiempos de arribo ni autonomía.
  double calculateDirectDistance() {
    return origin.distanceTo(destination);
  }

  /// Calcula la longitud acumulada a lo largo de los segmentos rectos que componen la polilínea [geometry].
  ///
  /// RESPONSABILIDAD:
  /// - Medir la longitud total del trazado geométrico completo sumando las distancias de cada sub-tramo
  ///   secuencial de [geometry].
  ///
  /// LIMITACIONES CRÍTICAS:
  /// - NO calcula automáticamente la distancia restante desde la posición actual del GPS.
  /// - NO proyecta la ubicación del motociclista sobre la ruta ni evalúa el progreso del viaje.
  /// - Si [geometry] contiene menos de 2 coordenadas (ej. vacía o punto único), retorna estrictamente 0.0.
  /// - Puede diferir legítimamente de [totalDistanceMeters] si la polilínea entregada por el proveedor
  ///   está simplificada o carece de resolución submétrica.
  double calculateGeometryDistance() {
    if (_geometry.length < 2) return 0.0;

    double cumulative = 0.0;
    for (int i = 0; i < _geometry.length - 1; i++) {
      cumulative += _geometry[i].distanceTo(_geometry[i + 1]);
    }
    return cumulative;
  }

  /// Retorna una copia de este plan de ruta con una distancia restante por carretera actualizada.
  ///
  /// RESPONSABILIDAD:
  /// - Crear una nueva instancia inmutable de [RoutePlan] validando que [newRemainingMeters]
  ///   sea finito, no negativo y no exceda la distancia total.
  ///
  /// LIMITACIONES CRÍTICAS:
  /// - Es una función de asignación y validación pura sobre el estado inmutable.
  /// - NO calcula la distancia restante de forma automática ni consulta lecturas de sensores GPS.
  /// - El valor [newRemainingMeters] debe ser determinado externamente por la capa de navegación/sesión
  ///   a partir del progreso comprobado sobre el itinerario.
  RoutePlan copyWithRemainingDistance(double newRemainingMeters) {
    return RoutePlan(
      origin: origin,
      destination: destination,
      maneuvers: _maneuvers,
      geometry: _geometry,
      totalDistanceMeters: totalDistanceMeters,
      estimatedDuration: estimatedDuration,
      remainingDistanceMeters: newRemainingMeters,
    );
  }

  /// Crea una copia inmutable con campos modificados, permitiendo asignar `null` a [remainingDistanceMeters].
  RoutePlan copyWith({
    Coordinates? origin,
    Coordinates? destination,
    List<Maneuver>? maneuvers,
    List<Coordinates>? geometry,
    double? totalDistanceMeters,
    Duration? estimatedDuration,
    Object? remainingDistanceMeters = _sentinel,
  }) {
    return RoutePlan(
      origin: origin ?? this.origin,
      destination: destination ?? this.destination,
      maneuvers: maneuvers ?? _maneuvers,
      geometry: geometry ?? _geometry,
      totalDistanceMeters: totalDistanceMeters ?? this.totalDistanceMeters,
      estimatedDuration: estimatedDuration ?? this.estimatedDuration,
      remainingDistanceMeters: identical(remainingDistanceMeters, _sentinel)
          ? this.remainingDistanceMeters
          : remainingDistanceMeters as double?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RoutePlan || runtimeType != other.runtimeType) return false;

    if (origin != other.origin ||
        destination != other.destination ||
        totalDistanceMeters != other.totalDistanceMeters ||
        estimatedDuration != other.estimatedDuration ||
        remainingDistanceMeters != other.remainingDistanceMeters) {
      return false;
    }

    if (_maneuvers.length != other._maneuvers.length) return false;
    for (int i = 0; i < _maneuvers.length; i++) {
      if (_maneuvers[i] != other._maneuvers[i]) return false;
    }

    if (_geometry.length != other._geometry.length) return false;
    for (int i = 0; i < _geometry.length; i++) {
      if (_geometry[i] != other._geometry[i]) return false;
    }

    return true;
  }

  @override
  int get hashCode => Object.hash(
        origin,
        destination,
        Object.hashAll(_maneuvers),
        Object.hashAll(_geometry),
        totalDistanceMeters,
        estimatedDuration,
        remainingDistanceMeters,
      );

  @override
  String toString() =>
      'RoutePlan(origin: $origin, dest: $destination, roadDist: $totalDistanceMeters m, remaining: $remainingDistanceMeters m, maneuvers: ${_maneuvers.length})';
}
