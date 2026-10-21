import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_companion/app/road_companion_app.dart';
import 'package:road_companion/app/state/app_settings_service.dart';
import 'package:road_companion/app/state/app_settings_state.dart';
import 'package:road_companion/features/navigation/infrastructure/services/gpx_file_picker.dart';
import 'package:road_companion/features/navigation/infrastructure/services/gpx_import_service.dart';
import 'package:road_companion/features/navigation/presentation/navigation_screen.dart';
import 'package:road_companion/features/navigation/presentation/state/imported_route_state.dart';
import 'package:road_companion/features/navigation/presentation/widgets/gpx_route_card.dart';
import 'package:road_companion/features/navigation/presentation/widgets/gpx_track_view.dart';
import 'package:road_companion/features/navigation/presentation/widgets/real_map_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake de GpxFilePicker para pruebas de interfaz controladas sin abrir selectores del sistema operativo.
class FakeGpxFilePicker implements GpxFilePicker {
  GpxFileResult? nextResult;
  bool shouldThrow = false;

  @override
  Future<GpxFileResult?> pickGpxFile() async {
    if (shouldThrow) {
      throw Exception('Simulación de fallo del sistema de archivos');
    }
    return nextResult;
  }
}

void main() {
  late AppSettingsState settings;
  late FakeGpxFilePicker fakePicker;
  late GpxImportService importService;
  late ImportedRouteState routeState;

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

    fakePicker = FakeGpxFilePicker();
    importService = GpxImportService(filePicker: fakePicker);
    routeState = ImportedRouteState(importService: importService);
  });

  Future<void> pumpNavigationApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      RoadCompanionApp(settings: settings, routeState: routeState),
    );
    await tester.pumpAndSettle();

    // Navegar a NavigationScreen desde HomeScreen
    await tester.tap(find.text('Explorar navegación'));
    await tester.pumpAndSettle();
  }

  group('NavigationScreen - Flujo de importación GPX', () {
    testWidgets(
      'Muestra acción de importar GPX y badge DEMO en estado inicial',
      (WidgetTester tester) async {
        await pumpNavigationApp(tester);

        expect(find.byType(NavigationScreen), findsOneWidget);
        expect(find.text('DEMO'), findsOneWidget);
        expect(find.text('Importar ruta GPX'), findsOneWidget);
        expect(find.byIcon(Icons.file_open_outlined), findsOneWidget);
        expect(find.byType(GpxRouteCard), findsNothing);
        expect(find.byType(GpxTrackView), findsNothing);
      },
    );

    testWidgets(
      'Importa exitosamente una ruta GPX y muestra métricas y trazado',
      (WidgetTester tester) async {
        const validGpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Test">
  <metadata><name>Ruta Cordillera Central</name></metadata>
  <trk>
    <trkseg>
      <trkpt lat="4.8133" lon="-75.6961"><ele>1411.0</ele></trkpt>
      <trkpt lat="4.7000" lon="-75.6500"><ele>1600.0</ele></trkpt>
      <trkpt lat="4.5339" lon="-75.6811"><ele>1550.0</ele></trkpt>
    </trkseg>
  </trk>
</gpx>''';

        fakePicker.nextResult = const GpxFileResult(
          fileName: 'cordillera.gpx',
          content: validGpx,
          sizeBytes: 400,
        );

        await pumpNavigationApp(tester);

        // Tocar el botón "Importar ruta GPX"
        await tester.tap(find.text('Importar ruta GPX'));
        await tester.pumpAndSettle();

        // Verificación de actualización del estado visual
        expect(find.byType(GpxRouteCard), findsOneWidget);
        expect(find.byType(GpxTrackView), findsOneWidget);
        expect(find.text('Ruta Cordillera Central'), findsOneWidget);
        expect(find.text('GPX IMPORTADO'), findsOneWidget);
        expect(find.text('GPX'), findsOneWidget); // Badge en AppBar
        expect(find.text('3'), findsOneWidget); // 3 puntos
        expect(
          find.text('Trazado GPX • Puntos reales sin mapa base'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Maneja la cancelación del selector de archivos sin alterar el estado',
      (WidgetTester tester) async {
        fakePicker.nextResult =
            null; // Simula cancelación por parte del usuario

        await pumpNavigationApp(tester);

        await tester.tap(find.text('Importar ruta GPX'));
        await tester.pumpAndSettle();

        // Se muestra SnackBar de cancelación
        expect(find.text('Selección de archivo cancelada.'), findsOneWidget);

        // Permanece en modo de mapa real sin alterar el estado
        expect(find.text('DEMO'), findsOneWidget);
        expect(find.byType(RealMapWidget), findsOneWidget);
        expect(find.byType(GpxRouteCard), findsNothing);
      },
    );

    testWidgets(
      'Muestra tarjeta de error ante un archivo GPX con contenido inválido',
      (WidgetTester tester) async {
        fakePicker.nextResult = const GpxFileResult(
          fileName: 'roto.gpx',
          content:
              '<gpx><trk><trkseg><trkpt lat="invalido" lon="-75.0" /></trkseg></trk></gpx>',
          sizeBytes: 100,
        );

        await pumpNavigationApp(tester);

        await tester.tap(find.text('Importar ruta GPX'));
        await tester.pumpAndSettle();

        // Debe mostrar la tarjeta de error
        expect(find.text('Error al importar archivo GPX'), findsOneWidget);
        expect(find.text('Reintentar importación'), findsOneWidget);
        expect(find.byType(GpxRouteCard), findsNothing);
      },
    );

    testWidgets(
      'Permite retirar la ruta cargada y regresar a la demostración interactiva',
      (WidgetTester tester) async {
        const validGpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1">
  <metadata><name>Ruta Retirable</name></metadata>
  <trk>
    <trkseg>
      <trkpt lat="5.0" lon="-75.0" />
      <trkpt lat="5.1" lon="-75.1" />
    </trkseg>
  </trk>
</gpx>''';

        fakePicker.nextResult = const GpxFileResult(
          fileName: 'retirable.gpx',
          content: validGpx,
          sizeBytes: 250,
        );

        await pumpNavigationApp(tester);

        // Cargar ruta
        await tester.tap(find.text('Importar ruta GPX'));
        await tester.pumpAndSettle();

        expect(find.text('Ruta Retirable'), findsOneWidget);

        // Tocar el botón "Volver a demo"
        await tester.tap(find.text('Volver a demo'));
        await tester.pumpAndSettle();

        // Regresa a modo demo
        expect(find.byType(GpxRouteCard), findsNothing);
        expect(find.byType(GpxTrackView), findsNothing);
        expect(find.text('DEMO'), findsOneWidget);
        expect(find.text('Simular'), findsOneWidget);
        expect(
          find.text(
            'Simulación activa: Honda → La Dorada → Norcasia (54 km). Datos calculados con el motor de dominio puro.',
          ),
          findsOneWidget,
        );
      },
    );
  });
}
