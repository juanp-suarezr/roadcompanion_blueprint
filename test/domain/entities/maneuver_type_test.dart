import 'package:road_companion/road_companion.dart';
import 'package:test/test.dart';

void main() {
  group('ManeuverType - Normalización y fallback seguro', () {
    test('mapea cadenas estándar a tipos conocidos', () {
      expect(
        ManeuverType.fromString('straight'),
        equals(ManeuverType.straight),
      );
      expect(
        ManeuverType.fromString('continue'),
        equals(ManeuverType.straight),
      );
      expect(ManeuverType.fromString('left'), equals(ManeuverType.left));
      expect(ManeuverType.fromString('turn_left'), equals(ManeuverType.left));
      expect(ManeuverType.fromString('turn-left'), equals(ManeuverType.left));
      expect(
        ManeuverType.fromString('slight_left'),
        equals(ManeuverType.slightLeft),
      );
      expect(
        ManeuverType.fromString('sharp_left'),
        equals(ManeuverType.sharpLeft),
      );
      expect(ManeuverType.fromString('right'), equals(ManeuverType.right));
      expect(ManeuverType.fromString('turn_right'), equals(ManeuverType.right));
      expect(
        ManeuverType.fromString('slight_right'),
        equals(ManeuverType.slightRight),
      );
      expect(
        ManeuverType.fromString('sharp_right'),
        equals(ManeuverType.sharpRight),
      );
      expect(ManeuverType.fromString('u_turn'), equals(ManeuverType.uTurn));
      expect(ManeuverType.fromString('uturn'), equals(ManeuverType.uTurn));
      expect(
        ManeuverType.fromString('roundabout'),
        equals(ManeuverType.roundabout),
      );
      expect(
        ManeuverType.fromString('rotary'),
        equals(ManeuverType.roundabout),
      );
      expect(ManeuverType.fromString('depart'), equals(ManeuverType.depart));
      expect(ManeuverType.fromString('arrive'), equals(ManeuverType.arrive));
    });

    test('soporta mayúsculas y espacios en blanco accidentales', () {
      expect(
        ManeuverType.fromString('  TURN_LEFT  '),
        equals(ManeuverType.left),
      );
      expect(
        ManeuverType.fromString('RoundAbout'),
        equals(ManeuverType.roundabout),
      );
      expect(
        ManeuverType.fromString('SHARP RIGHT'),
        equals(ManeuverType.sharpRight),
      );
    });

    test(
      'mapea de forma segura a unknown si la entrada es nula, vacía o desconocida',
      () {
        expect(ManeuverType.fromString(null), equals(ManeuverType.unknown));
        expect(ManeuverType.fromString(''), equals(ManeuverType.unknown));
        expect(ManeuverType.fromString('   '), equals(ManeuverType.unknown));
        expect(
          ManeuverType.fromString('curva_pronunciada'),
          equals(ManeuverType.unknown),
        );
        expect(
          ManeuverType.fromString('fly_over'),
          equals(ManeuverType.unknown),
        );
      },
    );
  });
}
