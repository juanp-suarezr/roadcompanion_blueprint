import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_companion/app/road_companion_app.dart';
import 'package:road_companion/app/state/app_settings_service.dart';
import 'package:road_companion/app/state/app_settings_state.dart';
import 'package:road_companion/features/home/presentation/home_screen.dart';
import 'package:road_companion/features/navigation/presentation/navigation_screen.dart';
import 'package:road_companion/features/placeholder/presentation/coming_soon_screen.dart';
import 'package:road_companion/features/settings/presentation/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppSettingsState settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'rc_theme_mode': 'system',
      'rc_moto_brand': 'Royal Enfield',
      'rc_moto_model': 'Meteor 350',
      'rc_moto_custom_name': 'StormBlue',
    });
    final prefs = await SharedPreferences.getInstance();
    final service = AppSettingsService(prefs);
    settings = AppSettingsState(service);
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(RoadCompanionApp(settings: settings));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'RoadCompanionApp se inicializa y muestra la pantalla principal',
    (WidgetTester tester) async {
      await pumpApp(tester);

      // Verificación de elementos clave de la identidad ESTELA
      expect(find.text('ESTELA'), findsWidgets);
      expect(find.text('NAVEGADOR DE RUTA COMPLEMENTARIO'), findsOneWidget);
      expect(find.text('LISTO PARA RODAR'), findsOneWidget);
      expect(find.text('Explorar navegación'), findsOneWidget);
      expect(find.text('Pantalla externa: '), findsOneWidget);
      expect(find.text('No conectada'), findsOneWidget);
      expect(find.text('Navegación'), findsOneWidget);
      expect(find.text('Mis viajes'), findsOneWidget);
      expect(find.text('Motocicleta'), findsOneWidget);
      expect(find.text('Ajustes'), findsOneWidget);
    },
  );

  testWidgets(
    'Navega a la pantalla de navegación asistida y renderiza componentes demo',
    (WidgetTester tester) async {
      await pumpApp(tester);

      // Tocar el botón principal "Explorar navegación"
      await tester.tap(find.text('Explorar navegación'));
      await tester.pumpAndSettle();

      // Verificación de pantalla de navegación
      expect(find.byType(NavigationScreen), findsOneWidget);
      expect(find.text('Navegación Asistida'), findsOneWidget);
      expect(find.text('DEMO'), findsOneWidget);
      expect(
        find.text('Esquema de calzada • No es mapa GPS real'),
        findsOneWidget,
      );
      expect(find.text('PROGRESO'), findsOneWidget);
      expect(find.text('Simular'), findsOneWidget);

      // Iniciar simulación y verificar que cambia a "Pausar"
      await tester.tap(find.text('Simular'));
      await tester.pump();
      expect(find.text('Pausar'), findsOneWidget);

      // Pausar simulación
      await tester.tap(find.text('Pausar'));
      await tester.pump();
      expect(find.text('Simular'), findsOneWidget);
    },
  );

  testWidgets(
    'Navega a Ajustes, cambia el tema y persiste el modo seleccionado',
    (WidgetTester tester) async {
      await pumpApp(tester);

      // Tocar el icono de ajustes en el encabezado
      await tester.tap(find.byTooltip('Ajustes de la aplicación'));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.text('Ajustes'), findsOneWidget);
      expect(find.text('APARIENCIA'), findsOneWidget);
      expect(find.text('MOTOCICLETA'), findsOneWidget);
      expect(find.text('DISPOSITIVOS'), findsOneWidget);
      expect(find.text('INFORMACIÓN'), findsOneWidget);

      // Cambiar a modo Oscuro
      await tester.tap(find.text('Oscuro'));
      await tester.pumpAndSettle();

      expect(settings.themeMode, equals(ThemeMode.dark));

      // Cambiar a modo Claro
      await tester.tap(find.text('Claro'));
      await tester.pumpAndSettle();

      expect(settings.themeMode, equals(ThemeMode.light));

      // Cambiar de vuelta a Sistema
      await tester.tap(find.text('Sistema'));
      await tester.pumpAndSettle();

      expect(settings.themeMode, equals(ThemeMode.system));
    },
  );

  testWidgets('Permite editar y guardar el perfil de la motocicleta', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);

    // Abrir Ajustes
    await tester.tap(find.byTooltip('Ajustes de la aplicación'));
    await tester.pumpAndSettle();

    // Localizar campos de texto
    final customNameField = find.widgetWithText(TextField, 'StormBlue');
    expect(customNameField, findsOneWidget);

    // Modificar el nombre personalizado
    await tester.enterText(customNameField, 'StormBlue Stellar');
    await tester.pump();

    // Scroll hasta el botón si fuese necesario y guardar perfil
    final saveButton = find.text('Guardar perfil de motocicleta');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pump();

    expect(settings.motorcycleCustomName, equals('StormBlue Stellar'));
    expect(find.text('Perfil de motocicleta actualizado.'), findsOneWidget);
  });

  testWidgets('Acceso a Mis viajes muestra pantalla informativa Próximamente', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);

    final misViajesFinder = find.text('Mis viajes');
    await tester.ensureVisible(misViajesFinder);
    await tester.tap(misViajesFinder);
    await tester.pumpAndSettle();

    expect(find.byType(ComingSoonScreen), findsOneWidget);
    expect(find.text('PRÓXIMAMENTE'), findsOneWidget);
    expect(find.text('Volver al inicio'), findsOneWidget);

    await tester.tap(find.text('Volver al inicio'));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
