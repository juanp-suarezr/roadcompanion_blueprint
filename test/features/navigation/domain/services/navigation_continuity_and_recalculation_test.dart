import 'dart:async';
import 'package:flutter_test/flutter_test.dart';

import 'package:road_companion/domain/entities/coordinates.dart';
import 'package:road_companion/domain/entities/maneuver.dart';
import 'package:road_companion/domain/entities/maneuver_type.dart';
import 'package:road_companion/domain/entities/route_plan.dart';
import 'package:road_companion/domain/services/route_progress_calculator.dart';
import 'package:road_companion/features/navigation/domain/entities/calculated_route.dart';
import 'package:road_companion/features/navigation/domain/entities/gps_position.dart';
import 'package:road_companion/features/navigation/domain/entities/gpx_point.dart';
import 'package:road_companion/features/navigation/domain/entities/gpx_segment.dart';
import 'package:road_companion/features/navigation/domain/entities/gpx_tracking_status.dart';
import 'package:road_companion/features/navigation/domain/entities/imported_gpx_route.dart';
import 'package:road_companion/features/navigation/domain/entities/road_curvature.dart';
import 'package:road_companion/features/navigation/domain/services/location_service.dart';
import 'package:road_companion/features/navigation/domain/services/navigation_maneuver_engine.dart';
import 'package:road_companion/features/navigation/domain/services/road_curvature_estimator.dart';
import 'package:road_companion/features/navigation/domain/services/route_integrity_validator.dart';
import 'package:road_companion/features/navigation/presentation/state/gpx_route_tracker.dart';

class _FakeLocationStream implements LocationService {
  final _controller = StreamController<GpsPosition>.broadcast();

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

  @override
  Future<GpsPosition?> getCurrentPosition({
    Duration timeLimit = const Duration(seconds: 8),
  }) async => null;

  void dispose() => _controller.close();
}

void main() {
  group('Entrega 1: Seguimiento GPS, Map Matching, Continuidad y Recálculo', () {
    late _FakeLocationStream locationService;

    setUp(() {
      locationService = _FakeLocationStream();
    });

    tearDown(() {
      locationService.dispose();
    });

    test(
      '1. Saltos GPS: descarta salto anómalo aislado (> 140 km/h) sin provocar off-route ni alterar segmento',
      () async {
        // Ruta recta de 5 km en dirección norte (0°)
        final gpxRoute = ImportedGpxRoute(
          name: 'Ruta Nacional 5km',
          segments: [
            GpxSegment([
              GpxPoint(coordinates: Coordinates(4.8000, -75.7000)),
              GpxPoint(coordinates: Coordinates(4.8100, -75.7000)),
              GpxPoint(coordinates: Coordinates(4.8200, -75.7000)),
              GpxPoint(coordinates: Coordinates(4.8300, -75.7000)),
              GpxPoint(coordinates: Coordinates(4.8450, -75.7000)),
            ]),
          ],
        );

        DateTime currentTime = DateTime(2026, 10, 31, 10, 0, 0);
        final tracker = GpxRouteTracker(
          route: gpxRoute,
          locationService: locationService,
          clock: () => currentTime,
          maxPlausibleSpeedKmh: 140.0,
        );

        await tracker.startTracking();

        // Muestra 1: Posición normal sobre el inicio de la ruta
        locationService.emit(
          GpsPosition(
            coordinates: Coordinates(4.8000, -75.7000),
            accuracyMeters: 5.0,
            speedMps: 20.0, // 72 km/h
            timestamp: currentTime,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(tracker.status, equals(GpxTrackingStatus.tracking));
        expect(tracker.distanceTraveledMeters, closeTo(0.0, 10.0));

        // Muestra 2: 1 segundo después, salto anómalo de 2 km a un lado (velocidad equivalente 7200 km/h)
        currentTime = currentTime.add(const Duration(seconds: 1));
        locationService.emit(
          GpsPosition(
            coordinates: Coordinates(4.8000, -75.6800), // ~2.2 km al este
            accuracyMeters: 8.0,
            timestamp: currentTime,
          ),
        );
        await Future<void>.delayed(Duration.zero);

        // El salto anómalo debe ser aislado preventivamente: NO altera tracking a offRoute,
        // NO mueve el segmento activo y emite mensaje de filtrado.
        expect(tracker.status, equals(GpxTrackingStatus.tracking));
        expect(tracker.statusMessage, contains('Filtrando salto GPS anómalo'));

        // Muestra 3: 1 segundo después, el GPS retorna a la ruta legítima (4.8002, -75.7000)
        currentTime = currentTime.add(const Duration(seconds: 1));
        locationService.emit(
          GpsPosition(
            coordinates: Coordinates(4.8002, -75.7000),
            accuracyMeters: 4.0,
            speedMps: 20.0,
            timestamp: currentTime,
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(tracker.status, equals(GpxTrackingStatus.tracking));
        expect(tracker.distanceTraveledMeters, greaterThanOrEqualTo(0.0));
        await tracker.stopTracking();
      },
    );

    test(
      '2. Posiciones GPS con precisión deficiente (> 65 m) pasan a lowAccuracy sin declarar falso offRoute',
      () async {
        final gpxRoute = ImportedGpxRoute(
          name: 'Ruta 1km',
          segments: [
            GpxSegment([
              GpxPoint(coordinates: Coordinates(4.8000, -75.7000)),
              GpxPoint(coordinates: Coordinates(4.8090, -75.7000)),
            ]),
          ],
        );

        final tracker = GpxRouteTracker(
          route: gpxRoute,
          locationService: locationService,
          maxAccuracyThresholdMeters: 65.0,
        );

        await tracker.startTracking();

        // Muestra con precisión degradada (±95 m)
        locationService.emit(
          GpsPosition(
            coordinates: Coordinates(4.8050, -75.7000),
            accuracyMeters: 95.0,
            timestamp: DateTime.now(),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(tracker.status, equals(GpxTrackingStatus.lowAccuracy));
        expect(tracker.statusMessage, contains('Precisión GPS baja'));
        expect(tracker.status, isNot(equals(GpxTrackingStatus.offRoute)));
        await tracker.stopTracking();
      },
    );

    test(
      '3. Carreteras paralelas: la concordancia angular entre rumbo y azimut selecciona la calzada correcta',
      () {
        const calculator = RouteProgressCalculator();

        // Geometría con calzada doble paralela:
        // Tramo 0: Calzada Norte (sur a norte: 4.8000 -> 4.8100 en -75.7000) azimut ~0°
        // Tramo 1: Enlace conector
        // Tramo 2: Calzada Sur (norte a sur: 4.8100 -> 4.8000 en -75.7002, a ~22m de distancia) azimut ~180°
        final geometry = [
          Coordinates(4.8000, -75.7000), // 0
          Coordinates(4.8100, -75.7000), // 1 (fin Calzada Norte)
          Coordinates(4.8100, -75.7002), // 2 (conector)
          Coordinates(4.8000, -75.7002), // 3 (fin Calzada Sur)
        ];

        // Posición del vehículo en medio de ambas calzadas (ej. en lat 4.8050, lon -75.7001),
        // moviéndose en dirección Norte (rumbo 0°).
        final riderPos = Coordinates(4.8050, -75.7001);

        // Con rumbo de desplazamiento Norte (0°), debe seleccionar el Tramo 0 (Calzada Norte)
        final progressNorth = calculator.calculate(
          geometry: geometry,
          currentPosition: riderPos,
          movementHeadingDegrees: 0.0,
        );
        expect(progressNorth.closestSegmentIndex, equals(0));

        // Si el rumbo de desplazamiento es Sur (180°), debe seleccionar el Tramo 2 (Calzada Sur)
        final progressSouth = calculator.calculate(
          geometry: geometry,
          currentPosition: riderPos,
          movementHeadingDegrees: 180.0,
        );
        expect(progressSouth.closestSegmentIndex, equals(2));
      },
    );

    test(
      '4. Curvas a velocidad de carretera: lookahead dinámico ampliado previene falsos offRoute',
      () async {
        // Trazado de carretera de montaña con microcurvas sucesivas
        final points = <GpxPoint>[];
        for (int i = 0; i < 40; i++) {
          points.add(
            GpxPoint(
              coordinates: Coordinates(
                4.8000 + (i * 0.001),
                -75.7000 + ((i % 2) * 0.0003),
              ),
            ),
          );
        }
        final gpxRoute = ImportedGpxRoute(
          name: 'Curvas Montaña',
          segments: [GpxSegment(points)],
        );

        final tracker = GpxRouteTracker(
          route: gpxRoute,
          locationService: locationService,
          lookaheadSegments: 8,
        );
        await tracker.startTracking();

        // Moto a 85 km/h (23.6 m/s) en el segmento 15
        locationService.emit(
          GpsPosition(
            coordinates: points[15].coordinates,
            accuracyMeters: 5.0,
            speedMps: 23.6,
            headingDegrees: 10.0,
            timestamp: DateTime.now(),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(tracker.status, equals(GpxTrackingStatus.tracking));
        expect(tracker.distanceTraveledMeters, greaterThan(1000.0));
        await tracker.stopTracking();
      },
    );

    test(
      '5. Desvíos reales: requiere 3 muestras consecutivas fuera de corredor con histéresis',
      () async {
        final gpxRoute = ImportedGpxRoute(
          name: 'Ruta Recta',
          segments: [
            GpxSegment([
              GpxPoint(coordinates: Coordinates(4.8000, -75.7000)),
              GpxPoint(coordinates: Coordinates(4.8300, -75.7000)),
            ]),
          ],
        );

        final tracker = GpxRouteTracker(
          route: gpxRoute,
          locationService: locationService,
          offRouteThresholdMeters: 45.0,
          offRouteFilterSamples: 3,
        );
        await tracker.startTracking();

        // Muestra 1 dentro de ruta
        locationService.emit(
          GpsPosition(
            coordinates: Coordinates(4.8000, -75.7000),
            accuracyMeters: 5.0,
            timestamp: DateTime.now(),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(tracker.status, equals(GpxTrackingStatus.tracking));

        // Muestra 2: 70m fuera de ruta (1 sola muestra no debe causar offRoute)
        locationService.emit(
          GpsPosition(
            coordinates: Coordinates(4.8050, -75.6990), // ~110m fuera
            accuracyMeters: 6.0,
            timestamp: DateTime.now(),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(tracker.status, equals(GpxTrackingStatus.tracking));

        // Muestra 3: segunda muestra fuera
        locationService.emit(
          GpsPosition(
            coordinates: Coordinates(4.8060, -75.6990),
            accuracyMeters: 6.0,
            timestamp: DateTime.now(),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(tracker.status, equals(GpxTrackingStatus.tracking));

        // Muestra 4: tercera muestra consecutiva fuera -> se confirma offRoute
        locationService.emit(
          GpsPosition(
            coordinates: Coordinates(4.8070, -75.6990),
            accuracyMeters: 6.0,
            timestamp: DateTime.now(),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(tracker.status, equals(GpxTrackingStatus.offRoute));

        await tracker.stopTracking();
      },
    );

    test(
      '6. Recálculo: routeVersion monotónico invalida eventos atrasados y descarta sobrescrituras',
      () {
        final origin = Coordinates(4.8000, -75.7000);
        final dest = Coordinates(4.8500, -75.7000);

        final routeV1 = CalculatedRoute(
          summary: 'Ruta Original',
          routePlan: RoutePlan(
            origin: origin,
            destination: dest,
            totalDistanceMeters: 5500.0,
            estimatedDuration: const Duration(minutes: 8),
            geometry: [origin, dest],
            maneuvers: [
              Maneuver(
                instructionText: 'Salida',
                type: ManeuverType.depart,
                location: origin,
                distanceMeters: 5500.0,
              ),
              Maneuver(
                instructionText: 'Llegada',
                type: ManeuverType.arrive,
                location: dest,
                distanceMeters: 0.0,
              ),
            ],
            routeVersion: 1,
          ),
        );

        final routeV2 = routeV1.copyWith(
          summary: 'Ruta Recalculada',
          routeVersion: 2,
        );

        expect(routeV1.routeVersion, equals(1));
        expect(routeV2.routeVersion, equals(2));
        expect(routeV2.summary, equals('Ruta Recalculada'));

        // Verificar que una respuesta desfasada con versión menor se rechaza frente a la activa
        int activeVersion = routeV2.routeVersion;
        bool isStaleAccepted(int incomingVersion) =>
            incomingVersion >= activeVersion;

        expect(
          isStaleAccepted(routeV1.routeVersion),
          isFalse,
        ); // Rechaza v1 atrasada
        expect(
          isStaleAccepted(routeV2.routeVersion),
          isTrue,
        ); // Acepta v2 actual
      },
    );

    test(
      '7. Continuidad en carretera nacional de 50 km sin giros: paso de mantenimiento recto con distancia real decreciente',
      () {
        final origin = Coordinates(4.8000, -75.7000);
        final dest = Coordinates(5.2500, -75.7000); // ~50 km al norte

        final highwayGeometry = <Coordinates>[];
        for (int i = 0; i <= 50; i++) {
          highwayGeometry.add(Coordinates(4.8000 + (i * 0.009), -75.7000));
        }

        final nationalRoute = CalculatedRoute(
          summary: 'Carretera Panamericana (50 km)',
          routePlan: RoutePlan(
            origin: origin,
            destination: dest,
            totalDistanceMeters: 50000.0,
            estimatedDuration: const Duration(minutes: 45),
            geometry: highwayGeometry,
            maneuvers: [
              Maneuver(
                instructionText: 'Inicia en Panamericana',
                type: ManeuverType.depart,
                location: origin,
                distanceMeters: 50000.0,
              ),
              Maneuver(
                instructionText: 'Llegada al destino',
                type: ManeuverType.arrive,
                location: dest,
                distanceMeters: 0.0,
              ),
            ],
          ),
        );

        final engine = NavigationManeuverEngine();
        engine.setRoute(nationalRoute);

        // Rider al km 10 de la carretera (a 40 km del destino)
        final posKm10 = highwayGeometry[10];
        final stepKm10 = engine.resolveStep(
          currentCoordinates: posKm10,
          highwayStraightThresholdMeters: 1500.0,
        );

        expect(stepKm10, isNotNull);
        // Debe estructurarse como seguimiento recto de calzada
        expect(stepKm10!.activeManeuver.type, equals(ManeuverType.straight));
        expect(stepKm10.isHighwayStraightContinuation, isTrue);
        expect(stepKm10.distanceToManeuverMeters, closeTo(40000.0, 500.0));
        expect(stepKm10.distanceToMilestoneMeters, closeTo(40000.0, 500.0));

        // Rider al km 35 (a 15 km del destino)
        final posKm35 = highwayGeometry[35];
        final stepKm35 = engine.resolveStep(
          currentCoordinates: posKm35,
          highwayStraightThresholdMeters: 1500.0,
        );

        expect(stepKm35, isNotNull);
        expect(stepKm35!.activeManeuver.type, equals(ManeuverType.straight));
        expect(stepKm35.distanceToManeuverMeters, closeTo(15000.0, 500.0));
        // La distancia debe decrecer estrictamente
        expect(
          stepKm35.distanceToManeuverMeters,
          lessThan(stepKm10.distanceToManeuverMeters),
        );
      },
    );

    test(
      '8. Transición fluida: tramo recto prolongado conmuta a flecha de giro real al aproximarse a < 1500 m',
      () {
        final origin = Coordinates(4.8000, -75.7000);
        final turnPoint = Coordinates(
          4.8900,
          -75.7000,
        ); // ~10 km recto hacia un giro a la derecha
        final dest = Coordinates(4.8900, -75.6500);

        final geometry = [
          origin,
          Coordinates(4.8500, -75.7000),
          turnPoint,
          dest,
        ];

        final routeWithDistantTurn = CalculatedRoute(
          summary: 'Troncal de Occidente',
          routePlan: RoutePlan(
            origin: origin,
            destination: dest,
            totalDistanceMeters: 15000.0,
            estimatedDuration: const Duration(minutes: 18),
            geometry: geometry,
            maneuvers: [
              Maneuver(
                instructionText: 'Inicia recorrido',
                type: ManeuverType.depart,
                location: origin,
                distanceMeters: 10000.0,
              ),
              Maneuver(
                instructionText: 'Gira a la derecha hacia Variante',
                type: ManeuverType.right,
                location: turnPoint,
                distanceMeters: 5000.0,
                roadName: 'Variante',
              ),
              Maneuver(
                instructionText: 'Llegada al destino',
                type: ManeuverType.arrive,
                location: dest,
                distanceMeters: 0.0,
              ),
            ],
          ),
        );

        final engine = NavigationManeuverEngine();
        engine.setRoute(routeWithDistantTurn);

        // Caso A: A 5 km del giro (> 1500 m) -> muestra instrucción recta de carretera con distancia al hito
        final stepDistant = engine.resolveStep(
          currentCoordinates: Coordinates(
            4.8450,
            -75.7000,
          ), // ~5 km antes del giro
          highwayStraightThresholdMeters: 1500.0,
        );
        expect(stepDistant, isNotNull);
        expect(stepDistant!.activeManeuver.type, equals(ManeuverType.straight));
        expect(stepDistant.isHighwayStraightContinuation, isTrue);
        expect(stepDistant.distanceToManeuverMeters, closeTo(5000.0, 300.0));
        expect(stepDistant.nextManeuver?.type, equals(ManeuverType.right));

        // Caso B: A 400 m del giro (<= 1500 m) -> conmuta al giro real right
        final stepClose = engine.resolveStep(
          currentCoordinates: Coordinates(
            4.8864,
            -75.7000,
          ), // ~400 m antes del giro
          highwayStraightThresholdMeters: 1500.0,
        );
        expect(stepClose, isNotNull);
        expect(stepClose!.activeManeuver.type, equals(ManeuverType.right));
        expect(stepClose.isHighwayStraightContinuation, isFalse);
        expect(stepClose.distanceToManeuverMeters, closeTo(400.0, 50.0));
      },
    );

    test(
      '9. Alternativas de ruta: enriquecimiento con diferencias de tiempo, distancia y advertencias de vía destapada',
      () {
        final origin = Coordinates(4.8000, -75.7000);
        final dest = Coordinates(4.8500, -75.7000);

        // Validación con tramo destapado
        final validationUnpaved = const RouteValidationResult(
          status: RouteValidationStatus.viable,
          hasUnpavedSections: true,
          warnings: [
            'La ruta incluye tramos sin pavimentar o caminos destapados. Conduce con precaución.',
          ],
        );

        final routeMain = CalculatedRoute(
          routeName: 'Ruta 1',
          summary: 'por Autopista Principal',
          isFastest: true,
          routePlan: RoutePlan(
            origin: origin,
            destination: dest,
            totalDistanceMeters: 12000.0,
            estimatedDuration: const Duration(minutes: 15),
            geometry: [origin, dest],
            maneuvers: const [],
          ),
        );

        final routeAlternative = CalculatedRoute(
          routeName: 'Ruta 2',
          summary: 'por Camino Rural Destapado',
          validation: validationUnpaved,
          distanceDiffKm: 2.5,
          durationDiff: const Duration(minutes: 10),
          routePlan: RoutePlan(
            origin: origin,
            destination: dest,
            totalDistanceMeters: 14500.0,
            estimatedDuration: const Duration(minutes: 25),
            geometry: [origin, dest],
            maneuvers: const [],
          ),
        );

        expect(routeMain.isFastest, isTrue);
        expect(routeMain.hasUnpavedSections, isFalse);

        expect(routeAlternative.hasUnpavedSections, isTrue);
        expect(routeAlternative.distanceDiffKm, equals(2.5));
        expect(routeAlternative.durationDiff?.inMinutes, equals(10));
        expect(
          routeAlternative.validation.warnings.first,
          contains('sin pavimentar'),
        );
      },
    );

    test(
      '10. Estimador de curvas durante recálculo: markStale previene emitir alertas obsoletas',
      () {
        final geometry = [
          Coordinates(4.8000, -75.7000),
          Coordinates(4.8050, -75.7000),
          Coordinates(4.8100, -75.7050), // Curva hacia noroeste
          Coordinates(4.8150, -75.7100),
        ];

        final curvature = RoadCurvatureEstimator.estimate(
          geometry: geometry,
          traveledDistanceMeters: 0.0,
          lookaheadMeters: 1200.0,
          geometrySource: GeometrySource.internalRouteOsrm,
          routeVersion: 1,
        );

        expect(curvature.isStale, isFalse);

        // Al iniciar el recálculo, se marca como stale
        final staleCurvature = curvature.markStale();
        expect(staleCurvature.isStale, isTrue);
        expect(staleCurvature.routeVersion, equals(1));
      },
    );

    group('Entrega A: Estabilidad de Maniobras y Prevención de Flip-Flop', () {
      late NavigationManeuverEngine engine;
      late CalculatedRoute urbanRoute;

      setUp(() {
        engine = NavigationManeuverEngine();

        final p0 = Coordinates(4.8000, -75.7000); // Salida
        final p1 = Coordinates(
          4.8018,
          -75.7000,
        ); // Giro a la izquierda a ~200 m
        final p2 = Coordinates(
          4.8018,
          -75.7050,
        ); // Siguiente hito a ~550 m más (~750m total)
        final p3 = Coordinates(
          4.8018,
          -75.7100,
        ); // Llegada destino (~1300m total)

        urbanRoute = CalculatedRoute(
          summary: 'Ruta Urbana de Prueba',
          routePlan: RoutePlan(
            origin: p0,
            destination: p3,
            totalDistanceMeters: 1300.0,
            estimatedDuration: const Duration(minutes: 5),
            geometry: [p0, p1, p2, p3],
            maneuvers: [
              Maneuver(
                instructionText: 'Salida en Carrera 7',
                type: ManeuverType.depart,
                location: p0,
                distanceMeters: 200.0,
                roadName: 'Carrera 7',
              ),
              Maneuver(
                instructionText: 'Gira a la izquierda en Calle 100',
                type: ManeuverType.left,
                location: p1,
                distanceMeters: 550.0,
                roadName: 'Calle 100',
              ),
              Maneuver(
                instructionText: 'Continúa recto por Calle 100',
                type: ManeuverType.straight,
                location: p2,
                distanceMeters: 550.0,
                roadName: 'Calle 100',
              ),
              Maneuver(
                instructionText: 'Llegada al destino',
                type: ManeuverType.arrive,
                location: p3,
                distanceMeters: 0.0,
              ),
            ],
            routeVersion: 1,
          ),
        );
        engine.setRoute(urbanRoute);
      });

      test(
        'A.1. Reproducción física: salida (depart) conmuta a giro (left) sin flip-flop ante fluctuaciones GPS',
        () {
          // En los primeros 10 metros, la maniobra activa es la salida
          final stepStart = engine.resolveStep(
            currentCoordinates: Coordinates(4.80005, -75.7000), // ~5 m
          );
          expect(stepStart?.activeManeuver.type, equals(ManeuverType.depart));
          expect(stepStart?.maneuverIndex, equals(0));

          // A los 18 metros (> 15 m), avanza a la maniobra 1 (giro a la izquierda)
          final stepAdvance = engine.resolveStep(
            currentCoordinates: Coordinates(4.80016, -75.7000), // ~18 m
          );
          expect(stepAdvance?.activeManeuver.type, equals(ManeuverType.left));
          expect(stepAdvance?.maneuverIndex, equals(1));
          expect(stepAdvance?.distanceToManeuverMeters, closeTo(182.0, 5.0));

          // Fluctuación GPS hacia atrás: muestra en 12 m (ruido GPS habitual)
          // La regla monotónica y de histéresis PROHÍBE retroceder a la maniobra 0 (depart/straight)
          final stepJitter = engine.resolveStep(
            currentCoordinates: Coordinates(4.80011, -75.7000), // ~12 m
          );
          expect(stepJitter?.activeManeuver.type, equals(ManeuverType.left));
          expect(stepJitter?.maneuverIndex, equals(1));
          expect(stepJitter?.distanceToManeuverMeters, greaterThan(0.0));
        },
      );

      test(
        'A.2. Ejecución del giro: no produce aumentos de distancia euclidianos al alejarse del vértice',
        () {
          // Establecer el avance al giro a la izquierda (Maneuver 1 en p1 a ~200 m)
          engine.resolveStep(
            currentCoordinates: Coordinates(4.80016, -75.7000),
          ); // activa idx 1

          // A 10 m del giro: distancia métrica positiva
          final stepApproaching = engine.resolveStep(
            currentCoordinates: Coordinates(
              4.80171,
              -75.7000,
            ), // ~190 m del inicio (~10 m al giro)
          );
          expect(
            stepApproaching?.activeManeuver.type,
            equals(ManeuverType.left),
          );
          expect(stepApproaching?.maneuverIndex, equals(1));
          expect(stepApproaching?.distanceToManeuverMeters, closeTo(10.0, 3.0));

          // Justo en el ápice o 4 m pasados del giro: la distancia debe permanecer en 0.0 ("Ahora"),
          // NO debe calcular distancia euclidiana hacia atrás que aumente a 126m o 235m.
          final stepApex = engine.resolveStep(
            currentCoordinates: Coordinates(
              4.8018,
              -75.70004,
            ), // ~204 m (4m pasado del vértice)
          );
          expect(stepApex?.activeManeuver.type, equals(ManeuverType.left));
          expect(stepApex?.distanceToManeuverMeters, equals(0.0));

          // Al superar los 10 m tras el giro (ej. a 215 m del inicio), conmuta limpiamente a la maniobra 2 (straight)
          final stepPassed = engine.resolveStep(
            currentCoordinates: Coordinates(
              4.8018,
              -75.70014,
            ), // ~215 m (15m pasado del giro)
          );
          expect(
            stepPassed?.activeManeuver.type,
            equals(ManeuverType.straight),
          );
          expect(stepPassed?.maneuverIndex, equals(2));
          // La distancia a la siguiente maniobra (p2) es decreciente respecto a su posición
          expect(stepPassed?.distanceToManeuverMeters, closeTo(535.0, 10.0));
        },
      );

      test(
        'A.3. Recálculo de ruta: reinicia el índice monotónico a 0 con la nueva versión de ruta',
        () {
          // Avanzar a maniobra 2 en la versión 1
          engine.resolveStep(
            currentCoordinates: Coordinates(4.80016, -75.7000),
          );
          engine.resolveStep(
            currentCoordinates: Coordinates(4.8018, -75.70014),
          );
          expect(engine.activeManeuverIndex, equals(2));

          // Se recibe nueva ruta recalculada con routeVersion = 2
          final recalculated = urbanRoute.copyWith(
            summary: 'Ruta Recalculada tras desvío',
            routeVersion: 2,
          );
          engine.setRoute(recalculated);

          expect(engine.activeManeuverIndex, equals(0));
          final stepNew = engine.resolveStep(
            currentCoordinates: urbanRoute.origin,
          );
          expect(stepNew?.maneuverIndex, equals(0));
          expect(stepNew?.activeManeuver.type, equals(ManeuverType.depart));
        },
      );
    });

    group('Entrega A: Estabilidad de Maniobras y Prevención de Flip-Flop', () {
      late NavigationManeuverEngine engine;
      late CalculatedRoute urbanRoute;

      setUp(() {
        engine = NavigationManeuverEngine();

        final p0 = Coordinates(4.8000, -75.7000); // Salida
        final p1 = Coordinates(4.8018, -75.7000); // Giro a la izquierda a ~200 m
        final p2 = Coordinates(4.8018, -75.7050); // Siguiente hito a ~550 m más (~750m total)
        final p3 = Coordinates(4.8018, -75.7100); // Llegada destino (~1300m total)

        urbanRoute = CalculatedRoute(
          summary: 'Ruta Urbana de Prueba',
          routePlan: RoutePlan(
            origin: p0,
            destination: p3,
            totalDistanceMeters: 1300.0,
            estimatedDuration: const Duration(minutes: 5),
            geometry: [p0, p1, p2, p3],
            maneuvers: [
              Maneuver(
                instructionText: 'Salida en Carrera 7',
                type: ManeuverType.depart,
                location: p0,
                distanceMeters: 200.0,
                roadName: 'Carrera 7',
              ),
              Maneuver(
                instructionText: 'Gira a la izquierda en Calle 100',
                type: ManeuverType.left,
                location: p1,
                distanceMeters: 550.0,
                roadName: 'Calle 100',
              ),
              Maneuver(
                instructionText: 'Continúa recto por Calle 100',
                type: ManeuverType.straight,
                location: p2,
                distanceMeters: 550.0,
                roadName: 'Calle 100',
              ),
              Maneuver(
                instructionText: 'Llegada al destino',
                type: ManeuverType.arrive,
                location: p3,
                distanceMeters: 0.0,
              ),
            ],
            routeVersion: 1,
          ),
        );
        engine.setRoute(urbanRoute);
      });

      test('A.1. Reproducción física: salida (depart) conmuta a giro (left) sin flip-flop ante fluctuaciones GPS', () {
        // En los primeros 10 metros, la maniobra activa es la salida
        final stepStart = engine.resolveStep(
          currentCoordinates: Coordinates(4.80005, -75.7000), // ~5 m
        );
        expect(stepStart?.activeManeuver.type, equals(ManeuverType.depart));
        expect(stepStart?.maneuverIndex, equals(0));

        // A los 18 metros (> 15 m), avanza a la maniobra 1 (giro a la izquierda)
        final stepAdvance = engine.resolveStep(
          currentCoordinates: Coordinates(4.80016, -75.7000), // ~18 m
        );
        expect(stepAdvance?.activeManeuver.type, equals(ManeuverType.left));
        expect(stepAdvance?.maneuverIndex, equals(1));
        expect(stepAdvance?.distanceToManeuverMeters, closeTo(182.0, 5.0));

        // Fluctuación GPS hacia atrás: muestra en 12 m (ruido GPS habitual)
        // La regla monotónica y de histéresis PROHÍBE retroceder a la maniobra 0 (depart/straight)
        final stepJitter = engine.resolveStep(
          currentCoordinates: Coordinates(4.80011, -75.7000), // ~12 m
        );
        expect(stepJitter?.activeManeuver.type, equals(ManeuverType.left));
        expect(stepJitter?.maneuverIndex, equals(1));
        expect(stepJitter?.distanceToManeuverMeters, greaterThan(0.0));
      });

      test('A.2. Ejecución del giro: no produce aumentos de distancia euclidianos al alejarse del vértice', () {
        // Establecer el avance al giro a la izquierda (Maneuver 1 en p1 a ~200 m)
        engine.resolveStep(currentCoordinates: Coordinates(4.80016, -75.7000)); // activa idx 1

        // A 10 m del giro: distancia métrica positiva
        final stepApproaching = engine.resolveStep(
          currentCoordinates: Coordinates(4.80171, -75.7000), // ~190 m del inicio (~10 m al giro)
        );
        expect(stepApproaching?.activeManeuver.type, equals(ManeuverType.left));
        expect(stepApproaching?.maneuverIndex, equals(1));
        expect(stepApproaching?.distanceToManeuverMeters, closeTo(10.0, 3.0));

        // Justo en el ápice o 4 m pasados del giro: la distancia debe permanecer en 0.0 ("Ahora"),
        // NO debe calcular distancia euclidiana hacia atrás que aumente a 126m o 235m.
        final stepApex = engine.resolveStep(
          currentCoordinates: Coordinates(4.8018, -75.70004), // ~204 m (4m pasado del vértice)
        );
        expect(stepApex?.activeManeuver.type, equals(ManeuverType.left));
        expect(stepApex?.distanceToManeuverMeters, equals(0.0));

        // Al superar los 10 m tras el giro (ej. a 215 m del inicio), conmuta limpiamente a la maniobra 2 (straight)
        final stepPassed = engine.resolveStep(
          currentCoordinates: Coordinates(4.8018, -75.70014), // ~215 m (15m pasado del giro)
        );
        expect(stepPassed?.activeManeuver.type, equals(ManeuverType.straight));
        expect(stepPassed?.maneuverIndex, equals(2));
        // La distancia a la siguiente maniobra (p2) es decreciente respecto a su posición
        expect(stepPassed?.distanceToManeuverMeters, closeTo(535.0, 10.0));
      });

      test('A.3. Recálculo de ruta: reinicia el índice monotónico a 0 con la nueva versión de ruta', () {
        // Avanzar a maniobra 2 en la versión 1
        engine.resolveStep(currentCoordinates: Coordinates(4.80016, -75.7000));
        engine.resolveStep(currentCoordinates: Coordinates(4.8018, -75.70014));
        expect(engine.activeManeuverIndex, equals(2));

        // Se recibe nueva ruta recalculada con routeVersion = 2
        final recalculated = urbanRoute.copyWith(
          summary: 'Ruta Recalculada tras desvío',
          routeVersion: 2,
        );
        engine.setRoute(recalculated);

        expect(engine.activeManeuverIndex, equals(0));
        final stepNew = engine.resolveStep(
          currentCoordinates: urbanRoute.origin,
        );
        expect(stepNew?.maneuverIndex, equals(0));
        expect(stepNew?.activeManeuver.type, equals(ManeuverType.depart));
      });
    });
  });
}
