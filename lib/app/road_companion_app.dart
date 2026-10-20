import 'package:flutter/material.dart';

import 'state/app_settings_state.dart';
import 'theme/app_theme.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/navigation/presentation/state/imported_route_state.dart';

/// Aplicación raíz de Road Companion.
///
/// Configura el tema dinámico (Sistema / Claro / Oscuro), el estado de rutas
/// importadas en memoria y monta la pantalla principal [HomeScreen].
class RoadCompanionApp extends StatefulWidget {
  final AppSettingsState settings;
  final ImportedRouteState? routeState;

  const RoadCompanionApp({super.key, required this.settings, this.routeState});

  @override
  State<RoadCompanionApp> createState() => _RoadCompanionAppState();
}

class _RoadCompanionAppState extends State<RoadCompanionApp> {
  late final ImportedRouteState _routeState;

  @override
  void initState() {
    super.initState();
    _routeState = widget.routeState ?? ImportedRouteState();
  }

  @override
  void dispose() {
    if (widget.routeState == null) {
      _routeState.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppSettingsScope(
      settings: widget.settings,
      child: ImportedRouteScope(
        routeState: _routeState,
        child: ListenableBuilder(
          listenable: widget.settings,
          builder: (context, _) {
            return MaterialApp(
              title: 'Road Companion',
              debugShowCheckedModeBanner: false,
              themeMode: widget.settings.themeMode,
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              home: const HomeScreen(),
            );
          },
        ),
      ),
    );
  }
}
