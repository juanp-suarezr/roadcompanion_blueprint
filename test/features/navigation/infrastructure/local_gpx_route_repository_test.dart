import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_companion/features/navigation/infrastructure/parsers/gpx_parser.dart';
import 'package:road_companion/features/navigation/infrastructure/repositories/local_gpx_route_repository.dart';

void main() {
  late Directory tempDir;
  late LocalGpxRouteRepository repository;
  const parser = GpxParser();

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('gpx_repo_test_');
    repository = LocalGpxRouteRepository(
      directoryProvider: () async => tempDir,
      parser: parser,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  const sampleGpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="RoadCompanion">
  <metadata><name>Ruta Sierra Nevada</name></metadata>
  <trk>
    <trkseg>
      <trkpt lat="11.1" lon="-74.0"><ele>500.0</ele></trkpt>
      <trkpt lat="11.2" lon="-74.1"><ele>850.0</ele></trkpt>
    </trkseg>
  </trk>
</gpx>''';

  group('LocalGpxRouteRepository - Persistencia y gestión de biblioteca', () {
    test(
      'Guarda una ruta GPX, actualiza el índice y la recupera intacta',
      () async {
        final parsedRoute = parser.parse(sampleGpx);

        final metadata = await repository.saveRoute(
          originalFileName: 'sierra.gpx',
          rawGpxContent: sampleGpx,
          parsedRoute: parsedRoute,
        );

        expect(metadata.name, equals('Ruta Sierra Nevada'));
        expect(metadata.fileName, equals('sierra.gpx'));
        expect(metadata.totalPoints, equals(2));

        // Comprobar listado de rutas guardadas
        final savedList = await repository.getSavedRoutes();
        expect(savedList.length, equals(1));
        expect(savedList.first.id, equals(metadata.id));

        // Cargar la ruta completa desde disco
        final loadedRoute = await repository.loadRoute(metadata.id);
        expect(loadedRoute.name, equals('Ruta Sierra Nevada'));
        expect(loadedRoute.totalPoints, equals(2));
        expect(loadedRoute.minElevation, equals(500.0));
        expect(loadedRoute.maxElevation, equals(850.0));
      },
    );

    test(
      'Evita duplicación en el índice cuando se importa la misma ruta',
      () async {
        final parsedRoute = parser.parse(sampleGpx);

        final meta1 = await repository.saveRoute(
          originalFileName: 'sierra_1.gpx',
          rawGpxContent: sampleGpx,
          parsedRoute: parsedRoute,
        );

        final meta2 = await repository.saveRoute(
          originalFileName: 'sierra_2.gpx',
          rawGpxContent: sampleGpx,
          parsedRoute: parsedRoute,
        );

        expect(meta1.id, equals(meta2.id));
        final savedList = await repository.getSavedRoutes();
        expect(savedList.length, equals(1));
      },
    );

    test('Elimina una ruta guardada y su archivo físico de disco', () async {
      final parsedRoute = parser.parse(sampleGpx);

      final meta = await repository.saveRoute(
        originalFileName: 'sierra.gpx',
        rawGpxContent: sampleGpx,
        parsedRoute: parsedRoute,
      );

      expect((await repository.getSavedRoutes()).length, equals(1));

      await repository.deleteRoute(meta.id);

      final listAfterDelete = await repository.getSavedRoutes();
      expect(listAfterDelete, isEmpty);

      final physicalFile = File('${tempDir.path}/gpx_routes/${meta.id}.gpx');
      expect(await physicalFile.exists(), isFalse);
    });

    test(
      'Maneja limpiamente archivos eliminados externamente del almacenamiento',
      () async {
        final parsedRoute = parser.parse(sampleGpx);

        final meta = await repository.saveRoute(
          originalFileName: 'sierra.gpx',
          rawGpxContent: sampleGpx,
          parsedRoute: parsedRoute,
        );

        // Eliminar el archivo físico manualmente simulando borrado externo
        final physicalFile = File('${tempDir.path}/gpx_routes/${meta.id}.gpx');
        await physicalFile.delete();

        // getSavedRoutes() debe detectar la ausencia, limpiar el índice y no retornar la ruta
        final savedList = await repository.getSavedRoutes();
        expect(savedList, isEmpty);

        // loadRoute() debe lanzar FileSystemException
        expect(
          () => repository.loadRoute(meta.id),
          throwsA(isA<FileSystemException>()),
        );
      },
    );
  });
}
