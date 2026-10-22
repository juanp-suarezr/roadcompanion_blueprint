import 'package:flutter/material.dart';

import '../../../app/state/app_settings_state.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/widgets/quick_action_card.dart';
import '../../../core/widgets/road_header.dart';
import '../../navigation/infrastructure/services/flutter_blue_plus_tripper_service.dart';
import '../../navigation/presentation/navigation_screen.dart';
import '../../navigation/presentation/screens/tripper_diagnostic_screen.dart';
import '../../placeholder/presentation/coming_soon_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../itinerary/presentation/screens/quick_navigation_screen.dart';
import '../../itinerary/presentation/screens/trip_planner_screen.dart';
import 'widgets/external_display_banner.dart';
import 'widgets/ready_to_ride_card.dart';

/// Pantalla principal de Road Companion.
///
/// Reemplaza la pantalla de contador predeterminada por un centro de mando
/// sobrio, accesible y diseñado para el motociclista contemporáneo.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _navigateTo(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsScope.of(context);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // 1. Encabezado principal con identidad de marca y acceso a Ajustes
            RoadHeader(
              onSettingsTap: () => _navigateTo(context, const SettingsScreen()),
            ),
            const SizedBox(height: 8.0),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 2. Tarjeta principal de estado y acción de navegación
                  ReadyToRideCard(
                    onExploreNavigation: () =>
                        _navigateTo(context, const NavigationScreen()),
                  ),
                  const SizedBox(height: 16.0),

                  // 3. Banner transparente de estado de pantalla externa
                  ExternalDisplayBanner(
                    onTap: () => _navigateTo(
                      context,
                      TripperDiagnosticScreen(
                        bleService: FlutterBluePlusTripperService(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24.0),

                  // 4. Sección de accesos rápidos
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'ACCESOS RÁPIDOS',
                        style: AppTypography.badgeLabel.copyWith(
                          color: Theme.of(context).colorScheme.secondary,
                          letterSpacing: 1.2,
                        ),
                      ),
                      Text(
                        settings.motorcycleCustomName,
                        style: TextStyle(
                          fontSize: 12.0,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12.0),

                  // Cuadrícula / Lista táctil de accesos rápidos
                  QuickActionCard(
                    icon: Icons.navigation_outlined,
                    title: 'Navegación',
                    subtitle: 'Demostración de ruta asistida y odometría',
                    onTap: () => _navigateTo(context, const NavigationScreen()),
                  ),
                  const SizedBox(height: 10.0),

                  QuickActionCard(
                    icon: Icons.near_me_rounded,
                    title: 'Ir ahora',
                    subtitle: 'Navegación rápida con Google Maps o Waze',
                    onTap: () =>
                        _navigateTo(context, const QuickNavigationScreen()),
                  ),
                  const SizedBox(height: 10.0),

                  QuickActionCard(
                    icon: Icons.alt_route_rounded,
                    title: 'Planificador de Viaje',
                    subtitle: 'Ruta multiparada y exportación a Maps / Waze',
                    onTap: () =>
                        _navigateTo(context, const TripPlannerScreen()),
                  ),
                  const SizedBox(height: 10.0),

                  QuickActionCard(
                    icon: Icons.bluetooth_searching_rounded,
                    title: 'Laboratorio Tripper',
                    subtitle: 'Conectar y escanear Tripper Pod BLE',
                    onTap: () => _navigateTo(
                      context,
                      TripperDiagnosticScreen(
                        bleService: FlutterBluePlusTripperService(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10.0),

                  QuickActionCard(
                    icon: Icons.map_outlined,
                    title: 'Mis viajes',
                    subtitle: 'Historial, bitácora y rutas completadas',
                    onTap: () => _navigateTo(
                      context,
                      const ComingSoonScreen(
                        title: 'Mis viajes',
                        description:
                            'Próximamente podrás registrar, guardar y revivir tus recorridos favoritos con métricas completas de ruta.',
                        icon: Icons.map_outlined,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10.0),

                  QuickActionCard(
                    icon: Icons.two_wheeler,
                    title: 'Motocicleta',
                    subtitle:
                        '${settings.motorcycleBrand} ${settings.motorcycleModel}',
                    onTap: () => _navigateTo(context, const SettingsScreen()),
                  ),
                  const SizedBox(height: 10.0),

                  QuickActionCard(
                    icon: Icons.settings_outlined,
                    title: 'Ajustes',
                    subtitle: 'Apariencia, tema y preferencias del sistema',
                    onTap: () => _navigateTo(context, const SettingsScreen()),
                  ),
                  const SizedBox(height: 24.0),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
