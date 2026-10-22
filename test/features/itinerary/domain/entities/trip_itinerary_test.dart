import 'package:road_companion/road_companion.dart';
import 'package:test/test.dart';

void main() {
  final origin = Destination(
    id: 'origin_bogota',
    title: 'Plaza de Bolívar, Bogotá',
    subtitle: 'Bogotá, Colombia',
    coordinates: Coordinates(4.5981, -74.0758),
  );

  final destination = Destination(
    id: 'dest_villa_leyva',
    title: 'Villa de Leyva',
    subtitle: 'Boyacá, Colombia',
    coordinates: Coordinates(5.6322, -73.5244),
  );

  final now = DateTime(2026, 10, 22, 10, 0, 0);

  group('TripStop - Entidad de Parada Inmutable', () {
    test('construye parada válida con atributos completos', () {
      final stop = TripStop(
        id: 'stop_1',
        name: 'Gasolinera Briceño',
        coordinates: Coordinates(4.9351, -73.9921),
        type: TripStopType.fuel,
        orderIndex: 0,
        plannedDuration: const Duration(minutes: 15),
      );

      expect(stop.id, equals('stop_1'));
      expect(stop.name, equals('Gasolinera Briceño'));
      expect(stop.type, equals(TripStopType.fuel));
      expect(stop.orderIndex, equals(0));
      expect(stop.isVisited, isFalse);
      expect(stop.plannedDuration, equals(const Duration(minutes: 15)));
    });

    test('rechaza id o nombre vacíos u orden negativo', () {
      expect(
        () => TripStop(
          id: '',
          name: 'Punto',
          coordinates: Coordinates(4.0, -74.0),
          orderIndex: 0,
        ),
        throwsArgumentError,
      );

      expect(
        () => TripStop(
          id: 's1',
          name: '   ',
          coordinates: Coordinates(4.0, -74.0),
          orderIndex: 0,
        ),
        throwsArgumentError,
      );

      expect(
        () => TripStop(
          id: 's1',
          name: 'Punto',
          coordinates: Coordinates(4.0, -74.0),
          orderIndex: -1,
        ),
        throwsArgumentError,
      );
    });
  });

  group('TripItinerary - Gestión y Ordenamiento de Paradas', () {
    test('construye itinerario vacío y calcula destino activo inicial', () {
      final itinerary = TripItinerary(
        id: 'trip_1',
        title: 'Ruta Boyacá',
        origin: origin,
        destination: destination,
        createdAt: now,
        updatedAt: now,
      );

      expect(itinerary.totalStopsCount, equals(0));
      expect(itinerary.nextActiveStop, isNull);
      expect(itinerary.nextActiveDestination, equals(destination));
      expect(itinerary.allStopsVisited, isFalse);
    });

    test('añade paradas consecutivas y asigna orden incremental', () {
      final base = TripItinerary(
        id: 'trip_1',
        title: 'Ruta Boyacá',
        origin: origin,
        destination: destination,
        createdAt: now,
        updatedAt: now,
      );

      final stop1 = TripStop(
        id: 'patios',
        name: 'Mirador de Patios',
        coordinates: Coordinates(4.6601, -74.0321),
        type: TripStopType.viewpoint,
        orderIndex: 99, // Debe ser sobreescrito a 0
      );

      final stop2 = TripStop(
        id: 'la_cabaña',
        name: 'Restaurante La Cabaña',
        coordinates: Coordinates(5.0201, -73.8501),
        type: TripStopType.restaurant,
        orderIndex: 99, // Debe ser sobreescrito a 1
      );

      final it1 = base.addStop(stop1);
      final it2 = it1.addStop(stop2);

      expect(it2.totalStopsCount, equals(2));
      expect(it2.stops[0].name, equals('Mirador de Patios'));
      expect(it2.stops[0].orderIndex, equals(0));
      expect(it2.stops[1].name, equals('Restaurante La Cabaña'));
      expect(it2.stops[1].orderIndex, equals(1));
      expect(it2.nextActiveStop, equals(it2.stops[0]));
    });

    test('rechaza paradas con identificadores duplicados', () {
      final base = TripItinerary(
        id: 'trip_1',
        title: 'Ruta Boyacá',
        origin: origin,
        destination: destination,
        createdAt: now,
        updatedAt: now,
      );

      final stop = TripStop(
        id: 'misma_id',
        name: 'Parada A',
        coordinates: Coordinates(4.7, -74.0),
        orderIndex: 0,
      );

      final it1 = base.addStop(stop);
      expect(() => it1.addStop(stop), throwsArgumentError);
    });

    test('elimina parada y renumera índices de orden consecutivamente', () {
      final base = TripItinerary(
        id: 'trip_1',
        title: 'Ruta',
        origin: origin,
        destination: destination,
        createdAt: now,
        updatedAt: now,
      );

      final s1 = TripStop(
        id: 's1',
        name: 'Parada 1',
        coordinates: Coordinates(4.7, -74.0),
        orderIndex: 0,
      );
      final s2 = TripStop(
        id: 's2',
        name: 'Parada 2',
        coordinates: Coordinates(4.8, -74.0),
        orderIndex: 1,
      );
      final s3 = TripStop(
        id: 's3',
        name: 'Parada 3',
        coordinates: Coordinates(4.9, -74.0),
        orderIndex: 2,
      );

      final it = base.addStop(s1).addStop(s2).addStop(s3);
      expect(it.totalStopsCount, equals(3));

      // Eliminar parada intermedia s2
      final updated = it.removeStop('s2');
      expect(updated.totalStopsCount, equals(2));
      expect(updated.stops[0].id, equals('s1'));
      expect(updated.stops[0].orderIndex, equals(0));
      expect(updated.stops[1].id, equals('s3'));
      expect(updated.stops[1].orderIndex, equals(1)); // Renumerado a 1
    });

    test('reordena paradas y actualiza índices secuenciales', () {
      final base = TripItinerary(
        id: 'trip_1',
        title: 'Ruta',
        origin: origin,
        destination: destination,
        createdAt: now,
        updatedAt: now,
      );

      final s1 = TripStop(
        id: 's1',
        name: 'Primera',
        coordinates: Coordinates(4.7, -74.0),
        orderIndex: 0,
      );
      final s2 = TripStop(
        id: 's2',
        name: 'Segunda',
        coordinates: Coordinates(4.8, -74.0),
        orderIndex: 1,
      );
      final s3 = TripStop(
        id: 's3',
        name: 'Tercera',
        coordinates: Coordinates(4.9, -74.0),
        orderIndex: 2,
      );

      final it = base.addStop(s1).addStop(s2).addStop(s3);

      // Mover la tercera (índice 2) a la primera posición (índice 0)
      final reordered = it.reorderStops(2, 0);
      expect(reordered.stops[0].id, equals('s3'));
      expect(reordered.stops[0].orderIndex, equals(0));
      expect(reordered.stops[1].id, equals('s1'));
      expect(reordered.stops[1].orderIndex, equals(1));
      expect(reordered.stops[2].id, equals('s2'));
      expect(reordered.stops[2].orderIndex, equals(2));
    });

    test(
      'calcula siguiente destino activo dinámicamente según estado de visita',
      () {
        final base = TripItinerary(
          id: 'trip_1',
          title: 'Ruta',
          origin: origin,
          destination: destination,
          createdAt: now,
          updatedAt: now,
        );

        final s1 = TripStop(
          id: 's1',
          name: 'Parada 1',
          coordinates: Coordinates(4.7, -74.0),
          orderIndex: 0,
        );
        final s2 = TripStop(
          id: 's2',
          name: 'Parada 2',
          coordinates: Coordinates(4.8, -74.0),
          orderIndex: 1,
        );

        var it = base.addStop(s1).addStop(s2);

        // 1. Inicialmente la siguiente es s1
        expect(it.nextActiveStop?.id, equals('s1'));
        expect(it.nextActiveDestination.name, equals('Parada 1'));
        expect(it.allStopsVisited, isFalse);

        // 2. Marcar s1 como visitada
        it = it.markStopVisited('s1', visited: true);
        expect(it.nextActiveStop?.id, equals('s2'));
        expect(it.nextActiveDestination.name, equals('Parada 2'));
        expect(it.allStopsVisited, isFalse);

        // 3. Marcar s2 como visitada -> todas las intermedias completadas
        it = it.markStopVisited('s2', visited: true);
        expect(it.nextActiveStop, isNull);
        expect(
          it.nextActiveDestination,
          equals(destination),
        ); // Vuelve al destino final
        expect(it.allStopsVisited, isTrue);
      },
    );
  });
}
