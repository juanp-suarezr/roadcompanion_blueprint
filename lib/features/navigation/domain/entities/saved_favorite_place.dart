import '../../../../domain/entities/coordinates.dart';

/// Categorías para clasificación de lugares favoritos del motociclista.
enum FavoritePlaceCategory {
  home('Casa', 'home'),
  work('Trabajo', 'work'),
  family('Familia', 'family'),
  farm('Finca', 'farm'),
  viewpoint('Mirador', 'viewpoint'),
  gasStation('Gasolinera', 'gas_station'),
  custom('Personalizado', 'custom');

  final String label;
  final String key;
  const FavoritePlaceCategory(this.label, this.key);

  static FavoritePlaceCategory fromKey(String? key) {
    if (key == null) return FavoritePlaceCategory.custom;
    for (final c in FavoritePlaceCategory.values) {
      if (c.key == key || c.name.toLowerCase() == key.toLowerCase()) {
        return c;
      }
    }
    return FavoritePlaceCategory.custom;
  }
}

/// Representa un lugar o punto geográfico guardado localmente en favoritos.
///
/// La coordenada es la identidad soberana e inmutable del lugar.
/// La dirección, nombre de vereda o municipio son complementarios.
class SavedFavoritePlace {
  final String id;
  final String name;
  final Coordinates coordinates;
  final String? address;
  final FavoritePlaceCategory category;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? notes;

  const SavedFavoritePlace({
    required this.id,
    required this.name,
    required this.coordinates,
    this.address,
    this.category = FavoritePlaceCategory.custom,
    required this.createdAt,
    this.updatedAt,
    this.notes,
  });

  SavedFavoritePlace copyWith({
    String? id,
    String? name,
    Coordinates? coordinates,
    String? address,
    FavoritePlaceCategory? category,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? notes,
  }) {
    return SavedFavoritePlace(
      id: id ?? this.id,
      name: name ?? this.name,
      coordinates: coordinates ?? this.coordinates,
      address: address ?? this.address,
      category: category ?? this.category,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'latitude': coordinates.latitude,
    'longitude': coordinates.longitude,
    'address': address,
    'category': category.key,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
    'notes': notes,
  };

  factory SavedFavoritePlace.fromJson(Map<String, dynamic> json) {
    return SavedFavoritePlace(
      id: json['id'] as String,
      name: json['name'] as String,
      coordinates: Coordinates(
        (json['latitude'] as num).toDouble(),
        (json['longitude'] as num).toDouble(),
      ),
      address: json['address'] as String?,
      category: FavoritePlaceCategory.fromKey(json['category'] as String?),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
      notes: json['notes'] as String?,
    );
  }
}
