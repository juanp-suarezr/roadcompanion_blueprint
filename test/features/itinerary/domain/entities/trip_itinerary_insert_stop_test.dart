import 'package:road_companion/road_companion.dart';
import 'package:test/test.dart';

void main() {
  final origin = Destination(
    id: 'orig',
    title: 'Bogotá',
    subtitle: 'Bogotá, Colombia',
    coordinates: Coordinates(4.5981, -74.0758),
  );

  final destination = Destination(
    id: 'dest',
    title: 'Villa de Leyva',
    subtitle: 'Boyacá, Colombia',
    coordinates: Coordinates(5.6322, -73.5244),
  );

  final now = DateTime(2026, 10, 22, 10, 0, 0);

  // Geometría de 4 puntos (~150 km)
  final geometry = [
    Coordinates(4.5981, -74.0758), // Origen (km 0)
    Coordinates(4.9351, -73.9921), // Briceño (~40 km)
    Coordinates(5.3101, -73.8151), // Ubaté (~90 km)
    Coordinates(5.6322, -73.5244), // Villa de Leyva (~150 km)
  ];

  group('TripItinerary - insertStopAtRoutePosition', () {
    test(
      'inserta una nueva parada en la posición intermedia óptima según el avance por carretera',
      () {
        final s1 = TripStop(
          id: 's_briceno',
          name: 'Briceño Gas',
          coordinates: Coordinates(4.9351, -73.9921), // km ~40
          orderIndex: 0,
          isVisited: true, // Ya visitada
        );

        final s2 = TripStop(
          id: 's_ubate',
          name: 'Ubaté Almuerzo',
          coordinates: Coordinates(5.3101, -73.8151), // km ~90
          orderIndex: 1,
          isVisited: false,
        );

        final itinerary = TripItinerary(
          id: 'trip_1',
          title: 'Ruta Boyacá',
          origin: origin,
          destination: destination,
          stops: [s1, s2],
          createdAt: now,
          updatedAt: now,
        );

        // Nuevo POI: Gasolinera en Nemocón (~65 km de la ruta, entre Briceño y Ubaté)
        final newPoiStop = TripStop(
          id: 'poi_gas_zipa',
          name: 'Terpel Nemocón',
          coordinates: Coordinates(5.0600, -73.8800),
          type: TripStopType.fuel,
          orderIndex: 0,
        );

        final updated = itinerary.insertStopAtRoutePosition(
          newPoiStop,
          distanceAlongRouteMeters: 65000.0, // km 65
          routeGeometry: geometry,
        );

        expect(updated.stops.length, equals(3));
        // Debe quedar en la posición intermedia (índice 1)
        expect(updated.stops[0].id, equals('s_briceno'));
        expect(updated.stops[0].orderIndex, equals(0));
        expect(updated.stops[0].isVisited, isTrue); // Preserva estado visitada

        expect(updated.stops[1].id, equals('poi_gas_zipa'));
        expect(updated.stops[1].orderIndex, equals(1));
        expect(updated.stops[1].isVisited, isFalse);

        expect(updated.stops[2].id, equals('s_ubate'));
        expect(updated.stops[2].orderIndex, equals(2));
        expect(updated.stops[2].isVisited, isFalse);

        // Origen y destino permanecen inalterados
        expect(updated.origin.id, equals('orig'));
        expect(updated.destination.id, equals('dest'));

        // calculatedRoute se resetea a null para solicitar recálculo
        expect(updated.calculatedRoute, isNull);
      },
    );

    test(
      'inserta antes de la primera parada existente si el avance es menor',
      () {
        final s1 = TripStop(
          id: 's_briceno',
          name: 'Briceño Gas',
          coordinates: Coordinates(4.9351, -73.9921), // km ~40
          orderIndex: 0,
          isVisited: true,
        );

        final itinerary = TripItinerary(
          id: 'trip_1',
          title: 'Ruta',
          origin: origin,
          destination: destination,
          stops: [s1],
          createdAt: now,
          updatedAt: now,
        );

        // POI en La Caro (~20 km)
        final poiEarly = TripStop(
          id: 'poi_caro',
          name: 'Punto La Caro',
          coordinates: Coordinates(4.8200, -74.0200),
          orderIndex: 0,
        );

        final updated = itinerary.insertStopAtRoutePosition(
          poiEarly,
          distanceAlongRouteMeters: 20000.0,
          routeGeometry: geometry,
        );

        expect(updated.stops.length, equals(2));
        expect(updated.stops[0].id, equals('poi_caro'));
        expect(updated.stops[0].orderIndex, equals(0));
        expect(updated.stops[1].id, equals('s_briceno'));
        expect(updated.stops[1].orderIndex, equals(1));
        expect(updated.stops[1].isVisited, isTrue); // Conserva visited
      },
    );

    test(
      'inserta después de la última parada existente si el avance es mayor',
      () {
        final s1 = TripStop(
          id: 's_briceno',
          name: 'Briceño Gas',
          coordinates: Coordinates(4.9351, -73.9921), // km ~40
          orderIndex: 0,
          isVisited: true,
        );

        final itinerary = TripItinerary(
          id: 'trip_1',
          title: 'Ruta',
          origin: origin,
          destination: destination,
          stops: [s1],
          createdAt: now,
          updatedAt: now,
        );

        // POI en Chiquinquirá (~115 km)
        final poiLate = TripStop(
          id: 'poi_chiqui',
          name: 'Mirador Chiquinquirá',
          coordinates: Coordinates(5.4500, -73.7000),
          orderIndex: 0,
        );

        final updated = itinerary.insertStopAtRoutePosition(
          poiLate,
          distanceAlongRouteMeters: 115000.0,
          routeGeometry: geometry,
        );

        expect(updated.stops.length, equals(2));
        expect(updated.stops[0].id, equals('s_briceno'));
        expect(updated.stops[0].orderIndex, equals(0));
        expect(updated.stops[0].isVisited, isTrue);
        expect(updated.stops[1].id, equals('poi_chiqui'));
        expect(updated.stops[1].orderIndex, equals(1));
      },
    );

    test(
      'maneja paradas con avance kilométrico idéntico o similar de forma determinista',
      () {
        final s1 = TripStop(
          id: 's_briceno',
          name: 'Briceño Gas',
          coordinates: Coordinates(4.9351, -73.9921), // km ~40
          orderIndex: 0,
          isVisited: false,
        );

        final itinerary = TripItinerary(
          id: 'trip_1',
          title: 'Ruta',
          origin: origin,
          destination: destination,
          stops: [s1],
          createdAt: now,
          updatedAt: now,
        );

        // Parada compañera en el mismo km (~40 km)
        final sTwin = TripStop(
          id: 's_twin',
          name: 'Briceño Restaurante',
          coordinates: Coordinates(4.9352, -73.9922),
          orderIndex: 0,
        );

        // Si el avance es igual (o ligeramente posterior), queda secuenciada inmediatamente después
        final updated = itinerary.insertStopAtRoutePosition(
          sTwin,
          distanceAlongRouteMeters: 40000.0,
          routeGeometry: geometry,
        );

        expect(updated.stops.length, equals(2));
        expect(updated.stops[0].id, equals('s_briceno'));
        expect(updated.stops[1].id, equals('s_twin'));
      },
    );

    test(
      'lanza StateError si existen paradas intermedias pero la geometría es nula o inválida',
      () {
        final s1 = TripStop(
          id: 's1',
          name: 'Parada Existente',
          coordinates: Coordinates(4.9351, -73.9921),
          orderIndex: 0,
        );

        final itinerary = TripItinerary(
          id: 'trip_1',
          title: 'Ruta',
          origin: origin,
          destination: destination,
          stops: [s1],
          createdAt: now,
          updatedAt: now,
        );

        final newStop = TripStop(
          id: 's2',
          name: 'Nueva Parada',
          coordinates: Coordinates(5.1000, -73.9000),
          orderIndex: 0,
        );

        // Geometría nula
        expect(
          () => itinerary.insertStopAtRoutePosition(
            newStop,
            distanceAlongRouteMeters: 50000.0,
            routeGeometry: null,
          ),
          throwsA(isA<StateError>()),
        );

        // Geometría inválida con menos de 2 puntos
        expect(
          () => itinerary.insertStopAtRoutePosition(
            newStop,
            distanceAlongRouteMeters: 50000.0,
            routeGeometry: [Coordinates(4.5, -74.0)],
          ),
          throwsA(isA<StateError>()),
        );
      },
    );

    test(
      'lanza ArgumentError ante avance kilométrico no finito o negativo',
      () {
        final itinerary = TripItinerary(
          id: 'trip_1',
          title: 'Ruta',
          origin: origin,
          destination: destination,
          stops: const [],
          createdAt: now,
          updatedAt: now,
        );

        final stop = TripStop(
          id: 's1',
          name: 'Parada',
          coordinates: Coordinates(4.9351, -73.9921),
          orderIndex: 0,
        );

        expect(
          () => itinerary.insertStopAtRoutePosition(
            stop,
            distanceAlongRouteMeters: -100.0,
            routeGeometry: geometry,
          ),
          throwsA(isA<ArgumentError>()),
        );

        expect(
          () => itinerary.insertStopAtRoutePosition(
            stop,
            distanceAlongRouteMeters: double.nan,
            routeGeometry: geometry,
          ),
          throwsA(isA<ArgumentError>()),
        );
      },
    );

    test('hace fallback a addStop cuando la lista de paradas está vacía', () {
      final itinerary = TripItinerary(
        id: 'trip_1',
        title: 'Ruta Directa',
        origin: origin,
        destination: destination,
        stops: const [],
        createdAt: now,
        updatedAt: now,
      );

      final stop = TripStop(
        id: 's_single',
        name: 'Primera Parada',
        coordinates: Coordinates(4.9351, -73.9921),
        orderIndex: 0,
      );

      final updated = itinerary.insertStopAtRoutePosition(
        stop,
        distanceAlongRouteMeters: 40000.0,
        routeGeometry: geometry,
      );

      expect(updated.stops.length, equals(1));
      expect(updated.stops.first.name, equals('Primera Parada'));
      expect(updated.stops.first.orderIndex, equals(0));
    });

    test(
      'lanza ArgumentError si se intenta insertar una parada con ID duplicado',
      () {
        final s1 = TripStop(
          id: 's_dup',
          name: 'Parada Existente',
          coordinates: Coordinates(4.9351, -73.9921),
          orderIndex: 0,
        );

        final itinerary = TripItinerary(
          id: 'trip_1',
          title: 'Ruta',
          origin: origin,
          destination: destination,
          stops: [s1],
          createdAt: now,
          updatedAt: now,
        );

        final duplicateStop = TripStop(
          id: 's_dup',
          name: 'Parada Repetida',
          coordinates: Coordinates(5.000, -73.9000),
          orderIndex: 0,
        );

        expect(
          () => itinerary.insertStopAtRoutePosition(
            duplicateStop,
            distanceAlongRouteMeters: 50000.0,
            routeGeometry: geometry,
          ),
          throwsA(isA<ArgumentError>()),
        );
      },
    );
  });
}
