import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/navigation/domain/services/navigation_source.dart';

/// Servicio de persistencia local para las preferencias de Road Companion.
///
/// Encapsula la interacción con [SharedPreferences] para guardar y restaurar
/// el modo de tema, el perfil de la motocicleta y la fuente de navegación seleccionada.
class AppSettingsService {
  static const String _keyThemeMode = 'rc_theme_mode';
  static const String _keyMotorcycleBrand = 'rc_moto_brand';
  static const String _keyMotorcycleModel = 'rc_moto_model';
  static const String _keyMotorcycleCustomName = 'rc_moto_custom_name';
  static const String _keySelectedNavigationSource = 'rc_selected_nav_source';

  final SharedPreferences? _prefs;

  const AppSettingsService([this._prefs]);

  /// Crea una instancia cargando las [SharedPreferences] reales del sistema.
  static Future<AppSettingsService> create() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return AppSettingsService(prefs);
    } catch (_) {
      // Fallback a modo en memoria tolerante ante fallos
      return const AppSettingsService(null);
    }
  }

  /// Carga el [ThemeMode] guardado; retorna [ThemeMode.system] por defecto.
  ThemeMode loadThemeMode() {
    final value = _prefs?.getString(_keyThemeMode);
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  /// Persiste el [ThemeMode] seleccionado.
  Future<void> saveThemeMode(ThemeMode mode) async {
    String modeString;
    switch (mode) {
      case ThemeMode.light:
        modeString = 'light';
        break;
      case ThemeMode.dark:
        modeString = 'dark';
        break;
      case ThemeMode.system:
        modeString = 'system';
        break;
    }
    await _prefs?.setString(_keyThemeMode, modeString);
  }

  /// Carga la marca de la motocicleta configurada.
  String loadMotorcycleBrand({String fallback = 'Royal Enfield'}) {
    return _prefs?.getString(_keyMotorcycleBrand) ?? fallback;
  }

  /// Carga el modelo de la motocicleta configurada.
  String loadMotorcycleModel({String fallback = 'Meteor 350'}) {
    return _prefs?.getString(_keyMotorcycleModel) ?? fallback;
  }

  /// Carga el nombre personalizado de la motocicleta.
  String loadMotorcycleCustomName({String fallback = 'StormBlue'}) {
    return _prefs?.getString(_keyMotorcycleCustomName) ?? fallback;
  }

  /// Persiste los datos del perfil de la motocicleta.
  Future<void> saveMotorcycleProfile({
    required String brand,
    required String model,
    required String customName,
  }) async {
    await _prefs?.setString(_keyMotorcycleBrand, brand);
    await _prefs?.setString(_keyMotorcycleModel, model);
    await _prefs?.setString(_keyMotorcycleCustomName, customName);
  }

  /// Carga la fuente de navegación seleccionada para el viaje (por defecto: Waze).
  SelectedNavigationSourceType loadSelectedNavigationSource() {
    final raw = _prefs?.getString(_keySelectedNavigationSource);
    if (raw == null) return SelectedNavigationSourceType.waze;
    return SelectedNavigationSourceType.fromStorageKey(raw);
  }

  /// Persiste la fuente de navegación seleccionada (`internal`, `waze`, `googleMaps`).
  Future<void> saveSelectedNavigationSource(
    SelectedNavigationSourceType source,
  ) async {
    await _prefs?.setString(_keySelectedNavigationSource, source.name);
  }
}
