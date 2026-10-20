/// Metadatos serializables de una ruta GPX guardada de forma persistente.
///
/// Permite listar y consultar las rutas almacenadas en el dispositivo sin
/// tener que cargar ni reanalizar la geometría XML completa en memoria.
class SavedRouteMetadata {
  /// Identificador único persistente de la ruta guardada.
  final String id;

  /// Nombre descriptivo del recorrido.
  final String name;

  /// Nombre original del archivo (ej. 'ruta_nevado.gpx').
  final String fileName;

  /// Distancia geográfica acumulada en metros.
  final double totalDistanceMeters;

  /// Cantidad de puntos geográficos en el trazado.
  final int totalPoints;

  /// Cantidad de segmentos discontinuos en la ruta.
  final int segmentCount;

  /// Elevación mínima registrada en metros, si existe.
  final double? minElevation;

  /// Elevación máxima registrada en metros, si existe.
  final double? maxElevation;

  /// Fecha y hora en la que se importó y guardó la ruta.
  final DateTime importedAt;

  const SavedRouteMetadata({
    required this.id,
    required this.name,
    required this.fileName,
    required this.totalDistanceMeters,
    required this.totalPoints,
    required this.segmentCount,
    this.minElevation,
    this.maxElevation,
    required this.importedAt,
  });

  /// Distancia en kilómetros para visualización.
  double get totalDistanceKm => totalDistanceMeters / 1000.0;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'fileName': fileName,
    'totalDistanceMeters': totalDistanceMeters,
    'totalPoints': totalPoints,
    'segmentCount': segmentCount,
    'minElevation': minElevation,
    'maxElevation': maxElevation,
    'importedAt': importedAt.toIso8601String(),
  };

  factory SavedRouteMetadata.fromJson(Map<String, dynamic> json) {
    return SavedRouteMetadata(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Ruta GPX',
      fileName: json['fileName'] as String? ?? 'ruta.gpx',
      totalDistanceMeters:
          (json['totalDistanceMeters'] as num?)?.toDouble() ?? 0.0,
      totalPoints: (json['totalPoints'] as num?)?.toInt() ?? 0,
      segmentCount: (json['segmentCount'] as num?)?.toInt() ?? 1,
      minElevation: (json['minElevation'] as num?)?.toDouble(),
      maxElevation: (json['maxElevation'] as num?)?.toDouble(),
      importedAt: json['importedAt'] != null
          ? DateTime.parse(json['importedAt'] as String)
          : DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SavedRouteMetadata &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'SavedRouteMetadata(id: $id, name: $name, km: ${totalDistanceKm.toStringAsFixed(1)})';
}
