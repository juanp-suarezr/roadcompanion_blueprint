/// Registro inmutable de una sesión de seguimiento de ruta GPX en motocicleta.
///
/// Distingue explícitamente entre una sesión completada exitosamente y una sesión
/// interrumpida o detenida antes del destino.
class NavigationSession {
  /// Identificador único de la sesión.
  final String id;

  /// Identificador de la ruta GPX seguida.
  final String routeId;

  /// Nombre de la ruta GPX seguida.
  final String routeName;

  /// Momento de inicio del seguimiento.
  final DateTime startTime;

  /// Momento de finalización del seguimiento.
  final DateTime? endTime;

  /// Duración total activa de la sesión.
  final Duration duration;

  /// Distancia estimada recorrida a lo largo de la ruta en metros.
  final double distanceTraveledMeters;

  /// Distancia total geográfica de la ruta en metros.
  final double totalRouteDistanceMeters;

  /// Porcentaje de avance alcanzado [0.0, 100.0].
  final double progressPercentage;

  /// Cantidad de muestras GPS válidas recibidas y procesadas.
  final int validGpsSamplesCount;

  /// Precisión promedio de las lecturas GPS procesadas en metros.
  final double averageAccuracyMeters;

  /// Velocidad máxima registrada durante la sesión en km/h, si estuvo disponible.
  final double? maxSpeedKmh;

  /// Indica si la sesión se completó al alcanzar el destino (true) o si fue interrumpida (false).
  final bool isCompleted;

  const NavigationSession({
    required this.id,
    required this.routeId,
    required this.routeName,
    required this.startTime,
    this.endTime,
    required this.duration,
    required this.distanceTraveledMeters,
    required this.totalRouteDistanceMeters,
    required this.progressPercentage,
    required this.validGpsSamplesCount,
    required this.averageAccuracyMeters,
    this.maxSpeedKmh,
    required this.isCompleted,
  });

  /// Distancia recorrida en kilómetros.
  double get distanceTraveledKm => distanceTraveledMeters / 1000.0;

  Map<String, dynamic> toJson() => {
    'id': id,
    'routeId': routeId,
    'routeName': routeName,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
    'durationMs': duration.inMilliseconds,
    'distanceTraveledMeters': distanceTraveledMeters,
    'totalRouteDistanceMeters': totalRouteDistanceMeters,
    'progressPercentage': progressPercentage,
    'validGpsSamplesCount': validGpsSamplesCount,
    'averageAccuracyMeters': averageAccuracyMeters,
    'maxSpeedKmh': maxSpeedKmh,
    'isCompleted': isCompleted,
  };

  factory NavigationSession.fromJson(Map<String, dynamic> json) {
    return NavigationSession(
      id: json['id'] as String,
      routeId: json['routeId'] as String? ?? 'unknown',
      routeName: json['routeName'] as String? ?? 'Ruta GPX',
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: json['endTime'] != null
          ? DateTime.parse(json['endTime'] as String)
          : null,
      duration: Duration(
        milliseconds: (json['durationMs'] as num?)?.toInt() ?? 0,
      ),
      distanceTraveledMeters:
          (json['distanceTraveledMeters'] as num?)?.toDouble() ?? 0.0,
      totalRouteDistanceMeters:
          (json['totalRouteDistanceMeters'] as num?)?.toDouble() ?? 0.0,
      progressPercentage:
          (json['progressPercentage'] as num?)?.toDouble() ?? 0.0,
      validGpsSamplesCount:
          (json['validGpsSamplesCount'] as num?)?.toInt() ?? 0,
      averageAccuracyMeters:
          (json['averageAccuracyMeters'] as num?)?.toDouble() ?? 0.0,
      maxSpeedKmh: (json['maxSpeedKmh'] as num?)?.toDouble(),
      isCompleted: json['isCompleted'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NavigationSession &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'NavigationSession(id: $id, route: $routeName, progress: ${progressPercentage.toStringAsFixed(1)}%, completed: $isCompleted)';
}
