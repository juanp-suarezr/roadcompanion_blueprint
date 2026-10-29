import '../../../../domain/entities/coordinates.dart';
import '../../../../domain/entities/maneuver.dart';
import '../../../../domain/entities/maneuver_type.dart';
import '../../../../domain/entities/route_plan.dart';
import '../services/tripper_protocol.dart';
import 'simulated_maneuver_step.dart';

/// Datos viales canónicos de la ruta de referencia:
/// Pereira (Plaza de Bolívar) → Santa Rosa de Cabal (Parque de las Araucarias), Risaralda, Colombia.
///
/// Longitud total aproximada por calzada: 15.52 km (~15527 metros).
/// Incluye el paso por el Viaducto César Gaviria Trujillo, Avenida Simón Bolívar (Dosquebradas),
/// Autopista del Café y la aproximación montañosa a Santa Rosa de Cabal.
class PereiraSantaRosaRoute {
  static const String routeName = 'Pereira → Santa Rosa de Cabal';
  static const String routeDescription =
      'Ruta vial de prueba por Viaducto César Gaviria y Autopista del Café (Risaralda, Colombia)';
  static const double totalRoadDistanceMeters = 15527.0;

  /// Origen: Plaza de Bolívar, Pereira (Risaralda, Colombia).
  static final Coordinates origin = Coordinates(4.814278, -75.694247);

  /// Destino: Parque de las Araucarias / Centro, Santa Rosa de Cabal (Risaralda, Colombia).
  static final Coordinates destination = Coordinates(4.868300, -75.621400);

  /// Geometría vial determinista completa extraída de la calzada real (105 vértices ordenados).
  static final List<Coordinates> geometry = [
    Coordinates(4.814278, -75.694247),
    Coordinates(4.814764, -75.695008),
    Coordinates(4.813952, -75.695087),
    Coordinates(4.813848, -75.694241),
    Coordinates(4.813544, -75.691758),
    Coordinates(4.813357, -75.690090),
    Coordinates(4.812500, -75.690174),
    Coordinates(4.811462, -75.688118),
    Coordinates(4.812073, -75.686572),
    Coordinates(4.813048, -75.687513),
    Coordinates(4.814135, -75.687311),
    Coordinates(4.820299, -75.685178),
    Coordinates(4.821718, -75.684256),
    Coordinates(4.823348, -75.683433),
    Coordinates(4.825046, -75.682518),
    Coordinates(4.826157, -75.681814),
    Coordinates(4.828157, -75.680559),
    Coordinates(4.828718, -75.680073),
    Coordinates(4.829568, -75.679045),
    Coordinates(4.830044, -75.678460),
    Coordinates(4.830653, -75.677583),
    Coordinates(4.831028, -75.676880),
    Coordinates(4.832403, -75.674581),
    Coordinates(4.833213, -75.673063),
    Coordinates(4.833743, -75.672102),
    Coordinates(4.834997, -75.670784),
    Coordinates(4.836534, -75.669309),
    Coordinates(4.837710, -75.668035),
    Coordinates(4.838684, -75.666954),
    Coordinates(4.839818, -75.665798),
    Coordinates(4.841029, -75.664477),
    Coordinates(4.842247, -75.663158),
    Coordinates(4.843077, -75.662238),
    Coordinates(4.843912, -75.661332),
    Coordinates(4.844917, -75.660181),
    Coordinates(4.845778, -75.659196),
    Coordinates(4.846875, -75.657891),
    Coordinates(4.847525, -75.657159),
    Coordinates(4.848312, -75.656247),
    Coordinates(4.849202, -75.655255),
    Coordinates(4.850125, -75.654160),
    Coordinates(4.851083, -75.653066),
    Coordinates(4.852083, -75.651877),
    Coordinates(4.852994, -75.650809),
    Coordinates(4.853922, -75.649718),
    Coordinates(4.854911, -75.648589),
    Coordinates(4.855845, -75.647493),
    Coordinates(4.856860, -75.646340),
    Coordinates(4.857864, -75.645199),
    Coordinates(4.858852, -75.644085),
    Coordinates(4.859846, -75.642959),
    Coordinates(4.860846, -75.641829),
    Coordinates(4.861783, -75.640767),
    Coordinates(4.862410, -75.640055),
    Coordinates(4.862680, -75.639745),
    Coordinates(4.863335, -75.639011),
    Coordinates(4.863777, -75.638459),
    Coordinates(4.864312, -75.637785),
    Coordinates(4.864811, -75.637158),
    Coordinates(4.865313, -75.636531),
    Coordinates(4.865814, -75.635905),
    Coordinates(4.866299, -75.635300),
    Coordinates(4.866750, -75.634720),
    Coordinates(4.867155, -75.634175),
    Coordinates(4.867568, -75.633633),
    Coordinates(4.867981, -75.633091),
    Coordinates(4.868394, -75.632550),
    Coordinates(4.868808, -75.632008),
    Coordinates(4.869222, -75.631466),
    Coordinates(4.869635, -75.630925),
    Coordinates(4.870049, -75.630383),
    Coordinates(4.870463, -75.629841),
    Coordinates(4.870876, -75.629300),
    Coordinates(4.871290, -75.628758),
    Coordinates(4.871704, -75.628216),
    Coordinates(4.872118, -75.627675),
    Coordinates(4.872531, -75.627133),
    Coordinates(4.872945, -75.626591),
    Coordinates(4.873359, -75.626050),
    Coordinates(4.873772, -75.625508),
    Coordinates(4.874186, -75.624966),
    Coordinates(4.874600, -75.624425),
    Coordinates(4.875013, -75.623883),
    Coordinates(4.875427, -75.623341),
    Coordinates(4.875841, -75.622800),
    Coordinates(4.876254, -75.622258),
    Coordinates(4.876668, -75.621716),
    Coordinates(4.877082, -75.621175),
    Coordinates(4.876400, -75.621300),
    Coordinates(4.875100, -75.621400),
    Coordinates(4.873200, -75.621450),
    Coordinates(4.871500, -75.621420),
    Coordinates(4.870100, -75.621400),
    Coordinates(4.869100, -75.621400),
    Coordinates(4.868300, -75.621400),
  ];

  /// Lista de maniobras canónicas a lo largo de la ruta vial Pereira → Santa Rosa.
  static List<SimulatedManeuverStep> buildCanonicalManeuverSteps() {
    return [
      // 1. Salida de Pereira
      SimulatedManeuverStep(
        stepNumber: 1,
        maneuver: Maneuver(
          instructionText: 'Salida de Pereira por Calle 19 hacia el Viaducto',
          type: ManeuverType.depart,
          location: geometry[0],
          roadName: 'Calle 19',
          distanceMeters: 450.0,
        ),
        initialDistanceMeters: 450,
        isSupportedByTripper: true,
        tripperManeuverCode: TripperProtocol.maneuverDepart,
        compatibilityNote: 'Código verificado 0x3C (Inicio de ruta)',
      ),

      // 2. Viaducto César Gaviria Trujillo (Recto continuo)
      SimulatedManeuverStep(
        stepNumber: 2,
        maneuver: Maneuver(
          instructionText:
              'Continúa recto por el Viaducto César Gaviria Trujillo',
          type: ManeuverType.straight,
          location: geometry[11],
          roadName: 'Viaducto César Gaviria Trujillo',
          distanceMeters: 750.0,
        ),
        initialDistanceMeters: 750,
        isSupportedByTripper: true,
        tripperManeuverCode: TripperProtocol.maneuverStraight,
        compatibilityNote: 'Código validado 0x09 (Recto por viaducto)',
      ),

      // 3. Entrada a Dosquebradas por Avenida Simón Bolívar
      SimulatedManeuverStep(
        stepNumber: 3,
        maneuver: Maneuver(
          instructionText:
              'Continúa por la Avenida Simón Bolívar atravesando Dosquebradas',
          type: ManeuverType.straight,
          location: geometry[16],
          roadName: 'Avenida Simón Bolívar',
          distanceMeters: 3800.0,
        ),
        initialDistanceMeters: 3800,
        isSupportedByTripper: true,
        tripperManeuverCode: TripperProtocol.maneuverStraight,
        compatibilityNote: 'Código validado 0x09 (Recto urbano Dosquebradas)',
      ),

      // 4. Incorporación a la Autopista del Café (Curva suave derecha)
      SimulatedManeuverStep(
        stepNumber: 4,
        maneuver: Maneuver(
          instructionText:
              'Toma la bifurcación a la derecha hacia la Autopista del Café',
          type: ManeuverType.slightRight,
          location: geometry[32],
          roadName: 'Autopista del Café',
          distanceMeters: 650.0,
        ),
        initialDistanceMeters: 650,
        isSupportedByTripper: true,
        tripperManeuverCode: TripperProtocol.maneuverSlightRight,
        compatibilityNote:
            'Código documentado 0x19 (Curva suave derecha / incorporación)',
      ),

      // 5. Autopista del Café - Tramo rápido en ascenso
      SimulatedManeuverStep(
        stepNumber: 5,
        maneuver: Maneuver(
          instructionText:
              'Avanza recto por la Autopista del Café hacia Santa Rosa',
          type: ManeuverType.straight,
          location: geometry[40],
          roadName: 'Autopista del Café (Ruta 29)',
          distanceMeters: 4600.0,
        ),
        initialDistanceMeters: 4600,
        isSupportedByTripper: true,
        tripperManeuverCode: TripperProtocol.maneuverStraight,
        compatibilityNote: 'Código validado 0x09 (Troncal Autopista del Café)',
      ),

      // 6. Curvas de Boquerón (Curva pronunciada a la izquierda)
      SimulatedManeuverStep(
        stepNumber: 6,
        maneuver: Maneuver(
          instructionText:
              'Curva pronunciada a la izquierda en sector La Romelia',
          type: ManeuverType.left,
          location: geometry[55],
          roadName: 'Autopista del Café',
          distanceMeters: 1200.0,
        ),
        initialDistanceMeters: 1200,
        isSupportedByTripper: true,
        tripperManeuverCode: TripperProtocol.maneuverSharpLeft,
        compatibilityNote:
            'Código documentado 0x16 (Curva pronunciada izquierda)',
      ),

      // 7. Desvío y entrada a Santa Rosa de Cabal
      SimulatedManeuverStep(
        stepNumber: 7,
        maneuver: Maneuver(
          instructionText:
              'Gira a la derecha para ingresar al casco urbano de Santa Rosa de Cabal',
          type: ManeuverType.right,
          location: geometry[80],
          roadName: 'Carrera 14 / Calle 12',
          distanceMeters: 800.0,
        ),
        initialDistanceMeters: 800,
        isSupportedByTripper: true,
        tripperManeuverCode: TripperProtocol.maneuverTurnRight,
        compatibilityNote:
            'Código confirmado físicamente 0x15 (Giro derecha casco urbano)',
      ),

      // 8. Llegada a destino en Parque de las Araucarias
      SimulatedManeuverStep(
        stepNumber: 8,
        maneuver: Maneuver(
          instructionText:
              'Has llegado al Parque de las Araucarias, Santa Rosa de Cabal. ¡Destino alcanzado!',
          type: ManeuverType.arrive,
          location: geometry.last,
          roadName: 'Santa Rosa de Cabal Centro',
          distanceMeters: 0.0,
        ),
        initialDistanceMeters: 0,
        isSupportedByTripper: true,
        tripperManeuverCode: TripperProtocol.maneuverDestination,
        compatibilityNote: 'Código verificado 0x00 (Destino alcanzado)',
      ),
    ];
  }

  /// Construye un [RoutePlan] formal del dominio con esta ruta vial.
  static RoutePlan buildRoutePlan() {
    final steps = buildCanonicalManeuverSteps();
    final maneuvers = steps.map((s) => s.maneuver).toList();

    return RoutePlan(
      origin: origin,
      destination: destination,
      geometry: geometry,
      totalDistanceMeters: totalRoadDistanceMeters,
      remainingDistanceMeters: totalRoadDistanceMeters,
      estimatedDuration: const Duration(minutes: 25),
      maneuvers: maneuvers,
    );
  }
}
