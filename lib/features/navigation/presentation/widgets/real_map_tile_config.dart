/// Enumeración de proveedores de teselas cartográficas admitidos.
enum MapTileProvider {
  /// Selecciona automáticamente según la disponibilidad de clave CARTO y el modo visual.
  /// Si está en modo oscuro y cuenta con CARTO_API_KEY, utiliza CARTO Dark Matter.
  /// Si no hay clave, utiliza OpenStreetMap estándar (estilo claro, sin marcas de agua).
  auto,

  /// Fuerza el uso de OpenStreetMap estándar (gratuito, sin clave).
  openStreetMap,

  /// Fuerza el uso de CARTO Basemaps (requiere clave API obligatoria).
  carto,
}

/// Configuración y resolución de teselas cartográficas para [RealMapWidget].
///
/// Gestiona la inyección segura de credenciales de CARTO mediante `--dart-define=CARTO_API_KEY=tu_clave`,
/// evitando dejar URLs raster de CARTO sin autenticar (lo cual produce marcas de agua "API KEY REQUIRED").
/// Cuando no hay clave disponible, conmuta limpiamente a las teselas oficiales de OpenStreetMap.
class RealMapTileConfig {
  /// Clave API inyectada en tiempo de compilación.
  static const String compileTimeCartoApiKey = String.fromEnvironment(
    'CARTO_API_KEY',
    defaultValue: '',
  );

  final MapTileProvider provider;
  final String? customCartoApiKey;
  final bool isDark;

  const RealMapTileConfig({
    this.provider = MapTileProvider.auto,
    this.customCartoApiKey,
    this.isDark = false,
  });

  /// Clave de API de CARTO efectiva (parámetro directo o variable de entorno de compilación).
  ///
  /// IMPORTANTE: Nunca imprimir esta clave en logs.
  String get effectiveCartoApiKey {
    final key = customCartoApiKey ?? compileTimeCartoApiKey;
    return key.trim();
  }

  /// Indica si existe una clave de CARTO no vacía disponible.
  bool get hasValidCartoKey => effectiveCartoApiKey.isNotEmpty;

  /// Indica si se configuró un estado erróneo (se forzó CARTO sin proveer clave).
  bool get hasConfigurationError {
    return provider == MapTileProvider.carto && !hasValidCartoKey;
  }

  /// Determina si deben servirse teselas oscuras de CARTO.
  bool get shouldUseCarto {
    if (provider == MapTileProvider.openStreetMap) return false;
    if (provider == MapTileProvider.carto) return hasValidCartoKey;
    // En modo auto, solo se usa CARTO si la interfaz es oscura Y existe una clave válida.
    return isDark && hasValidCartoKey;
  }

  /// URL de la plantilla de teselas cartográficas.
  String get tileUrl {
    if (shouldUseCarto) {
      final key = effectiveCartoApiKey;
      return 'https://{s}.basemaps.cartocdn.com/rastertiles/dark_all/{z}/{x}/{y}.png?api_key=$key';
    }
    // Alternativa estándar sin marcas de agua: OpenStreetMap
    return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  }

  /// Lista de subdominios requeridos por el proveedor de teselas.
  List<String> get subdomains {
    return shouldUseCarto ? const ['a', 'b', 'c', 'd'] : const <String>[];
  }

  /// Atribución requerida según el proveedor seleccionado.
  String get attributionText {
    return shouldUseCarto
        ? '© OpenStreetMap, © CARTO'
        : '© OpenStreetMap contributors';
  }

  /// Aviso explicativo si se está en modo oscuro pero se utiliza OSM por ausencia de clave CARTO.
  String? get darkFallbackNotice {
    if (provider == MapTileProvider.auto && isDark && !hasValidCartoKey) {
      return 'Modo oscuro: usando OpenStreetMap estándar (sin clave CARTO)';
    }
    return null;
  }

  @override
  String toString() {
    // Protección de seguridad: NO exponer la clave en la representación en cadena.
    return 'RealMapTileConfig(provider: $provider, isDark: $isDark, hasValidKey: $hasValidCartoKey)';
  }
}
