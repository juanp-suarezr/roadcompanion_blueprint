import '../../../../domain/entities/coordinates.dart';
import 'trip_stop_type.dart';

const Object _sentinel = Object();

/// Representa una parada intermedia inmutable dentro del itinerario de viaje de REstelar.
class TripStop {
  /// Identificador único y determinista de la parada.
  final String id;

  /// Nombre descriptivo o rótulo de la parada (ej. "Gasolinera Terpel Alto de Patios").
  final String name;

  /// Coordenada geográfica exacta de la parada.
  final Coordinates coordinates;

  /// Tipología de la parada.
  final TripStopType type;

  /// Posición secuencial de la parada dentro del itinerario (inicia en 0).
  final int orderIndex;

  /// Tiempo estimado de permanencia en la parada (opcional).
  final Duration? plannedDuration;

  /// Indica si el motociclista ya visitó o superó esta parada durante el viaje.
  final bool isVisited;

  /// Comentarios o indicaciones personales del usuario para esta parada.
  final String? notes;

  TripStop({
    required this.id,
    required this.name,
    required this.coordinates,
    this.type = TripStopType.custom,
    required this.orderIndex,
    this.plannedDuration,
    this.isVisited = false,
    this.notes,
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(
        id,
        'id',
        'El identificador de la parada no puede estar vacío.',
      );
    }
    if (name.trim().isEmpty) {
      throw ArgumentError.value(
        name,
        'name',
        'El nombre de la parada no puede estar vacío.',
      );
    }
    if (orderIndex < 0) {
      throw ArgumentError.value(
        orderIndex,
        'orderIndex',
        'El índice de orden debe ser mayor o igual a 0.',
      );
    }
  }

  /// Retorna una copia inmutable con los campos modificados.
  TripStop copyWith({
    String? id,
    String? name,
    Coordinates? coordinates,
    TripStopType? type,
    int? orderIndex,
    Object? plannedDuration = _sentinel,
    bool? isVisited,
    Object? notes = _sentinel,
  }) {
    return TripStop(
      id: id ?? this.id,
      name: name ?? this.name,
      coordinates: coordinates ?? this.coordinates,
      type: type ?? this.type,
      orderIndex: orderIndex ?? this.orderIndex,
      plannedDuration: identical(plannedDuration, _sentinel)
          ? this.plannedDuration
          : plannedDuration as Duration?,
      isVisited: isVisited ?? this.isVisited,
      notes: identical(notes, _sentinel) ? this.notes : notes as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TripStop &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          coordinates == other.coordinates &&
          type == other.type &&
          orderIndex == other.orderIndex &&
          plannedDuration == other.plannedDuration &&
          isVisited == other.isVisited &&
          notes == other.notes;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    coordinates,
    type,
    orderIndex,
    plannedDuration,
    isVisited,
    notes,
  );

  @override
  String toString() =>
      'TripStop(id: $id, name: "$name", order: $orderIndex, visited: $isVisited, type: ${type.name})';
}
