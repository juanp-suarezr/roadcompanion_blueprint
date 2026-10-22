import 'package:road_companion/road_companion.dart';
import 'package:test/test.dart';

void main() {
  const parser = NavigationInstructionParser();
  final testDate = DateTime(2026, 10, 22, 14, 15, 0);

  group('NavigationInstructionParser - Pruebas Sintácticas de Referencia', () {
    // NOTA DE TRANSPARENCIA:
    // Estos casos validan el comportamiento sintáctico determinista del parser.
    // No constituyen garantía de concordancia idéntica con todas las versiones de
    // Google Maps o Waze hasta que se capturen volcados auténticos en el Samsung Galaxy A35.

    group('Extracción de distancias en español y unidades mixtas', () {
      test('procesa distancias en metros como «400 m» y «50 metros»', () {
        final result = parser.parse(
          rawTitle: 'Gira a la derecha',
          rawText: 'en 400 m',
          source: BridgeSourceType.googleMaps,
          receivedAt: testDate,
        );

        expect(result.distanceMeters, equals(400));
        expect(result.rawDistanceText, equals('en 400 m'));
        expect(result.maneuverType, equals(ManeuverType.right));
        expect(result.status, equals(BridgeInstructionStatus.recognized));
      });

      test(
        'procesa distancia con coma decimal «1,2 km» a exactamente 1200 metros',
        () {
          final result = parser.parse(
            rawTitle: 'En 1,2 km',
            rawText: 'Gira a la izquierda en Av. Caracas',
            source: BridgeSourceType.googleMaps,
            receivedAt: testDate,
          );

          expect(result.distanceMeters, equals(1200));
          expect(result.maneuverType, equals(ManeuverType.left));
          expect(result.destinationStreet, equals('Av. Caracas'));
          expect(result.status, equals(BridgeInstructionStatus.recognized));
        },
      );

      test(
        'procesa distancia con punto decimal «1.2 km» a exactamente 1200 metros',
        () {
          final result = parser.parse(
            rawTitle: 'En 1.2 km',
            rawText: 'Gira a la izquierda',
            source: BridgeSourceType.waze,
            receivedAt: testDate,
          );

          expect(result.distanceMeters, equals(1200));
          expect(result.maneuverType, equals(ManeuverType.left));
        },
      );

      test('procesa distancias enteras en kilómetros como «2 km»', () {
        final result = parser.parse(
          rawTitle: 'En 2 km',
          rawText: 'Continúa recto',
          source: BridgeSourceType.googleMaps,
          receivedAt: testDate,
        );

        expect(result.distanceMeters, equals(2000));
        expect(result.maneuverType, equals(ManeuverType.straight));
      });

      test('no inventa distancia si el texto carece de métricas numéricas', () {
        final result = parser.parse(
          rawTitle: 'Gira a la derecha',
          rawText: 'en Calle 100',
          source: BridgeSourceType.googleMaps,
          receivedAt: testDate,
        );

        expect(result.distanceMeters, isNull);
        expect(result.rawDistanceText, isNull);
        expect(result.maneuverType, equals(ManeuverType.right));
        expect(result.status, equals(BridgeInstructionStatus.recognized));
      });
    });

    group('Reconocimiento de maniobras en español', () {
      test('identifica giros a la izquierda (leve, normal, pronunciado)', () {
        final slight = parser.parse(
          rawText: 'En 300 m, mantente a la izquierda hacia Autopista Norte',
          source: BridgeSourceType.googleMaps,
          receivedAt: testDate,
        );
        expect(slight.maneuverType, equals(ManeuverType.slightLeft));

        final normal = parser.parse(
          rawText: 'Gira a la izquierda en Carrera 15',
          source: BridgeSourceType.googleMaps,
          receivedAt: testDate,
        );
        expect(normal.maneuverType, equals(ManeuverType.left));

        final sharp = parser.parse(
          rawText: 'Giro cerrado a la izquierda en 50 m',
          source: BridgeSourceType.waze,
          receivedAt: testDate,
        );
        expect(sharp.maneuverType, equals(ManeuverType.sharpLeft));
      });

      test('identifica giros a la derecha (leve, normal, pronunciado)', () {
        final slight = parser.parse(
          rawText: 'En 200 m, bifurcación a la derecha',
          source: BridgeSourceType.googleMaps,
          receivedAt: testDate,
        );
        expect(slight.maneuverType, equals(ManeuverType.slightRight));

        final normal = parser.parse(
          rawText: 'Doble a la derecha',
          source: BridgeSourceType.waze,
          receivedAt: testDate,
        );
        expect(normal.maneuverType, equals(ManeuverType.right));

        final sharp = parser.parse(
          rawText: 'Giro pronunciado a la derecha en 100 m',
          source: BridgeSourceType.googleMaps,
          receivedAt: testDate,
        );
        expect(sharp.maneuverType, equals(ManeuverType.sharpRight));
      });

      test('identifica cambio de sentido / retorno en U', () {
        final uturn1 = parser.parse(
          rawText: 'Haz un cambio de sentido en 150 m',
          source: BridgeSourceType.googleMaps,
          receivedAt: testDate,
        );
        expect(uturn1.maneuverType, equals(ManeuverType.uTurn));

        final uturn2 = parser.parse(
          rawText: 'Retorno en U-turn',
          source: BridgeSourceType.waze,
          receivedAt: testDate,
        );
        expect(uturn2.maneuverType, equals(ManeuverType.uTurn));
      });

      test('identifica rotondas con número de salida ordinal o cardinal', () {
        final r1 = parser.parse(
          rawText: 'En la rotonda, toma la 2ª salida hacia Av. El Dorado',
          source: BridgeSourceType.googleMaps,
          receivedAt: testDate,
        );
        expect(r1.maneuverType, equals(ManeuverType.roundabout));
        expect(r1.roundaboutExit, equals(2));

        final r2 = parser.parse(
          rawText: 'En la glorieta toma la salida 1',
          source: BridgeSourceType.waze,
          receivedAt: testDate,
        );
        expect(r2.maneuverType, equals(ManeuverType.roundabout));
        expect(r2.roundaboutExit, equals(1));

        final r3 = parser.parse(
          rawText: 'At the roundabout, take the 3rd exit',
          source: BridgeSourceType.googleMaps,
          receivedAt: testDate,
        );
        expect(r3.maneuverType, equals(ManeuverType.roundabout));
        expect(r3.roundaboutExit, equals(3));
      });

      test('identifica llegada al destino', () {
        final arr1 = parser.parse(
          rawText: 'Has llegado a tu destino',
          source: BridgeSourceType.googleMaps,
          receivedAt: testDate,
        );
        expect(arr1.maneuverType, equals(ManeuverType.arrive));
        expect(arr1.status, equals(BridgeInstructionStatus.recognized));

        final arr2 = parser.parse(
          rawText: 'Destino alcanzado',
          source: BridgeSourceType.waze,
          receivedAt: testDate,
        );
        expect(arr2.maneuverType, equals(ManeuverType.arrive));
      });

      test('identifica continuar recto', () {
        final straight = parser.parse(
          rawText: 'Continúa recto por Calle 26 durante 3 km',
          source: BridgeSourceType.googleMaps,
          receivedAt: testDate,
        );
        expect(straight.maneuverType, equals(ManeuverType.straight));
        expect(straight.status, equals(BridgeInstructionStatus.recognized));
      });
    });

    group('Seguridad y Manejo de Textos No Reconocidos o Incompletos', () {
      test('NO convierte texto desconocido en un giro recto por defecto', () {
        final unknownText = parser.parse(
          rawText: 'Precaución: radar fijo en la vía',
          source: BridgeSourceType.waze,
          receivedAt: testDate,
        );

        expect(unknownText.maneuverType, equals(ManeuverType.unknown));
        expect(
          unknownText.status,
          equals(BridgeInstructionStatus.unrecognized),
        );
      });

      test(
        'mensajes de estado de GPS y sesión se clasifican como unrecognized',
        () {
          final gps = parser.parse(
            rawTitle: 'Google Maps',
            rawText: 'Buscando señal GPS...',
            source: BridgeSourceType.googleMaps,
            receivedAt: testDate,
          );
          expect(gps.maneuverType, equals(ManeuverType.unknown));
          expect(gps.status, equals(BridgeInstructionStatus.unrecognized));

          final waze = parser.parse(
            rawTitle: 'Waze',
            rawText: 'Bienvenido a Waze — Sesión iniciada',
            source: BridgeSourceType.waze,
            receivedAt: testDate,
          );
          expect(waze.maneuverType, equals(ManeuverType.unknown));
          expect(waze.status, equals(BridgeInstructionStatus.unrecognized));
        },
      );

      test(
        'texto con distancia pero sin maniobra se clasifica como incomplete',
        () {
          final incomplete = parser.parse(
            rawText: 'en 400 m',
            source: BridgeSourceType.googleMaps,
            receivedAt: testDate,
          );

          expect(incomplete.distanceMeters, equals(400));
          expect(incomplete.maneuverType, equals(ManeuverType.unknown));
          expect(incomplete.status, equals(BridgeInstructionStatus.incomplete));
          expect(incomplete.isIncomplete, isTrue);
          expect(incomplete.isRecognized, isFalse);
        },
      );

      test(
        'entrada totalmente vacía se maneja de forma segura como unrecognized',
        () {
          final empty = parser.parse(
            rawTitle: null,
            rawText: '',
            rawSubText: '   ',
            source: BridgeSourceType.unknown,
            receivedAt: testDate,
          );

          expect(empty.maneuverType, equals(ManeuverType.unknown));
          expect(empty.status, equals(BridgeInstructionStatus.unrecognized));
        },
      );
    });
  });
}
