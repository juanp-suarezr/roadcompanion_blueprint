import '../../../../domain/entities/coordinates.dart';

/// Representa un destino o punto de interés seleccionado en el mapa cartográfico.
class Destination {
  /// Identificador único del lugar (ej. osm_id o hash).
  final String id;

  /// Nombre corto o principal del lugar (ej. "Nevado del Ruiz", "Catedral de Manizales").
  final String title;

  /// Dirección o descripción geográfica detallada (municipio, departamento, país).
  final String subtitle;

  /// Coordenada geográfica validada del destino.
  final Coordinates coordinates;

  /// Tipo o categoría del punto (ej. "amenity", "city", "tourism", "street").
  final String? category;

  const Destination({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.coordinates,
    this.category,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'latitude': coordinates.latitude,
    'longitude': coordinates.longitude,
    'category': category,
  };

  factory Destination.fromJson(Map<String, dynamic> json) {
    return Destination(
      id: json['id'] as String,
      title: json['title'] as String,
      subtitle: json['subtitle'] as String? ?? '',
      coordinates: Coordinates(
        (json['latitude'] as num).toDouble(),
        (json['longitude'] as num).toDouble(),
      ),
      category: json['category'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Destination &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Destination($title, coords: $coordinates)';
}
