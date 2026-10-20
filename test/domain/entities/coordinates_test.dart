import 'package:road_companion/road_companion.dart';
import 'package:test/test.dart';

void main() {
  group('Coordinates - Validaciones de rango y finitud', () {
    test('acepta coordenadas válidas dentro del rango admisible', () {
      final coord = Coordinates(4.8133, -75.6961);
      expect(coord.latitude, equals(4.8133));
      expect(coord.longitude, equals(-75.6961));
    });

    test('acepta los 4 límites extremos exactos en las esquinas del globo', () {
      expect(() => Coordinates(90.0, 180.0), returnsNormally);
      expect(() => Coordinates(-90.0, -180.0), returnsNormally);
      expect(() => Coordinates(90.0, -180.0), returnsNormally);
      expect(() => Coordinates(-90.0, 180.0), returnsNormally);
      expect(() => Coordinates(0.0, 0.0), returnsNormally);
    });

    test('rechaza latitud superior a 90 grados', () {
      expect(
        () => Coordinates(90.0001, -75.0),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'latitude',
        )),
      );
    });

    test('rechaza latitud inferior a -90 grados', () {
      expect(
        () => Coordinates(-90.1, -75.0),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'latitude',
        )),
      );
    });

    test('rechaza longitud superior a 180 grados', () {
      expect(
        () => Coordinates(4.0, 180.01),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'longitude',
        )),
      );
    });

    test('rechaza longitud inferior a -180 grados', () {
      expect(
        () => Coordinates(4.0, -180.05),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'longitude',
        )),
      );
    });

    test('rechaza valores no finitos (NaN, Infinity, -Infinity)', () {
      expect(
        () => Coordinates(double.nan, -75.0),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'latitude',
        )),
      );
      expect(
        () => Coordinates(4.0, double.nan),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'longitude',
        )),
      );
      expect(
        () => Coordinates(double.infinity, 0.0),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'latitude',
        )),
      );
      expect(
        () => Coordinates(double.negativeInfinity, 0.0),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'latitude',
        )),
      );
      expect(
        () => Coordinates(0.0, double.infinity),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'longitude',
        )),
      );
      expect(
        () => Coordinates(0.0, double.negativeInfinity),
        throwsA(isA<ArgumentError>().having(
          (e) => e.name,
          'name',
          'longitude',
        )),
      );
    });
  });

  group('Coordinates - Distancia directa Haversine', () {
    test('distancia hacia el mismo punto es 0.0 metros', () {
      final p = Coordinates(4.8133, -75.6961);
      expect(p.distanceTo(p), equals(0.0));
    });

    test('calcula distancia directa coherente entre Pereira y Armenia', () {
      final pereira = Coordinates(4.8133, -75.6961);
      final armenia = Coordinates(4.5339, -75.6811);

      final distanceMeters = pereira.distanceTo(armenia);

      expect(distanceMeters, greaterThan(30800));
      expect(distanceMeters, lessThan(31500));
    });

    test('la distancia es conmutativa (A->B == B->A)', () {
      final a = Coordinates(4.8133, -75.6961);
      final b = Coordinates(4.5339, -75.6811);
      expect(a.distanceTo(b), closeTo(b.distanceTo(a), 0.0001));
    });

    test('distancia en el antimeridiano (180° y -180° sobre el mismo paralelo)',
        () {
      final east = Coordinates(0.0, 180.0);
      final west = Coordinates(0.0, -180.0);
      // Representan el mismo meridiano exacto opuesto a Greenwich
      expect(east.distanceTo(west), closeTo(0.0, 0.001));
    });

    test(
        'distancia entre polos norte y sur es media circunferencia terrestre (~20.015 km)',
        () {
      final northPole = Coordinates(90.0, 0.0);
      final southPole = Coordinates(-90.0, 0.0);
      expect(northPole.distanceTo(southPole), closeTo(20015086, 1000));
    });

    test('distancia entre puntos antipodales en el ecuador (~20.015 km)', () {
      final p1 = Coordinates(0.0, 0.0);
      final p2 = Coordinates(0.0, 180.0);
      expect(p1.distanceTo(p2), closeTo(20015086, 1000));
    });
  });

  group('Coordinates - Igualdad e inmutabilidad', () {
    test('dos coordenadas con mismos valores son iguales', () {
      final c1 = Coordinates(4.8133, -75.6961);
      final c2 = Coordinates(4.8133, -75.6961);
      expect(c1, equals(c2));
      expect(c1.hashCode, equals(c2.hashCode));
    });

    test('trata 0.0 y -0.0 como coordenadas equivalentes en rango e igualdad',
        () {
      final cPositiveZero = Coordinates(0.0, 0.0);
      final cNegativeZero = Coordinates(-0.0, -0.0);
      expect(cPositiveZero, equals(cNegativeZero));
      expect(cPositiveZero.distanceTo(cNegativeZero), equals(0.0));
    });

    test('coordenadas con valores distintos no son iguales', () {
      final c1 = Coordinates(4.8133, -75.6961);
      final c2 = Coordinates(4.8134, -75.6961);
      expect(c1, isNot(equals(c2)));
    });

    test('toString retorna formato legible sin exponer secretos', () {
      final c = Coordinates(4.8133, -75.6961);
      expect(c.toString(), equals('Coordinates(lat: 4.8133, lon: -75.6961)'));
    });
  });
}
