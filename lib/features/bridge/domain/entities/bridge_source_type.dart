/// Identifica la fuente de la instrucción de navegación recibida por ESTELA Bridge.
enum BridgeSourceType {
  /// Instrucción interceptada desde la aplicación Google Maps.
  googleMaps(
    packageName: 'com.google.android.apps.maps',
    displayName: 'Google Maps',
  ),

  /// Instrucción interceptada desde la aplicación Waze.
  waze(packageName: 'com.waze', displayName: 'Waze'),

  /// Fuente de laboratorio o simulación controlada (para pruebas sin requerir conducción real).
  simulation(
    packageName: 'internal.simulation',
    displayName: 'Simulador Bridge',
  ),

  /// Fuente externa no identificada o genérica.
  unknown(packageName: '', displayName: 'Fuente Desconocida');

  final String packageName;
  final String displayName;

  const BridgeSourceType({
    required this.packageName,
    required this.displayName,
  });

  /// Determina la fuente a partir del nombre del paquete de la aplicación Android.
  static BridgeSourceType fromPackageName(String? packageName) {
    if (packageName == null) return BridgeSourceType.unknown;
    final trimmed = packageName.trim().toLowerCase();
    for (final source in BridgeSourceType.values) {
      if (source.packageName.isNotEmpty &&
          trimmed.contains(source.packageName.toLowerCase())) {
        return source;
      }
    }
    return BridgeSourceType.unknown;
  }
}
