import 'dart:math';

/// Representa una coordenada geográfica inmutable (latitud y longitud en WGS84).
class Coordinates {
  /// Latitud en grados decimales (-90.0 a 90.0).
  final double latitude;

  /// Longitud en grados decimales (-180.0 a 180.0).
  final double longitude;

  /// Crea una coordenada validando estrictamente que los valores sean finitos y
  /// se encuentren dentro del rango geodésico admisible.
  Coordinates(this.latitude, this.longitude) {
    if (!latitude.isFinite) {
      throw ArgumentError.value(
        latitude,
        'latitude',
        'La latitud debe ser un número finito.',
      );
    }
    if (!longitude.isFinite) {
      throw ArgumentError.value(
        longitude,
        'longitude',
        'La longitud debe ser un número finito.',
      );
    }
    if (latitude < -90.0 || latitude > 90.0) {
      throw ArgumentError.value(
        latitude,
        'latitude',
        'La latitud debe estar comprendida entre -90.0 y 90.0 grados.',
      );
    }
    if (longitude < -180.0 || longitude > 180.0) {
      throw ArgumentError.value(
        longitude,
        'longitude',
        'La longitud debe estar comprendida entre -180.0 y 180.0 grados.',
      );
    }
  }

  /// Calcula la distancia directa (ortodrómica / gran círculo) en metros
  /// hacia otra coordenada mediante la fórmula del semiverseno (Haversine).
  ///
  /// IMPORTANTE: Esta función calcula únicamente la distancia en línea recta
  /// (gran círculo) entre dos puntos. NO DEBE usarse para calcular la distancia
  /// restante de un viaje por carretera, la cual depende del trazado de la ruta.
  double distanceTo(Coordinates other) {
    const double earthRadiusMeters = 6371000.0;

    final double lat1Rad = latitude * (pi / 180.0);
    final double lat2Rad = other.latitude * (pi / 180.0);
    final double deltaLatRad = (other.latitude - latitude) * (pi / 180.0);
    final double deltaLonRad = (other.longitude - longitude) * (pi / 180.0);

    final double sinDeltaLat = sin(deltaLatRad / 2.0);
    final double sinDeltaLon = sin(deltaLonRad / 2.0);

    final double a = sinDeltaLat * sinDeltaLat +
        cos(lat1Rad) * cos(lat2Rad) * sinDeltaLon * sinDeltaLon;

    final double clampedA = a.clamp(0.0, 1.0);
    final double c = 2.0 * atan2(sqrt(clampedA), sqrt(1.0 - clampedA));

    return earthRadiusMeters * c;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Coordinates &&
          runtimeType == other.runtimeType &&
          latitude == other.latitude &&
          longitude == other.longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'Coordinates(lat: $latitude, lon: $longitude)';
}
