import 'package:road_companion/road_companion.dart';
import 'package:test/test.dart';

void main() {
  group('BridgeSourceType - Identificación de proveedor', () {
    test('mapea paquetes oficiales conocidos a su enum correspondiente', () {
      expect(
        BridgeSourceType.fromPackageName('com.google.android.apps.maps'),
        equals(BridgeSourceType.googleMaps),
      );
      expect(
        BridgeSourceType.fromPackageName('COM.GOOGLE.ANDROID.APPS.MAPS'),
        equals(BridgeSourceType.googleMaps),
      );
      expect(
        BridgeSourceType.fromPackageName('com.waze'),
        equals(BridgeSourceType.waze),
      );
      expect(
        BridgeSourceType.fromPackageName('internal.simulation'),
        equals(BridgeSourceType.simulation),
      );
    });

    test('retorna unknown para paquetes ajenos, nulos o vacíos', () {
      expect(
        BridgeSourceType.fromPackageName(null),
        equals(BridgeSourceType.unknown),
      );
      expect(
        BridgeSourceType.fromPackageName(''),
        equals(BridgeSourceType.unknown),
      );
      expect(
        BridgeSourceType.fromPackageName('com.spotify.music'),
        equals(BridgeSourceType.unknown),
      );
    });
  });

  group('BridgeNavigationInstruction - Modelo Inmutable y Estados', () {
    final now = DateTime(2026, 10, 22, 14, 0, 0);

    test('construye instrucción reconocida con métricas válidas', () {
      final instruction = BridgeNavigationInstruction(
        source: BridgeSourceType.googleMaps,
        maneuverType: ManeuverType.right,
        distanceMeters: 400,
        rawDistanceText: '400 m',
        rawText: 'En 400 m, gira a la derecha en Calle 26',
        rawTitle: 'Gira a la derecha',
        destinationStreet: 'Calle 26',
        receivedAt: now,
        status: BridgeInstructionStatus.recognized,
      );

      expect(instruction.isRecognized, isTrue);
      expect(instruction.isIncomplete, isFalse);
      expect(instruction.isUnrecognized, isFalse);
      expect(instruction.isStale, isFalse);
      expect(instruction.distanceMeters, equals(400));
      expect(instruction.destinationStreet, equals('Calle 26'));
      expect(instruction.source, equals(BridgeSourceType.googleMaps));
    });

    test('permite instrucción sin distancia sin inventarla', () {
      final instruction = BridgeNavigationInstruction(
        source: BridgeSourceType.waze,
        maneuverType: ManeuverType.left,
        distanceMeters: null,
        rawText: 'Gira a la izquierda',
        receivedAt: now,
        status: BridgeInstructionStatus.recognized,
      );

      expect(instruction.distanceMeters, isNull);
      expect(instruction.rawDistanceText, isNull);
      expect(instruction.isRecognized, isTrue);
    });

    test(
      'discrimina correctamente estados de incompletitud y no reconocimiento',
      () {
        final incomplete = BridgeNavigationInstruction(
          source: BridgeSourceType.googleMaps,
          maneuverType: ManeuverType.unknown,
          distanceMeters: 300,
          rawText: 'En 300 m',
          receivedAt: now,
          status: BridgeInstructionStatus.incomplete,
        );
        expect(incomplete.isIncomplete, isTrue);
        expect(incomplete.isRecognized, isFalse);

        final unrecognized = BridgeNavigationInstruction(
          source: BridgeSourceType.waze,
          maneuverType: ManeuverType.unknown,
          rawText: 'Tráfico pesado en tu ruta',
          receivedAt: now,
          status: BridgeInstructionStatus.unrecognized,
        );
        expect(unrecognized.isUnrecognized, isTrue);
        expect(unrecognized.isRecognized, isFalse);
      },
    );

    test('evalúa obsolescencia con isExpired y genera asStale inmutable', () {
      final instruction = BridgeNavigationInstruction(
        source: BridgeSourceType.googleMaps,
        maneuverType: ManeuverType.straight,
        distanceMeters: 1000,
        rawText: 'Continúa recto',
        receivedAt: now,
        status: BridgeInstructionStatus.recognized,
      );

      // A los 30 segundos aún es fresca (umbral por defecto de 45s)
      final at30s = now.add(const Duration(seconds: 30));
      expect(instruction.isExpired(now: at30s), isFalse);

      // A los 50 segundos ya es obsoleta
      final at50s = now.add(const Duration(seconds: 50));
      expect(instruction.isExpired(now: at50s), isTrue);

      final staleInstruction = instruction.asStale();
      expect(staleInstruction.isStale, isTrue);
      expect(staleInstruction.status, equals(BridgeInstructionStatus.stale));
      expect(staleInstruction.distanceMeters, equals(1000));
    });

    test('copyWith preserva campos y permite sobreescrituras controladas', () {
      final original = BridgeNavigationInstruction(
        source: BridgeSourceType.googleMaps,
        maneuverType: ManeuverType.sharpRight,
        distanceMeters: 200,
        rawText: 'Giro cerrado a la derecha',
        receivedAt: now,
        status: BridgeInstructionStatus.recognized,
      );

      final updated = original.copyWith(
        distanceMeters: 100,
        rawDistanceText: '100 m',
      );

      expect(updated.distanceMeters, equals(100));
      expect(updated.rawDistanceText, equals('100 m'));
      expect(updated.maneuverType, equals(ManeuverType.sharpRight));
      expect(updated.source, equals(BridgeSourceType.googleMaps));
    });

    test(
      'toDiagnosticString no lanza excepciones y resume atributos esenciales',
      () {
        final instruction = BridgeNavigationInstruction(
          source: BridgeSourceType.googleMaps,
          maneuverType: ManeuverType.roundabout,
          roundaboutExit: 2,
          distanceMeters: 500,
          rawText: 'En la rotonda toma la 2ª salida',
          destinationStreet: 'Av. Circunvalar',
          receivedAt: now,
          status: BridgeInstructionStatus.recognized,
        );

        final diagnostic = instruction.toDiagnosticString();
        expect(diagnostic, contains('[BRIDGE Google Maps]'));
        expect(diagnostic, contains('RECOGNIZED'));
        expect(diagnostic, contains('Salida 2'));
        expect(diagnostic, contains('500m'));
      },
    );
  });
}
