import 'package:flutter_test/flutter_test.dart';
import 'package:road_companion/domain/entities/coordinates.dart';
import 'package:road_companion/domain/entities/maneuver.dart';
import 'package:road_companion/domain/entities/maneuver_type.dart';
import 'package:road_companion/features/navigation/infrastructure/services/flutter_tts_voice_navigation_service.dart';

class MockTtsService extends FlutterTtsVoiceNavigationService {
  final List<String> spokenPrompts = [];

  MockTtsService() : super();

  @override
  bool get isAvailable => true;

  @override
  Future<void> speak(String text, {bool interrupt = false}) async {
    if (isMuted) return;
    spokenPrompts.add(text);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VoiceNavigationService - Anuncios y Deduplicación', () {
    late MockTtsService voiceService;
    late Maneuver testManeuver;

    setUp(() {
      voiceService = MockTtsService();
      testManeuver = Maneuver(
        instructionText: 'Gira a la derecha en Avenida 30 de Agosto',
        type: ManeuverType.right,
        location: Coordinates(4.8150, -75.6950),
        roadName: 'Avenida 30 de Agosto',
      );
    });

    test('Emite aviso de anticipación a ~450m y no lo duplica si se mantiene en el rango', () async {
      await voiceService.processManeuverGuidance(
        maneuverIndex: 1,
        maneuver: testManeuver,
        distanceToManeuverMeters: 450.0,
        currentSpeedKmh: 40.0,
      );

      expect(voiceService.spokenPrompts.length, equals(1));
      expect(voiceService.spokenPrompts.first, contains('En 450 metros, gira a la derecha en Avenida 30 de Agosto'));

      // Repetir llamada a 440m (mismo rango de anticipación)
      await voiceService.processManeuverGuidance(
        maneuverIndex: 1,
        maneuver: testManeuver,
        distanceToManeuverMeters: 440.0,
        currentSpeedKmh: 40.0,
      );

      // No debe repetirse
      expect(voiceService.spokenPrompts.length, equals(1));
    });

    test('Secuencia progresiva: Anticipación -> Preparación -> Inminente', () async {
      // 1. Anticipación
      await voiceService.processManeuverGuidance(
        maneuverIndex: 2,
        maneuver: testManeuver,
        distanceToManeuverMeters: 450.0,
        currentSpeedKmh: 40.0,
      );
      expect(voiceService.spokenPrompts.length, equals(1));

      // 2. Preparación a 180m
      await voiceService.processManeuverGuidance(
        maneuverIndex: 2,
        maneuver: testManeuver,
        distanceToManeuverMeters: 180.0,
        currentSpeedKmh: 40.0,
      );
      expect(voiceService.spokenPrompts.length, equals(2));
      expect(voiceService.spokenPrompts.last, contains('En 180 metros'));

      // 3. Inminente a 25m
      await voiceService.processManeuverGuidance(
        maneuverIndex: 2,
        maneuver: testManeuver,
        distanceToManeuverMeters: 25.0,
        currentSpeedKmh: 40.0,
      );
      expect(voiceService.spokenPrompts.length, equals(3));
      expect(voiceService.spokenPrompts.last, equals('Gira a la derecha en Avenida 30 de Agosto.'));
    });

    test('Modo silenciado (isMuted) bloquea todo anuncio de voz', () async {
      voiceService.isMuted = true;

      await voiceService.processManeuverGuidance(
        maneuverIndex: 3,
        maneuver: testManeuver,
        distanceToManeuverMeters: 20.0,
        currentSpeedKmh: 35.0,
      );

      expect(voiceService.spokenPrompts, isEmpty);
    });

    test('Anuncio de salida de ruta y llegada a destino', () async {
      await voiceService.announceOffRoute();
      expect(voiceService.spokenPrompts.length, equals(1));
      expect(voiceService.spokenPrompts.first, contains('Has salido de la ruta'));

      await voiceService.announceDestinationReached();
      expect(voiceService.spokenPrompts.length, equals(2));
      expect(voiceService.spokenPrompts.last, contains('Has llegado a tu destino'));
    });
  });
}
