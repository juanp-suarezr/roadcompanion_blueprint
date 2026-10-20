import 'package:road_companion/road_companion.dart';
import 'package:test/test.dart';

void main() {
  final testLocation = Coordinates(4.8133, -75.6961);

  group('Maneuver - Creación y validación de métricas', () {
    test('crea maniobra con todos los campos válidos', () {
      final maneuver = Maneuver(
        instructionText: 'Gira a la derecha en Avenida Bolívar',
        type: ManeuverType.right,
        location: testLocation,
        distanceMeters: 250.0,
        roadName: 'Avenida Bolívar',
        exitNumber: null,
        confidence: 0.95,
      );

      expect(maneuver.instructionText,
          equals('Gira a la derecha en Avenida Bolívar'));
      expect(maneuver.type, equals(ManeuverType.right));
      expect(maneuver.location, equals(testLocation));
      expect(maneuver.distanceMeters, equals(250.0));
      expect(maneuver.roadName, equals('Avenida Bolívar'));
      expect(maneuver.exitNumber, isNull);
      expect(maneuver.confidence, equals(0.95));
    });

    test('acepta distancia cero (0.0 m) para maniobras en el punto actual', () {
      final maneuver = Maneuver(
        instructionText: 'Has llegado a tu destino',
        type: ManeuverType.arrive,
        location: testLocation,
        distanceMeters: 0.0,
      );

      expect(maneuver.distanceMeters, equals(0.0));
    });

    test('acepta número de salida mínimo permitido (exitNumber == 1)', () {
      final maneuver = Maneuver(
        instructionText: 'Toma la primera salida de la rotonda',
        type: ManeuverType.roundabout,
        location: testLocation,
        exitNumber: 1,
      );

      expect(maneuver.exitNumber, equals(1));
    });

    test('acepta límites exactos de confianza (0.0 y 1.0)', () {
      final mMin = Maneuver(
        instructionText: 'Paso tentativo',
        type: ManeuverType.unknown,
        location: testLocation,
        confidence: 0.0,
      );
      final mMax = Maneuver(
        instructionText: 'Paso confirmado',
        type: ManeuverType.straight,
        location: testLocation,
        confidence: 1.0,
      );

      expect(mMin.confidence, equals(0.0));
      expect(mMax.confidence, equals(1.0));
    });

    test('rechaza texto de instrucción vacío o solo espacios', () {
      expect(
        () => Maneuver(
          instructionText: '',
          type: ManeuverType.straight,
          location: testLocation,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'instructionText',
        )),
      );

      expect(
        () => Maneuver(
          instructionText: '   ',
          type: ManeuverType.straight,
          location: testLocation,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'instructionText',
        )),
      );
    });

    test('rechaza nombre de vía vacío o solo espacios cuando no es nulo', () {
      expect(
        () => Maneuver(
          instructionText: 'Continúa',
          type: ManeuverType.straight,
          location: testLocation,
          roadName: '',
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'roadName',
        )),
      );

      expect(
        () => Maneuver(
          instructionText: 'Continúa',
          type: ManeuverType.straight,
          location: testLocation,
          roadName: '   ',
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'roadName',
        )),
      );
    });

    test('rechaza distancia de maniobra negativa', () {
      expect(
        () => Maneuver(
          instructionText: 'Continúa recto',
          type: ManeuverType.straight,
          location: testLocation,
          distanceMeters: -0.1,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'distanceMeters',
        )),
      );
    });

    test('rechaza distancia de maniobra no finita (NaN, Infinity, -Infinity)',
        () {
      expect(
        () => Maneuver(
          instructionText: 'Continúa recto',
          type: ManeuverType.straight,
          location: testLocation,
          distanceMeters: double.nan,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'distanceMeters',
        )),
      );
      expect(
        () => Maneuver(
          instructionText: 'Continúa recto',
          type: ManeuverType.straight,
          location: testLocation,
          distanceMeters: double.infinity,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'distanceMeters',
        )),
      );
      expect(
        () => Maneuver(
          instructionText: 'Continúa recto',
          type: ManeuverType.straight,
          location: testLocation,
          distanceMeters: double.negativeInfinity,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'distanceMeters',
        )),
      );
    });

    test('rechaza número de salida menor a 1 (0 y negativos)', () {
      expect(
        () => Maneuver(
          instructionText: 'Toma la salida',
          type: ManeuverType.roundabout,
          location: testLocation,
          exitNumber: 0,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'exitNumber',
        )),
      );

      expect(
        () => Maneuver(
          instructionText: 'Toma la salida',
          type: ManeuverType.roundabout,
          location: testLocation,
          exitNumber: -2,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'exitNumber',
        )),
      );
    });

    test('rechaza niveles de confianza fuera del rango 0.0 a 1.0 o no finitos',
        () {
      expect(
        () => Maneuver(
          instructionText: 'Continúa',
          type: ManeuverType.straight,
          location: testLocation,
          confidence: -0.01,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'confidence',
        )),
      );

      expect(
        () => Maneuver(
          instructionText: 'Continúa',
          type: ManeuverType.straight,
          location: testLocation,
          confidence: 1.01,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'confidence',
        )),
      );

      expect(
        () => Maneuver(
          instructionText: 'Continúa',
          type: ManeuverType.straight,
          location: testLocation,
          confidence: double.nan,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'confidence',
        )),
      );

      expect(
        () => Maneuver(
          instructionText: 'Continúa',
          type: ManeuverType.straight,
          location: testLocation,
          confidence: double.infinity,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'confidence',
        )),
      );
    });
  });

  group('Maneuver - Inmutabilidad y copyWith con centinela para null explícito',
      () {
    final completeManeuver = Maneuver(
      instructionText: 'Toma la 3ra salida en Glorieta Corales',
      type: ManeuverType.roundabout,
      location: testLocation,
      distanceMeters: 450.0,
      roadName: 'Avenida de las Américas',
      exitNumber: 3,
      confidence: 0.9,
    );

    test('copyWith preserva valores originales si los argumentos se omiten',
        () {
      final updated =
          completeManeuver.copyWith(instructionText: 'Nueva instrucción');

      expect(updated.instructionText, equals('Nueva instrucción'));
      expect(updated.type, equals(completeManeuver.type));
      expect(updated.location, equals(completeManeuver.location));
      expect(updated.distanceMeters, equals(450.0));
      expect(updated.roadName, equals('Avenida de las Américas'));
      expect(updated.exitNumber, equals(3));
      expect(updated.confidence, equals(0.9));
    });

    test('copyWith permite establecer distanceMeters explícitamente en null',
        () {
      final updated = completeManeuver.copyWith(distanceMeters: null);

      expect(updated.distanceMeters, isNull);
      expect(updated.roadName, equals('Avenida de las Américas')); // preservado
      expect(updated.exitNumber, equals(3)); // preservado
    });

    test('copyWith permite establecer roadName explícitamente en null', () {
      final updated = completeManeuver.copyWith(roadName: null);

      expect(updated.roadName, isNull);
      expect(updated.distanceMeters, equals(450.0)); // preservado
      expect(updated.exitNumber, equals(3)); // preservado
    });

    test('copyWith permite establecer exitNumber explícitamente en null', () {
      final updated = completeManeuver.copyWith(exitNumber: null);

      expect(updated.exitNumber, isNull);
      expect(updated.distanceMeters, equals(450.0)); // preservado
      expect(updated.roadName, equals('Avenida de las Américas')); // preservado
    });

    test(
        'copyWith permite actualizar campos opcionales a nuevos valores no nulos',
        () {
      final updated = completeManeuver.copyWith(
        distanceMeters: 120.0,
        roadName: 'Calle 14',
        exitNumber: 1,
      );

      expect(updated.distanceMeters, equals(120.0));
      expect(updated.roadName, equals('Calle 14'));
      expect(updated.exitNumber, equals(1));
    });

    test(
        'copyWith lanza TypeError si se pasa un tipo incompatible a distanceMeters',
        () {
      expect(
        () => completeManeuver.copyWith(distanceMeters: 'no_es_un_double'),
        throwsA(isA<TypeError>()),
      );
    });

    test('copyWith lanza TypeError si se pasa un tipo incompatible a roadName',
        () {
      expect(
        () => completeManeuver.copyWith(roadName: 12345),
        throwsA(isA<TypeError>()),
      );
    });

    test(
        'copyWith lanza TypeError si se pasa un tipo incompatible a exitNumber',
        () {
      expect(
        () => completeManeuver.copyWith(exitNumber: 'salida_tres'),
        throwsA(isA<TypeError>()),
      );
    });

    test('compara correctamente por valor e igualdad estructural', () {
      final m1 = Maneuver(
        instructionText: 'Gira a la izquierda',
        type: ManeuverType.left,
        location: testLocation,
        distanceMeters: 100.0,
      );
      final m2 = Maneuver(
        instructionText: 'Gira a la izquierda',
        type: ManeuverType.left,
        location: testLocation,
        distanceMeters: 100.0,
      );

      expect(m1, equals(m2));
      expect(m1.hashCode, equals(m2.hashCode));
    });

    test('toString retorna representación legible sin secretos', () {
      final m = Maneuver(
        instructionText: 'Gira a la izquierda',
        type: ManeuverType.left,
        location: testLocation,
        distanceMeters: 100.0,
      );
      expect(m.toString(), contains('Maneuver('));
      expect(m.toString(), contains('Gira a la izquierda'));
    });
  });
}
