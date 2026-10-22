import '../../../../domain/entities/coordinates.dart';
import '../../../../domain/services/route_progress_calculator.dart';
import '../../../../features/navigation/domain/entities/calculated_route.dart';
import '../../../../features/navigation/domain/entities/destination.dart';
import 'trip_stop.dart';

/// Representación inmutable de un plan de viaje multiparada en REstelar.
///
/// Mantiene la soberanía del itinerario definido por el motociclista
/// (origen, paradas intermedias ordenadas y destino final), independientemente
/// de las decisiones de enrutamiento o recálculos de navegadores externos.
class TripItinerary {
  /// Identificador único del itinerario.
  final String id;

  /// Título o nombre asignado al viaje (ej. "Ruta de los Pueblos Blancos").
  final String title;

  /// Punto de origen o partida del viaje.
  final Destination origin;

  /// Destino final del viaje.
  final Destination destination;

  /// Lista ordenada de paradas intermedias.
  final List<TripStop> stops;

  /// Fecha de creación del itinerario.
  final DateTime createdAt;

  /// Fecha de última modificación del itinerario.
  final DateTime updatedAt;

  /// Ruta vial calculada por el motor OSRM para este itinerario (si está disponible).
  final CalculatedRoute? calculatedRoute;

  TripItinerary({
    required this.id,
    required this.title,
    required this.origin,
    required this.destination,
    this.stops = const [],
    required this.createdAt,
    required this.updatedAt,
    this.calculatedRoute,
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(
        id,
        'id',
        'El identificador del itinerario no puede estar vacío.',
      );
    }
    if (title.trim().isEmpty) {
      throw ArgumentError.value(
        title,
        'title',
        'El título del itinerario no puede estar vacío.',
      );
    }

    // Validar que no existan IDs de paradas duplicados
    final ids = <String>{};
    for (final stop in stops) {
      if (!ids.add(stop.id)) {
        throw ArgumentError(
          'El itinerario contiene paradas duplicadas con el mismo identificador: "${stop.id}".',
        );
      }
    }
  }

  /// Retorna la siguiente parada intermedia activa que aún no ha sido visitada.
  /// Si todas las paradas intermedias fueron visitadas o no hay paradas, retorna `null`.
  TripStop? get nextActiveStop {
    for (final stop in stops) {
      if (!stop.isVisited) {
        return stop;
      }
    }
    return null;
  }

  /// Retorna el siguiente destino activo hacia el cual debe dirigirse el conductor:
  /// - Si hay una parada pendiente, retorna esa parada como [Destination].
  /// - Si todas las paradas fueron visitadas o la lista está vacía, retorna el [destination] final.
  Destination get nextActiveDestination {
    final active = nextActiveStop;
    if (active != null) {
      return Destination(
        id: 'stop_${active.id}',
        title: active.name,
        subtitle: active.type.displayName,
        coordinates: active.coordinates,
        category: active.type.name,
      );
    }
    return destination;
  }

  /// Total de paradas intermedias configuradas.
  int get totalStopsCount => stops.length;

  /// Cantidad de paradas intermedias pendientes por visitar.
  int get pendingStopsCount => stops.where((s) => !s.isVisited).length;

  /// Indica si todas las paradas intermedias ya fueron completadas.
  bool get allStopsVisited => stops.isNotEmpty && pendingStopsCount == 0;

  /// Retorna una copia con una nueva parada añadida al final de la secuencia.
  TripItinerary addStop(TripStop stop) {
    if (stops.any((s) => s.id == stop.id)) {
      throw ArgumentError(
        'Ya existe una parada con el ID "${stop.id}" en el itinerario.',
      );
    }

    final newStops = List<TripStop>.from(stops);
    final indexedStop = stop.copyWith(orderIndex: newStops.length);
    newStops.add(indexedStop);

    return copyWith(
      stops: newStops,
      updatedAt: DateTime.now(),
      // Al cambiar la secuencia de paradas, la ruta anterior debe recalcularse
      calculatedRoute: null,
    );
  }

  /// Inserta una nueva parada en la posición óptima a lo largo de la ruta vial,
  /// preservando el origen, el destino y el estado de visitada de las demás paradas.
  TripItinerary insertStopAtRoutePosition(
    TripStop stop, {
    required double distanceAlongRouteMeters,
    List<Coordinates>? routeGeometry,
  }) {
    if (stops.any((s) => s.id == stop.id)) {
      throw ArgumentError(
        'Ya existe una parada con el ID "${stop.id}" en el itinerario.',
      );
    }

    if (distanceAlongRouteMeters.isNaN ||
        distanceAlongRouteMeters.isInfinite ||
        distanceAlongRouteMeters < 0) {
      throw ArgumentError.value(
        distanceAlongRouteMeters,
        'distanceAlongRouteMeters',
        'El avance sobre la ruta debe ser un valor numérico finito no negativo.',
      );
    }

    if (stops.isEmpty) {
      return addStop(stop);
    }

    // Si existen paradas previas y no hay geometría de ruta válida, el orden relativo
    // no puede calcularse con fiabilidad: no se inventa una posición arbitraria.
    if (routeGeometry == null || routeGeometry.length < 2) {
      throw StateError(
        'No es posible determinar el orden secuencial de la parada en el itinerario sin una geometría de ruta calculada válida.',
      );
    }

    const calculator = RouteProgressCalculator();
    int insertIndex = stops.length;

    for (int i = 0; i < stops.length; i++) {
      final existingStop = stops[i];
      try {
        final existingProgress = calculator.calculate(
          geometry: routeGeometry,
          currentPosition: existingStop.coordinates,
        );
        if (distanceAlongRouteMeters <
            existingProgress.distanceTraveledMeters) {
          insertIndex = i;
          break;
        }
      } catch (_) {
        throw StateError(
          'No fue posible determinar con fiabilidad la posición relativa de la parada existente "${existingStop.name}".',
        );
      }
    }

    final newStops = List<TripStop>.from(stops);
    newStops.insert(insertIndex, stop);

    // Renumerar índices de orden 0..N-1 conservando su estado isVisited
    final reindexed = <TripStop>[];
    for (int i = 0; i < newStops.length; i++) {
      reindexed.add(newStops[i].copyWith(orderIndex: i));
    }

    return copyWith(
      stops: reindexed,
      updatedAt: DateTime.now(),
      calculatedRoute: null,
    );
  }

  /// Retorna una copia con la parada eliminada y los índices de orden renumerados.
  TripItinerary removeStop(String stopId) {
    final filtered = stops.where((s) => s.id != stopId).toList();
    // Renumerar orden correlativo 0..N-1
    final reindexed = <TripStop>[];
    for (int i = 0; i < filtered.length; i++) {
      reindexed.add(filtered[i].copyWith(orderIndex: i));
    }

    return copyWith(
      stops: reindexed,
      updatedAt: DateTime.now(),
      calculatedRoute: null,
    );
  }

  /// Retorna una copia con las paradas reordenadas según los nuevos índices.
  TripItinerary reorderStops(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= stops.length) {
      throw RangeError.range(oldIndex, 0, stops.length - 1, 'oldIndex');
    }
    if (newIndex < 0 || newIndex > stops.length) {
      throw RangeError.range(newIndex, 0, stops.length, 'newIndex');
    }

    final list = List<TripStop>.from(stops);
    var targetIndex = newIndex;
    if (oldIndex < targetIndex) {
      targetIndex -= 1;
    }
    final item = list.removeAt(oldIndex);
    list.insert(targetIndex, item);

    // Renumerar orden correlativo
    final reindexed = <TripStop>[];
    for (int i = 0; i < list.length; i++) {
      reindexed.add(list[i].copyWith(orderIndex: i));
    }

    return copyWith(
      stops: reindexed,
      updatedAt: DateTime.now(),
      calculatedRoute: null,
    );
  }

  /// Marca una parada específica como visitada o no visitada.
  TripItinerary markStopVisited(String stopId, {bool visited = true}) {
    final updated = stops.map((s) {
      if (s.id == stopId) {
        return s.copyWith(isVisited: visited);
      }
      return s;
    }).toList();

    return copyWith(stops: updated, updatedAt: DateTime.now());
  }

  /// Retorna una copia inmutable del itinerario.
  TripItinerary copyWith({
    String? id,
    String? title,
    Destination? origin,
    Destination? destination,
    List<TripStop>? stops,
    DateTime? createdAt,
    DateTime? updatedAt,
    CalculatedRoute? calculatedRoute,
  }) {
    return TripItinerary(
      id: id ?? this.id,
      title: title ?? this.title,
      origin: origin ?? this.origin,
      destination: destination ?? this.destination,
      stops: stops ?? this.stops,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      calculatedRoute: calculatedRoute ?? this.calculatedRoute,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TripItinerary &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          origin == other.origin &&
          destination == other.destination &&
          _listEquals(stops, other.stops) &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    origin,
    destination,
    Object.hashAll(stops),
    createdAt,
    updatedAt,
  );

  static bool _listEquals(List<TripStop> a, List<TripStop> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  String toString() =>
      'TripItinerary(id: $id, "$title", stops: ${stops.length}, pending: $pendingStopsCount)';
}
