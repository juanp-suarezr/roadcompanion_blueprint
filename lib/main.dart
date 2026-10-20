import 'package:flutter/material.dart';

import 'app/road_companion_app.dart';
import 'app/state/app_settings_service.dart';
import 'app/state/app_settings_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicialización del servicio de persistencia y estado global de ajustes
  final settingsService = await AppSettingsService.create();
  final settingsState = AppSettingsState(settingsService);

  runApp(RoadCompanionApp(settings: settingsState));
}
