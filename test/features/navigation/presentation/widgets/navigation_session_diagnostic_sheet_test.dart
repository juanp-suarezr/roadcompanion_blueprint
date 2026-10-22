import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_companion/domain/entities/coordinates.dart';
import 'package:road_companion/domain/entities/maneuver.dart';
import 'package:road_companion/domain/entities/maneuver_type.dart';
import 'package:road_companion/domain/entities/route_plan.dart';
import 'package:road_companion/features/navigation/domain/entities/calculated_route.dart';
import 'package:road_companion/features/navigation/domain/entities/gps_position.dart';
import 'package:road_companion/features/navigation/domain/services/navigation_maneuver_engine.dart';
import 'package:road_companion/features/navigation/infrastructure/parsers/gpx_parser.dart';
import 'package:road_companion/features/navigation/infrastructure/services/flutter_tts_voice_navigation_service.dart';
import 'package:road_companion/features/navigation/presentation/state/gpx_route_tracker.dart';
import 'package:road_companion/features/navigation/presentation/widgets/navigation_session_diagnostic_sheet.dart';

import '../state/gpx_route_tracker_test.dart';

class MockVoiceForSheetTest extends FlutterTtsVoiceNavigationService {
  String? _spoken;

  @override
  String? get lastSpokenText => _spoken;

  @override
  bool get isAvailable => true;

  @override
  Future<void> speak(String text, {bool interrupt = false}) async {
    _spoken = text;
  }
}

void main() {
  testWidgets(
    'NavigationSessionDiagnosticSheet renderiza todas las métricas de telemetría y alerta de obsolescencia',
    (tester) async {
      final fakeLocationService = FakeLocationService();
      DateTime simTime = DateTime(2026, 10, 22, 11, 0, 0);

      const gpxData = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="RoadCompanion">
  <trk><trkseg>
    <trkpt lat="5.0000" lon="-75.0000"><ele>1000.0</ele></trkpt>
    <trkpt lat="5.0050" lon="-75.0000"><ele>1020.0</ele></trkpt>
  </trkseg></trk>
</gpx>''';

      final route = const GpxParser().parse(gpxData);

      final tracker = GpxRouteTracker(
        route: route,
        locationService: fakeLocationService,
        clock: () => simTime,
      );

      final maneuverEngine = NavigationManeuverEngine();
      final calcRoute = CalculatedRoute(
        routePlan: RoutePlan(
          origin: route.allCoordinates.first,
          destination: route.allCoordinates.last,
          geometry: route.allCoordinates,
          totalDistanceMeters: route.totalGeographicDistanceMeters,
          estimatedDuration: const Duration(minutes: 5),
          maneuvers: [
            Maneuver(
              instructionText: 'Gira a la izquierda en Calle 10',
              type: ManeuverType.left,
              location: route.allCoordinates.last,
              distanceMeters: 500.0,
            ),
          ],
        ),
        summary: 'Ruta de prueba para diagnóstico',
      );
      maneuverEngine.setRoute(calcRoute);

      final voiceService = MockVoiceForSheetTest();
      await voiceService.speak('Gira a la izquierda en 500 metros.');

      await tracker.startTracking();

      // 1. Emitir posición válida
      final pos = GpsPosition(
        coordinates: Coordinates(5.0000, -75.0000),
        accuracyMeters: 8.0,
        speedMps: 10.0,
        timestamp: simTime,
      );
      fakeLocationService.emitPosition(pos);
      await tester.pump();

      maneuverEngine.resolveStep(
        currentCoordinates: pos.coordinates,
        progress: tracker.currentProgress,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NavigationSessionDiagnosticSheet(
              tracker: tracker,
              maneuverEngine: maneuverEngine,
              voiceService: voiceService,
            ),
          ),
        ),
      );

      // Verificaciones:
      // 1. Título y badges
      expect(find.text('Diagnóstico de Sesión GPS en Vivo'), findsOneWidget);
      expect(find.text('GPS FÍSICO REAL'), findsOneWidget);

      // 2. Coordenadas y precisión
      expect(find.textContaining('5.000000, -75.000000'), findsOneWidget);
      expect(find.textContaining('±8.0 m'), findsOneWidget);

      // 3. Posiciones recibidas
      expect(find.textContaining('1 (1 válidas)'), findsOneWidget);

      // 4. Maniobra y voz
      expect(find.textContaining('Calle 10'), findsOneWidget);
      expect(
        find.textContaining('Gira a la izquierda en 500 metros.'),
        findsOneWidget,
      );

      // 5. Botón de copiado
      expect(
        find.text('Copiar diagnóstico de sesión completo'),
        findsOneWidget,
      );

      // Simular que transcurren 15 segundos sin recibir coordenadas para verificar aviso de obsolescencia
      simTime = simTime.add(const Duration(seconds: 15));
      tracker.notifyListeners();
      await tester.pump();

      expect(
        find.textContaining('Señal GPS detenida o estancada'),
        findsOneWidget,
      );

      tracker.dispose();
    },
  );
}
