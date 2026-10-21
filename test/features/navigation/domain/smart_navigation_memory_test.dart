import 'package:flutter_test/flutter_test.dart';
import 'package:road_companion/domain/entities/coordinates.dart';
import 'package:road_companion/features/navigation/domain/entities/access_restriction.dart';
import 'package:road_companion/features/navigation/domain/entities/navigation_issue_report.dart';
import 'package:road_companion/features/navigation/domain/entities/saved_favorite_route.dart';
import 'package:road_companion/features/navigation/domain/services/smart_navigation_memory_service.dart';

void main() {
  group('SmartNavigationMemoryService - Memoria Inteligente Local', () {
    late SmartNavigationMemoryService memoryService;

    setUp(() {
      // Instancia puramente en memoria para pruebas rápidas
      memoryService = SmartNavigationMemoryService();
    });

    test('1. Guarda, consulta ordenado por fecha y elimina rutas favoritas', () async {
      final r1 = SavedFavoriteRoute(
        id: 'fav_1',
        title: 'Pereira a Guadalupe',
        origin: Coordinates(4.8133, -75.6961),
        originTitle: 'Centro Pereira',
        destination: Coordinates(4.833360, -75.672461),
        destinationTitle: 'Barrio Guadalupe',
        savedAt: DateTime(2026, 10, 20, 10, 0),
        distanceKm: 6.8,
        estimatedDuration: const Duration(minutes: 18),
        notes: 'Entrada por Variante La Romelia',
      );

      final r2 = SavedFavoriteRoute(
        id: 'fav_2',
        title: 'Pereira a Salento',
        origin: Coordinates(4.8133, -75.6961),
        originTitle: 'Centro Pereira',
        destination: Coordinates(4.6375, -75.5708),
        destinationTitle: 'Plaza de Salento',
        savedAt: DateTime(2026, 10, 21, 14, 30),
        distanceKm: 34.2,
        estimatedDuration: const Duration(minutes: 55),
        notes: 'Autopista del Café',
      );

      await memoryService.saveFavoriteRoute(r1);
      await memoryService.saveFavoriteRoute(r2);

      final favorites = memoryService.favoriteRoutes;
      expect(favorites.length, equals(2));
      // Más reciente primero (r2)
      expect(favorites.first.id, equals('fav_2'));
      expect(favorites.last.id, equals('fav_1'));

      // Eliminar fav_1
      await memoryService.deleteFavoriteRoute('fav_1');
      expect(memoryService.favoriteRoutes.length, equals(1));
      expect(memoryService.favoriteRoutes.first.id, equals('fav_2'));
    });

    test('2. Guarda reportes de incidencias viales y evita duplicados en < 25m', () async {
      final rep1 = NavigationIssueReport(
        id: 'rep_1',
        location: Coordinates(4.833360, -75.672461),
        type: NavigationIssueType.lockedGate,
        description: 'Portón cerrado con candado en acceso privado',
        reportedAt: DateTime.now(),
        status: ReportVerificationStatus.confirmed,
      );

      final rep2Duplicate = NavigationIssueReport(
        id: 'rep_2',
        // Misma coordenada aproximada (1 metro de diferencia)
        location: Coordinates(4.833365, -75.672465),
        type: NavigationIssueType.lockedGate,
        description: 'Reiteración de portón',
        reportedAt: DateTime.now(),
        status: ReportVerificationStatus.confirmed,
      );

      await memoryService.addReport(rep1);
      expect(memoryService.reports.length, equals(1));

      // Al agregar el duplicado en < 25m, sustituye la anterior
      await memoryService.addReport(rep2Duplicate);
      expect(memoryService.reports.length, equals(1));
      expect(memoryService.reports.first.id, equals('rep_2'));
    });

    test('3. Sincroniza reportes confirmados de portón con el registro de restricciones viales', () {
      final registry = RoadAccessRestrictionRegistry();
      expect(registry.allRecords.length, equals(1)); // Guadalupe inicial

      final gateReport = NavigationIssueReport(
        id: 'gate_test_1',
        location: Coordinates(4.8500, -75.6500),
        type: NavigationIssueType.lockedGate,
        description: 'Cerrojo metálico vereda La Florida',
        reportedAt: DateTime.now(),
        status: ReportVerificationStatus.confirmed,
      );

      final unconfirmedReport = NavigationIssueReport(
        id: 'gate_test_2',
        location: Coordinates(4.8600, -75.6600),
        type: NavigationIssueType.lockedGate,
        description: 'Posible cerrojo no verificado',
        reportedAt: DateTime.now(),
        status: ReportVerificationStatus.unconfirmed,
      );

      memoryService.addReport(gateReport);
      memoryService.addReport(unconfirmedReport);

      // Sincronizar con el registro territorial
      memoryService.syncWithRestrictionRegistry(registry);

      // Solo el reporte confirmado debe agregarse como restricción activa
      expect(registry.allRecords.length, equals(2));
      final addedRecord = registry.allRecords.firstWhere((r) => r.id == 'user_report_gate_test_1');
      expect(addedRecord.type, equals(AccessRestrictionType.lockedGate));
      expect(addedRecord.description, contains('Cerrojo metálico vereda La Florida'));
    });

    test('4. Detecta incidencias viales a lo largo de una geometría vial calculada', () {
      final gateLocation = Coordinates(4.833360, -75.672461);
      final rep = NavigationIssueReport(
        id: 'rep_on_route',
        location: gateLocation,
        type: NavigationIssueType.unexpectedUnpaved,
        description: 'Tramo con gravilla suelta y baches',
        reportedAt: DateTime.now(),
        status: ReportVerificationStatus.unconfirmed,
      );
      memoryService.addReport(rep);

      // Geometría que pasa a 10 metros del reporte
      final routeGeometry = [
        Coordinates(4.833000, -75.672400),
        Coordinates(4.833355, -75.672455),
        Coordinates(4.833700, -75.672500),
      ];

      final matches = memoryService.checkReportsAlongRoute(routeGeometry);
      expect(matches.length, equals(1));
      expect(matches.first.id, equals('rep_on_route'));

      // Geometría lejana no debe coincidir
      final farGeometry = [
        Coordinates(5.0000, -75.0000),
        Coordinates(5.0010, -75.0010),
      ];
      final noMatches = memoryService.checkReportsAlongRoute(farGeometry);
      expect(noMatches, isEmpty);
    });
  });
}
