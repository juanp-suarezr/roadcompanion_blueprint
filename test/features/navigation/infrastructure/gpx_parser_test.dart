import 'package:flutter_test/flutter_test.dart';
import 'package:road_companion/features/navigation/domain/entities/imported_gpx_route.dart';
import 'package:road_companion/features/navigation/infrastructure/parsers/gpx_parser.dart';

void main() {
  const parser = GpxParser();

  group('GpxParser - Análisis y validaciones obligatorias T2.1', () {
    test('1. GPX válido con un track y varios puntos', () {
      const gpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="RoadCompanion" xmlns="http://www.topografix.com/GPX/1/1">
  <metadata>
    <name>Ruta del Café</name>
  </metadata>
  <trk>
    <name>Tramo Principal</name>
    <trkseg>
      <trkpt lat="4.8133" lon="-75.6961">
        <ele>1411.0</ele>
        <time>2026-10-20T10:00:00Z</time>
      </trkpt>
      <trkpt lat="4.8140" lon="-75.6950">
        <ele>1415.5</ele>
      </trkpt>
      <trkpt lat="4.8150" lon="-75.6940">
        <ele>1420.0</ele>
      </trkpt>
    </trkseg>
  </trk>
</gpx>''';

      final route = parser.parse(gpx);

      expect(route, isA<ImportedGpxRoute>());
      expect(route.name, equals('Ruta del Café'));
      expect(route.totalPoints, equals(3));
      expect(route.segments.length, equals(1));
      expect(route.minElevation, equals(1411.0));
      expect(route.maxElevation, equals(1420.0));
      expect(route.totalGeographicDistanceMeters, greaterThan(0.0));
      expect(route.origin.latitude, closeTo(4.8133, 0.0001));
      expect(route.destination.latitude, closeTo(4.8150, 0.0001));
    });

    test(
      '2. GPX con varios segmentos (no suma distancia entre segmentos discontinuos)',
      () {
        // Dos segmentos:
        // Seg 1: P1 (4.8133, -75.6961) -> P2 (4.8140, -75.6950)
        // Seg 2: P3 (4.5339, -75.6811) -> P4 (4.5345, -75.6800)
        // Distancia entre Seg1 y Seg2 es de más de 30 km (Pereira a Armenia).
        // Si no se inventa carretera, la distancia total debe ser sólo (dist(P1,P2) + dist(P3,P4)), que es < 400 m.
        const gpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="RoadCompanion">
  <trk>
    <name>Ruta Discontinua</name>
    <trkseg>
      <trkpt lat="4.8133" lon="-75.6961" />
      <trkpt lat="4.8140" lon="-75.6950" />
    </trkseg>
    <trkseg>
      <trkpt lat="4.5339" lon="-75.6811" />
      <trkpt lat="4.5345" lon="-75.6800" />
    </trkseg>
  </trk>
</gpx>''';

        final route = parser.parse(gpx);

        expect(route.segments.length, equals(2));
        expect(route.totalPoints, equals(4));

        final seg1Dist = route.segments[0].calculateDistanceMeters();
        final seg2Dist = route.segments[1].calculateDistanceMeters();

        expect(seg1Dist, greaterThan(100.0));
        expect(seg1Dist, lessThan(300.0));

        expect(seg2Dist, greaterThan(100.0));
        expect(seg2Dist, lessThan(300.0));

        // La distancia total es estrictamente la suma intra-segmento, sin el salto de 31 km
        expect(
          route.totalGeographicDistanceMeters,
          closeTo(seg1Dist + seg2Dist, 0.001),
        );
        expect(route.totalGeographicDistanceMeters, lessThan(1000.0));
      },
    );

    test('3. GPX con una ruta (<rte>) sin track (<trk>)', () {
      const gpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="RoadCompanion">
  <rte>
    <name>Travesía de los Nevados</name>
    <rtept lat="5.0500" lon="-75.4800">
      <ele>2150.0</ele>
    </rtept>
    <rtept lat="5.0600" lon="-75.4700">
      <ele>2300.0</ele>
    </rtept>
  </rte>
</gpx>''';

      final route = parser.parse(gpx);

      expect(route.name, equals('Travesía de los Nevados'));
      expect(route.totalPoints, equals(2));
      expect(route.segments.length, equals(1));
      expect(route.minElevation, equals(2150.0));
      expect(route.maxElevation, equals(2300.0));
      expect(route.totalGeographicDistanceMeters, greaterThan(1000.0));
    });

    test('4. Coordenadas inválidas (fuera de rango o no numéricas)', () {
      const gpxLatOutOfRange = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1"><trk><trkseg>
  <trkpt lat="95.0000" lon="-74.0000" />
</trkseg></trk></gpx>''';

      expect(
        () => parser.parse(gpxLatOutOfRange),
        throwsA(
          isA<GpxParseException>().having(
            (e) => e.message,
            'message',
            contains('rango geográfico'),
          ),
        ),
      );

      const gpxLonOutOfRange = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1"><trk><trkseg>
  <trkpt lat="4.0000" lon="195.0000" />
</trkseg></trk></gpx>''';

      expect(
        () => parser.parse(gpxLonOutOfRange),
        throwsA(
          isA<GpxParseException>().having(
            (e) => e.message,
            'message',
            contains('rango geográfico'),
          ),
        ),
      );

      const gpxNonNumeric = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1"><trk><trkseg>
  <trkpt lat="invalido" lon="-74.0000" />
</trkseg></trk></gpx>''';

      expect(
        () => parser.parse(gpxNonNumeric),
        throwsA(
          isA<GpxParseException>().having(
            (e) => e.message,
            'message',
            contains('no numérica'),
          ),
        ),
      );
    });

    test('5. Archivo vacío o solo espacios en blanco', () {
      expect(
        () => parser.parse(''),
        throwsA(
          isA<GpxParseException>().having(
            (e) => e.message,
            'message',
            contains('vacío'),
          ),
        ),
      );

      expect(
        () => parser.parse('   \n\t  '),
        throwsA(
          isA<GpxParseException>().having(
            (e) => e.message,
            'message',
            contains('vacío'),
          ),
        ),
      );
    });

    test('6. XML malformado o con etiquetas rotas', () {
      const gpxMalformed = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1">
  <trk>
    <trkseg>
      <trkpt lat="4.8" lon="-75.6">
    </trkseg>
</gpx>''';

      expect(
        () => parser.parse(gpxMalformed),
        throwsA(
          isA<GpxParseException>().having(
            (e) => e.message,
            'message',
            contains('malformado'),
          ),
        ),
      );
    });

    test('7. Archivo sin puntos utilizables', () {
      const gpxEmptyTrack = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="RoadCompanion">
  <metadata><name>Ruta Fantasma</name></metadata>
  <trk>
    <name>Sin puntos</name>
    <trkseg></trkseg>
  </trk>
</gpx>''';

      expect(
        () => parser.parse(gpxEmptyTrack),
        throwsA(
          isA<GpxParseException>().having(
            (e) => e.message,
            'message',
            contains('no contiene puntos de recorrido utilizables'),
          ),
        ),
      );
    });

    test(
      '8. Distancia aproximada entre dos coordenadas conocidas (Pereira y Armenia)',
      () {
        // Coordenadas conocidas: Pereira (4.8133, -75.6961) y Armenia (4.5339, -75.6811)
        // Distancia directa Haversine calculada en coordinates_test: entre 30800 y 31500 m (~31.1 km).
        const gpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1">
  <metadata><name>Eje Cafetero</name></metadata>
  <trk>
    <trkseg>
      <trkpt lat="4.8133" lon="-75.6961" />
      <trkpt lat="4.5339" lon="-75.6811" />
    </trkseg>
  </trk>
</gpx>''';

        final route = parser.parse(gpx);

        expect(route.totalPoints, equals(2));
        expect(route.totalGeographicDistanceMeters, greaterThan(30800.0));
        expect(route.totalGeographicDistanceMeters, lessThan(31500.0));
        expect(route.totalDistanceKm, closeTo(31.1, 0.4));
      },
    );

    test('9. Manejo correcto de elevación ausente (<ele> no suministrado)', () {
      const gpxWithoutEle = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1">
  <trk>
    <trkseg>
      <trkpt lat="5.2045" lon="-74.7408" />
      <trkpt lat="5.2410" lon="-74.7350" />
    </trkseg>
  </trk>
</gpx>''';

      final route = parser.parse(gpxWithoutEle);

      expect(route.minElevation, isNull);
      expect(route.maxElevation, isNull);
      expect(route.segments.first.points[0].elevation, isNull);
      expect(route.segments.first.points[1].elevation, isNull);
    });

    test('10. Preservación estricta del orden de los puntos', () {
      const gpxOrdered = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1">
  <trk>
    <trkseg>
      <trkpt lat="1.0" lon="10.0" />
      <trkpt lat="2.0" lon="20.0" />
      <trkpt lat="3.0" lon="30.0" />
      <trkpt lat="4.0" lon="40.0" />
    </trkseg>
  </trk>
</gpx>''';

      final route = parser.parse(gpxOrdered);
      final pts = route.allCoordinates;

      expect(pts.length, equals(4));
      expect(pts[0].latitude, equals(1.0));
      expect(pts[0].longitude, equals(10.0));

      expect(pts[1].latitude, equals(2.0));
      expect(pts[1].longitude, equals(20.0));

      expect(pts[2].latitude, equals(3.0));
      expect(pts[2].longitude, equals(30.0));

      expect(pts[3].latitude, equals(4.0));
      expect(pts[3].longitude, equals(40.0));
    });
  });
}
