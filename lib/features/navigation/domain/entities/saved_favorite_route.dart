import '../../../../domain/entities/coordinates.dart';

/// Representa una ruta favorita guardada localmente por el motociclista en la memoria inteligente.
///
/// Conserva el punto de origen, destino, coordenadas, distancia total, duración estimada,
/// fecha de guardado, notas personalizadas y preferencias de tránsito.
class SavedFavoriteRoute {
  final String id;
  final String title;
  final Coordinates origin;
  final String originTitle;
  final Coordinates destination;
  final String destinationTitle;
  final DateTime savedAt;
  final double distanceKm;
  final Duration estimatedDuration;
  final String? notes;
  final Map<String, dynamic> preferences;

  const SavedFavoriteRoute({
    required this.id,
    required this.title,
    required this.origin,
    required this.originTitle,
    required this.destination,
    required this.destinationTitle,
    required this.savedAt,
    required this.distanceKm,
    required this.estimatedDuration,
    this.notes,
    this.preferences = const {},
  });

  String get formattedDuration {
    final hours = estimatedDuration.inHours;
    final minutes = estimatedDuration.inMinutes.remainder(60);
    if (hours > 0) {
      return '$hours h ${minutes.toString().padLeft(2, '0')} min';
    }
    return '$minutes min';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'origin': {'latitude': origin.latitude, 'longitude': origin.longitude},
    'originTitle': originTitle,
    'destination': {
      'latitude': destination.latitude,
      'longitude': destination.longitude,
    },
    'destinationTitle': destinationTitle,
    'savedAt': savedAt.toIso8601String(),
    'distanceKm': distanceKm,
    'estimatedDurationSeconds': estimatedDuration.inSeconds,
    'notes': notes,
    'preferences': preferences,
  };

  factory SavedFavoriteRoute.fromJson(Map<String, dynamic> json) {
    final originMap = json['origin'] as Map<String, dynamic>;
    final destMap = json['destination'] as Map<String, dynamic>;

    return SavedFavoriteRoute(
      id: json['id'] as String,
      title: json['title'] as String,
      origin: Coordinates(
        (originMap['latitude'] as num).toDouble(),
        (originMap['longitude'] as num).toDouble(),
      ),
      originTitle: json['originTitle'] as String? ?? 'Origen',
      destination: Coordinates(
        (destMap['latitude'] as num).toDouble(),
        (destMap['longitude'] as num).toDouble(),
      ),
      destinationTitle: json['destinationTitle'] as String? ?? 'Destino',
      savedAt:
          DateTime.tryParse(json['savedAt'] as String? ?? '') ?? DateTime.now(),
      distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0.0,
      estimatedDuration: Duration(
        seconds: (json['estimatedDurationSeconds'] as num?)?.toInt() ?? 0,
      ),
      notes: json['notes'] as String?,
      preferences: json['preferences'] as Map<String, dynamic>? ?? const {},
    );
  }

  SavedFavoriteRoute copyWith({
    String? title,
    String? notes,
    Map<String, dynamic>? preferences,
  }) {
    return SavedFavoriteRoute(
      id: id,
      title: title ?? this.title,
      origin: origin,
      originTitle: originTitle,
      destination: destination,
      destinationTitle: destinationTitle,
      savedAt: savedAt,
      distanceKm: distanceKm,
      estimatedDuration: estimatedDuration,
      notes: notes ?? this.notes,
      preferences: preferences ?? this.preferences,
    );
  }
}
