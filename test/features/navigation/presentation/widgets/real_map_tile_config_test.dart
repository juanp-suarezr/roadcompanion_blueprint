import 'package:flutter_test/flutter_test.dart';
import 'package:road_companion/features/navigation/presentation/widgets/real_map_tile_config.dart';

void main() {
  group('RealMapTileConfig - Configuración y resolución de teselas cartográficas', () {
    test('1. Con clave CARTO válida en modo oscuro resuelve CARTO Dark Matter con autenticación', () {
      const config = RealMapTileConfig(
        provider: MapTileProvider.auto,
        customCartoApiKey: 'secret_carto_key_123',
        isDark: true,
      );

      expect(config.hasValidCartoKey, isTrue);
      expect(config.shouldUseCarto, isTrue);
      expect(config.hasConfigurationError, isFalse);
      expect(
        config.tileUrl,
        equals(
          'https://{s}.basemaps.cartocdn.com/rastertiles/dark_all/{z}/{x}/{y}.png?api_key=secret_carto_key_123',
        ),
      );
      expect(config.subdomains, equals(['a', 'b', 'c', 'd']));
      expect(config.attributionText, equals('© OpenStreetMap, © CARTO'));
      expect(config.darkFallbackNotice, isNull);
    });

    test('2. Sin clave CARTO en modo oscuro conmuta a OpenStreetMap estándar sin marcas de agua', () {
      const config = RealMapTileConfig(
        provider: MapTileProvider.auto,
        customCartoApiKey: '',
        isDark: true,
      );

      expect(config.hasValidCartoKey, isFalse);
      expect(config.shouldUseCarto, isFalse);
      expect(config.hasConfigurationError, isFalse);
      expect(
        config.tileUrl,
        equals('https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
      );
      expect(config.subdomains, isEmpty);
      expect(config.attributionText, equals('© OpenStreetMap contributors'));
      expect(config.darkFallbackNotice, contains('OpenStreetMap estándar'));
    });

    test('3. En modo claro resuelve OpenStreetMap estándar independientemente de la clave', () {
      const configWithKey = RealMapTileConfig(
        provider: MapTileProvider.auto,
        customCartoApiKey: 'secret_carto_key_123',
        isDark: false,
      );

      expect(configWithKey.shouldUseCarto, isFalse);
      expect(
        configWithKey.tileUrl,
        equals('https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
      );
      expect(configWithKey.attributionText, equals('© OpenStreetMap contributors'));
      expect(configWithKey.darkFallbackNotice, isNull);
    });

    test('4. Forzar MapTileProvider.carto sin clave reporta hasConfigurationError', () {
      const config = RealMapTileConfig(
        provider: MapTileProvider.carto,
        customCartoApiKey: '',
        isDark: true,
      );

      expect(config.hasConfigurationError, isTrue);
      expect(config.hasValidCartoKey, isFalse);
    });

    test('5. Forzar MapTileProvider.openStreetMap usa OSM incluso si hay clave y modo oscuro', () {
      const config = RealMapTileConfig(
        provider: MapTileProvider.openStreetMap,
        customCartoApiKey: 'secret_carto_key_123',
        isDark: true,
      );

      expect(config.shouldUseCarto, isFalse);
      expect(
        config.tileUrl,
        equals('https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
      );
      expect(config.attributionText, equals('© OpenStreetMap contributors'));
      expect(config.darkFallbackNotice, isNull);
    });

    test('6. Seguridad: toString() no expone la clave API en texto ni registros', () {
      const config = RealMapTileConfig(
        provider: MapTileProvider.auto,
        customCartoApiKey: 'super_secret_token_never_log',
        isDark: true,
      );

      final stringRep = config.toString();
      expect(stringRep, isNot(contains('super_secret_token_never_log')));
      expect(stringRep, contains('hasValidKey: true'));
    });
  });
}
