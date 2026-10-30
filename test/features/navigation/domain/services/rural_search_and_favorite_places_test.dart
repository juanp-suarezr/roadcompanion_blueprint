import 'package:flutter_test/flutter_test.dart';
import 'package:road_companion/domain/entities/coordinates.dart';
import 'package:road_companion/features/navigation/domain/entities/saved_favorite_place.dart';
import 'package:road_companion/features/navigation/domain/services/smart_navigation_memory_service.dart';
import 'package:road_companion/features/navigation/infrastructure/services/nominatim_geocoding_service.dart';

void main() {
  group('Búsqueda geográfica decimal y normalización', () {
    test(
      'tryParseCoordinatesQuery detecta coordenadas con coma y espacios',
      () {
        final dest1 = NominatimGeocodingService.tryParseCoordinatesQuery(
          '4.78389, -75.05948',
        );
        expect(dest1, isNotNull);
        expect(dest1!.coordinates.latitude, closeTo(4.78389, 0.0001));
        expect(dest1.coordinates.longitude, closeTo(-75.05948, 0.0001));
        expect(dest1.category, 'coordinates');

        final dest2 = NominatimGeocodingService.tryParseCoordinatesQuery(
          '  4.78389   -75.05948  ',
        );
        expect(dest2, isNotNull);
        expect(dest2!.coordinates.latitude, closeTo(4.78389, 0.0001));
        expect(dest2.coordinates.longitude, closeTo(-75.05948, 0.0001));

        final invalid = NominatimGeocodingService.tryParseCoordinatesQuery(
          'Calle 45 # 12-34',
        );
        expect(invalid, isNull);
      },
    );

    test('normalizeColombianQuery maneja vías y topónimos rurales', () {
      final norm = NominatimGeocodingService.normalizeColombianQuery(
        'Cra. 10 # 20-30',
      );
      expect(norm, contains('Carrera 10'));
      expect(norm, isNot(contains('#')));
    });
  });

  group('SmartNavigationMemoryService — Lugares Favoritos Persistentes', () {
    test(
      'Guarda, lista, edita y elimina lugares favoritos (ej. Casa en vereda)',
      () async {
        final memory = SmartNavigationMemoryService(null);
        await memory.load();

        expect(memory.favoritePlaces, isEmpty);

        // 1. Guardar casa en una vereda sin dirección formal
        final veredaHome = SavedFavoritePlace(
          id: 'place_vereda_01',
          name: 'Mi casa en la vereda',
          coordinates: Coordinates(5.04521, -75.48912),
          address: 'Vereda El Rosario, Caldas',
          category: FavoritePlaceCategory.home,
          createdAt: DateTime.now(),
          notes: 'Entrada por el portón de madera, carretera destapada',
        );

        await memory.saveFavoritePlace(veredaHome);
        expect(memory.favoritePlaces.length, 1);
        expect(memory.favoritePlaces.first.name, 'Mi casa en la vereda');
        expect(
          memory.favoritePlaces.first.category,
          FavoritePlaceCategory.home,
        );

        // 2. Guardar mirador favorito
        final mirador = SavedFavoritePlace(
          id: 'place_mirador_02',
          name: 'Mirador La Cruz',
          coordinates: Coordinates(6.65218, -73.28626),
          category: FavoritePlaceCategory.viewpoint,
          createdAt: DateTime.now().add(const Duration(seconds: 1)),
        );

        await memory.saveFavoritePlace(mirador);
        expect(memory.favoritePlaces.length, 2);

        // El más reciente aparece primero
        expect(memory.favoritePlaces.first.name, 'Mirador La Cruz');

        // 3. Editar nombre de la casa
        final updated = veredaHome.copyWith(
          name: 'Finca El Ensueño',
          category: FavoritePlaceCategory.farm,
        );
        await memory.saveFavoritePlace(updated);
        expect(memory.favoritePlaces.length, 2);
        expect(
          memory.favoritePlaces.any(
            (p) =>
                p.name == 'Finca El Ensueño' &&
                p.category == FavoritePlaceCategory.farm,
          ),
          isTrue,
        );

        // 4. Eliminar mirador
        await memory.deleteFavoritePlace(mirador.id);
        expect(memory.favoritePlaces.length, 1);
        expect(memory.favoritePlaces.first.id, veredaHome.id);
      },
    );
  });
}
