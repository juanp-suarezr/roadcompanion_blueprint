import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_companion/app/theme/app_theme.dart';
import 'package:road_companion/domain/entities/coordinates.dart';
import 'package:road_companion/domain/entities/maneuver.dart';
import 'package:road_companion/domain/entities/maneuver_type.dart';
import 'package:road_companion/domain/entities/route_plan.dart';
import 'package:road_companion/features/navigation/domain/entities/calculated_route.dart';
import 'package:road_companion/features/navigation/domain/entities/destination.dart';
import 'package:road_companion/features/navigation/domain/entities/gps_position.dart';
import 'package:road_companion/features/navigation/domain/entities/navigation_session.dart';
import 'package:road_companion/features/navigation/domain/repositories/session_repository.dart';
import 'package:road_companion/features/navigation/domain/services/geocoding_service.dart';
import 'package:road_companion/features/navigation/domain/services/location_service.dart';
import 'package:road_companion/features/navigation/domain/services/route_integrity_validator.dart';
import 'package:road_companion/features/navigation/domain/services/routing_service.dart';
import 'package:road_companion/features/navigation/presentation/navigation_screen.dart';
import 'package:road_companion/features/navigation/presentation/state/imported_route_state.dart';
import 'package:road_companion/features/navigation/presentation/widgets/active_turn_by_turn_hud.dart';
import 'package:road_companion/features/navigation/presentation/widgets/real_map_widget.dart';
import 'package:road_companion/features/navigation/presentation/widgets/route_overview_card.dart';

class MockGeocodingService implements GeocodingService {
  final List<Destination> returnList;
  MockGeocodingService(this.returnList);

  @override
  Future<List<Destination>> search(
    String query, {
    Coordinates? proximityHint,
    int limit = 10,
  }) async {
    return returnList;
  }

  @override
  Future<List<Destination>> searchNearbyCategory({
    required String category,
    required Coordinates center,
    int limit = 15,
  }) async {
    return returnList;
  }

  @override
  Future<Destination?> reverseGeocode(Coordinates coordinates) async => null;
}

class MockRoutingService implements RoutingService {
  final CalculatedRoute routeToReturn;
  final List<CalculatedRoute>? routesToReturn;
  MockRoutingService(this.routeToReturn, {this.routesToReturn});

  @override
  Future<CalculatedRoute> calculateRoute({
    required Coordinates origin,
    required Coordinates destination,
  }) async {
    return routeToReturn;
  }

  @override
  Future<List<CalculatedRoute>> calculateRoutesWithAlternatives({
    required Coordinates origin,
    required Coordinates destination,
  }) async {
    return routesToReturn ?? [routeToReturn];
  }
}

class MockMapLocationService implements LocationService {
  final StreamController<GpsPosition> _controller =
      StreamController<GpsPosition>.broadcast();
  void emit(GpsPosition pos) => _controller.add(pos);

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermissionResult> checkPermission() async =>
      LocationPermissionResult.granted;

  @override
  Future<LocationPermissionResult> requestPermission() async =>
      LocationPermissionResult.granted;

  @override
  Future<bool> checkBackgroundPermission() async => true;

  @override
  Future<LocationPermissionResult> requestBackgroundPermission() async =>
      LocationPermissionResult.granted;

  @override
  Stream<GpsPosition> getPositionStream({
    int distanceFilterMeters = 2,
    int intervalDurationMs = 1000,
    bool enableBackgroundNotification = false,
    String? notificationTitle,
    String? notificationText,
  }) => _controller.stream;

  void dispose() => _controller.close();
}

class MockMapSessionRepo implements SessionRepository {
  final List<NavigationSession> sessions = [];

  @override
  Future<List<NavigationSession>> getSessions() async => sessions;

  @override
  Future<void> saveSession(NavigationSession session) async =>
      sessions.add(session);

  @override
  Future<void> deleteSession(String id) async =>
      sessions.removeWhere((s) => s.id == id);
}

void main() {
  late MockMapLocationService mockLocationService;
  late MockMapSessionRepo mockSessionRepo;
  late MockGeocodingService mockGeocodingService;
  late MockRoutingService mockRoutingService;

  final sampleDestination = Destination(
    id: '123',
    title: 'Nevado del Ruiz',
    subtitle: 'Villamaría, Caldas, Colombia',
    coordinates: Coordinates(4.895, -75.322),
  );

  final sampleRoute = CalculatedRoute(
    routePlan: RoutePlan(
      origin: Coordinates(5.068, -75.517),
      destination: Coordinates(4.895, -75.322),
      estimatedDuration: const Duration(hours: 1, minutes: 25),
      geometry: [
        Coordinates(5.068, -75.517),
        Coordinates(4.980, -75.410),
        Coordinates(4.895, -75.322),
      ],
      totalDistanceMeters: 48200.0,
      maneuvers: [
        Maneuver(
          instructionText: 'Inicia por Vía al Nevado',
          type: ManeuverType.depart,
          location: Coordinates(5.068, -75.517),
          distanceMeters: 12000.0,
        ),
        Maneuver(
          instructionText: 'Gira a la derecha hacia Refugio Brisas',
          type: ManeuverType.right,
          location: Coordinates(4.980, -75.410),
          distanceMeters: 36200.0,
        ),
        Maneuver(
          instructionText: 'Llegada al Nevado del Ruiz',
          type: ManeuverType.arrive,
          location: Coordinates(4.895, -75.322),
          distanceMeters: 0.0,
        ),
      ],
    ),
    summary: 'por Vía al Nevado',
  );

  setUp(() {
    mockLocationService = MockMapLocationService();
    mockSessionRepo = MockMapSessionRepo();
    mockGeocodingService = MockGeocodingService([sampleDestination]);
    mockRoutingService = MockRoutingService(sampleRoute);
  });

  tearDown(() {
    mockLocationService.dispose();
  });

  testWidgets(
    'Flujo completo de búsqueda de destino, cálculo de ruta vial e inicio de navegación en mapa real',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: ImportedRouteScope(
            routeState: ImportedRouteState(),
            child: NavigationScreen(
              locationService: mockLocationService,
              sessionRepository: mockSessionRepo,
              geocodingService: mockGeocodingService,
              routingService: mockRoutingService,
              initialMode: NavigationScreenMode.realMap,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Verificar presencia del mapa real, atribución de datos abiertos y barra de búsqueda
      expect(find.byType(RealMapWidget), findsOneWidget);
      expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
      expect(find.text('Buscar destino o municipio...'), findsOneWidget);

      // 2. Abrir barra de búsqueda
      await tester.tap(find.text('Buscar destino o municipio...'));
      await tester.pumpAndSettle();

      // Escribir en el campo de búsqueda
      await tester.enterText(find.byType(TextField), 'Nevado');
      await tester.pump(const Duration(milliseconds: 600)); // Esperar debounce
      await tester.pumpAndSettle();

      // Verificar que el resultado de búsqueda se visualiza
      expect(find.text('Nevado del Ruiz'), findsOneWidget);

      // 3. Seleccionar el destino
      await tester.tap(find.text('Nevado del Ruiz'));
      await tester.pumpAndSettle();

      // Verificar que se calculó la ruta y se despliega la tarjeta de resumen
      expect(find.byType(RouteOverviewCard), findsOneWidget);
      expect(find.text('48.2 km'), findsOneWidget);
      expect(find.text('1 h 25 min'), findsOneWidget);
      expect(find.text('por Vía al Nevado'), findsOneWidget);
      expect(find.text('INICIAR NAVEGACIÓN'), findsOneWidget);

      // 4. Iniciar navegación activa
      await tester.tap(find.text('INICIAR NAVEGACIÓN'));
      await tester.pump();

      // Emitir posición GPS
      mockLocationService.emit(
        GpsPosition(
          coordinates: Coordinates(5.068, -75.517),
          accuracyMeters: 5.0,
          speedMps: 18.0, // 64.8 km/h
          timestamp: DateTime.now(),
        ),
      );
      await tester.pumpAndSettle();

      // Verificar que se activa el HUD de giro a giro sobre el mapa
      expect(find.byType(ActiveTurnByTurnHud), findsOneWidget);
      expect(find.text('65'), findsOneWidget); // 64.8 km/h redondeado
      expect(find.text('km/h'), findsOneWidget);
      expect(find.text('Pausar'), findsOneWidget);
      expect(find.text('Finalizar'), findsOneWidget);

      // 5. Finalizar navegación
      await tester.tap(
        find.descendant(
          of: find.byType(ActiveTurnByTurnHud),
          matching: find.text('Finalizar'),
        ),
      );
      await tester.pumpAndSettle();

      // Diálogo de confirmación
      expect(find.text('¿Finalizar navegación?'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Finalizar'),
        ),
      );
      await tester.pumpAndSettle();

      // Verificar que la sesión se guardó en el repositorio
      expect(mockSessionRepo.sessions.length, equals(1));
    },
  );

  testWidgets(
    'Permite alternar entre rutas alternativas y navegar con la alternativa seleccionada',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final route1 = sampleRoute.copyWith(
        routeName: 'Ruta 1',
        isFastest: true,
        summary: 'por Vía al Nevado Principal',
      );

      final route2 = CalculatedRoute(
        routeName: 'Ruta 2',
        summary: 'por Paso Letras Alterno',
        isShortest: true,
        distanceDiffKm: null,
        durationDiff: const Duration(minutes: 15),
        routePlan: RoutePlan(
          origin: Coordinates(5.068, -75.517),
          destination: Coordinates(4.895, -75.322),
          estimatedDuration: const Duration(hours: 1, minutes: 40),
          geometry: [
            Coordinates(5.068, -75.517),
            Coordinates(5.010, -75.450),
            Coordinates(4.895, -75.322),
          ],
          totalDistanceMeters: 41500.0,
          maneuvers: [
            Maneuver(
              instructionText: 'Inicia por Letras Alterno',
              type: ManeuverType.depart,
              location: Coordinates(5.068, -75.517),
              distanceMeters: 10000.0,
            ),
            Maneuver(
              instructionText: 'Llegada al destino',
              type: ManeuverType.arrive,
              location: Coordinates(4.895, -75.322),
              distanceMeters: 0.0,
            ),
          ],
        ),
      );

      final multiRouteService = MockRoutingService(
        route1,
        routesToReturn: [route1, route2],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: ImportedRouteScope(
            routeState: ImportedRouteState(),
            child: NavigationScreen(
              locationService: mockLocationService,
              sessionRepository: mockSessionRepo,
              geocodingService: mockGeocodingService,
              routingService: multiRouteService,
              initialMode: NavigationScreenMode.realMap,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Abrir búsqueda y seleccionar destino
      await tester.tap(find.text('Buscar destino o municipio...'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Nevado');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nevado del Ruiz'));
      await tester.pumpAndSettle();

      // Verificar que se listan ambas rutas disponibles
      expect(find.text('RUTAS DISPONIBLES (2)'), findsOneWidget);
      expect(find.text('Ruta 1'), findsOneWidget);
      expect(find.text('Ruta 2'), findsOneWidget);
      expect(find.text('por Vía al Nevado Principal'), findsOneWidget);
      expect(find.text('INICIAR RUTA 1'), findsOneWidget);

      // Tocar en "Ruta 2" para seleccionarla
      await tester.tap(find.text('Ruta 2'));
      await tester.pumpAndSettle();

      // Verificar que ahora se muestra la información de la Ruta 2
      expect(find.text('por Paso Letras Alterno'), findsOneWidget);
      expect(find.text('41.5 km'), findsOneWidget);
      expect(find.text('1 h 40 min'), findsOneWidget);
      expect(find.text('INICIAR RUTA 2'), findsOneWidget);

      // Iniciar navegación con la Ruta 2 seleccionada
      await tester.tap(find.text('INICIAR RUTA 2'));
      await tester.pump();

      // Emitir ubicación GPS
      mockLocationService.emit(
        GpsPosition(
          coordinates: Coordinates(5.068, -75.517),
          accuracyMeters: 5.0,
          speedMps: 15.0,
          timestamp: DateTime.now(),
        ),
      );
      await tester.pumpAndSettle();

      // Verificar que el HUD activo se encendió
      expect(find.byType(ActiveTurnByTurnHud), findsOneWidget);
    },
  );

  testWidgets(
    'Muestra advertencia explícita de cerrojo/acceso restringido y distintivo PRIVADA en la interfaz',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final restrictedRoute = sampleRoute.copyWith(
        routeName: 'Ruta 1',
        validation: const RouteValidationResult(
          status: RouteValidationStatus.confirmedRestrictedAccess,
          hasRestrictedAccess: true,
          warnings: [
            'Acceso restringido o vía privada confirmada (barrier=gate (portón/cerrojo)). Esta vía no está disponible para libre tránsito público.',
          ],
        ),
      );

      final restrictedRoutingService = MockRoutingService(
        restrictedRoute,
        routesToReturn: [restrictedRoute],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: ImportedRouteScope(
            routeState: ImportedRouteState(),
            child: NavigationScreen(
              locationService: mockLocationService,
              sessionRepository: mockSessionRepo,
              geocodingService: mockGeocodingService,
              routingService: restrictedRoutingService,
              initialMode: NavigationScreenMode.realMap,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Buscar destino o municipio...'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Nevado');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nevado del Ruiz'));
      await tester.pumpAndSettle();

      // Verificar que aparece el mensaje de advertencia de acceso restringido
      expect(find.text('Acceso restringido / Vía privada con cerrojo'), findsOneWidget);
      expect(
        find.textContaining('Acceso restringido o vía privada confirmada'),
        findsOneWidget,
      );
      expect(find.text('INICIAR RUTA (ACCESO RESTRINGIDO)'), findsOneWidget);
    },
  );
}
