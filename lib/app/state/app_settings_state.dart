import 'package:flutter/material.dart';

import 'app_settings_service.dart';

/// Notificador de estado global para los ajustes reactivos de Road Companion.
///
/// Notifica cambios inmediatamente a [MaterialApp] para que la selección de tema
/// y datos de la motocicleta se reflejen en tiempo real sin reiniciar la aplicación.
class AppSettingsState extends ChangeNotifier {
  final AppSettingsService _service;

  late ThemeMode _themeMode;
  late String _motorcycleBrand;
  late String _motorcycleModel;
  late String _motorcycleCustomName;

  AppSettingsState(this._service) {
    _themeMode = _service.loadThemeMode();
    _motorcycleBrand = _service.loadMotorcycleBrand();
    _motorcycleModel = _service.loadMotorcycleModel();
    _motorcycleCustomName = _service.loadMotorcycleCustomName();
  }

  /// Modo de tema actual de la aplicación.
  ThemeMode get themeMode => _themeMode;

  /// Marca registrada de la motocicleta.
  String get motorcycleBrand => _motorcycleBrand;

  /// Modelo de la motocicleta.
  String get motorcycleModel => _motorcycleModel;

  /// Nombre personalizado o apodo de la motocicleta (ej. "StormBlue").
  String get motorcycleCustomName => _motorcycleCustomName;

  /// Actualiza el modo de tema y lo persiste de inmediato.
  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    _service.saveThemeMode(mode);
  }

  /// Actualiza y persiste el perfil de la motocicleta.
  void updateMotorcycleProfile({
    String? brand,
    String? model,
    String? customName,
  }) {
    final newBrand = brand?.trim() ?? _motorcycleBrand;
    final newModel = model?.trim() ?? _motorcycleModel;
    final newCustomName = customName?.trim() ?? _motorcycleCustomName;

    _motorcycleBrand = newBrand.isNotEmpty ? newBrand : 'Motocicleta';
    _motorcycleModel = newModel.isNotEmpty ? newModel : 'Personalizada';
    _motorcycleCustomName = newCustomName.isNotEmpty
        ? newCustomName
        : 'Road Companion';

    notifyListeners();
    _service.saveMotorcycleProfile(
      brand: _motorcycleBrand,
      model: _motorcycleModel,
      customName: _motorcycleCustomName,
    );
  }
}

/// Provider elemental basado en InheritedWidget para proveer [AppSettingsState]
/// a través del árbol de widgets de manera limpia y sin dependencias pesadas.
class AppSettingsScope extends InheritedNotifier<AppSettingsState> {
  const AppSettingsScope({
    super.key,
    required AppSettingsState settings,
    required super.child,
  }) : super(notifier: settings);

  /// Obtiene la instancia de [AppSettingsState] más cercana en el árbol.
  static AppSettingsState of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppSettingsScope>();
    assert(
      scope != null,
      'No se encontró ningún AppSettingsScope en el contexto actual.',
    );
    return scope!.notifier!;
  }

  /// Obtiene la instancia de [AppSettingsState] sin suscribirse a reconstrucciones.
  static AppSettingsState read(BuildContext context) {
    final element = context
        .getElementForInheritedWidgetOfExactType<AppSettingsScope>();
    final scope = element?.widget as AppSettingsScope?;
    assert(
      scope != null,
      'No se encontró ningún AppSettingsScope en el contexto actual.',
    );
    return scope!.notifier!;
  }
}
