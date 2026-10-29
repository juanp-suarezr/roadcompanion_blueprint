import 'package:flutter/material.dart';

/// Dirección lateral predominante de una curva vial.
enum CurveDirection {
  /// Sin curvatura lateral relevante (recta o datos insuficientes).
  none,

  /// Curva hacia la izquierda.
  left,

  /// Curva hacia la derecha.
  right,

  /// Sucesión de curvas alternadas (izquierda-derecha o derecha-izquierda).
  alternating,
}

/// Clasificación geométrica de la curvatura de la vía (separada de maniobras de navegación).
enum CurveClass {
  /// Tramo recto sin curvatura significativa.
  straight,

  /// Curva amplia o gradual.
  gentle,

  /// Curva moderada.
  moderate,

  /// Curva pronunciada o cerrada.
  sharp,

  /// Curva en horquilla (cambio de dirección >= 120° en arco continuo compacto).
  hairpin,

  /// Curvas consecutivas cercanas.
  consecutive,

  /// Tramo sinuoso (sucesión continua de curvas alternadas).
  winding,

  /// Geometría vial incompleta, ausente o insuficiente para estimar curvatura.
  insufficientData,
}

/// Procedencia verificada de la geometría vial utilizada por el estimador.
enum GeometrySource {
  /// Geometría obtenida del motor de enrutamiento interno (OSRM GeoJSON).
  internalRouteOsrm,

  /// Geometría obtenida de un archivo GPX importado por el usuario.
  gpxTrack,

  /// Geometría determinista del escenario canónico de simulación.
  canonicalSimulation,

  /// Fuente de navegación externa (Waze / Google Maps) sin geometría de ruta expuesta.
  none,
}

/// Clasificación visual e interfaz de compatibilidad de la curvatura de la calzada.
enum RoadCurvatureType {
  straight,
  gentleLeft,
  gentleRight,
  sharpLeft,
  sharpRight,
  consecutiveCurves,
  winding,
  insufficientGeometry,
  @Deprecated('No mezclar maniobras discretas con curvatura vial')
  intersectionTurnLeft,
  @Deprecated('No mezclar maniobras discretas con curvatura vial')
  intersectionTurnRight,
  @Deprecated('No mezclar maniobras discretas con curvatura vial')
  roundabout;

  String get label {
    switch (this) {
      case RoadCurvatureType.straight:
        return 'Tramo recto';
      case RoadCurvatureType.gentleLeft:
        return 'Curva suave a la izquierda';
      case RoadCurvatureType.gentleRight:
        return 'Curva suave a la derecha';
      case RoadCurvatureType.sharpLeft:
        return 'Curva pronunciada a la izquierda';
      case RoadCurvatureType.sharpRight:
        return 'Curva pronunciada a la derecha';
      case RoadCurvatureType.consecutiveCurves:
        return 'Curvas consecutivas';
      case RoadCurvatureType.winding:
        return 'Tramo sinuoso';
      case RoadCurvatureType.insufficientGeometry:
        return 'Geometría vial insuficiente';
      // ignore: deprecated_member_use_from_same_package
      case RoadCurvatureType.intersectionTurnLeft:
        return 'Giro de intersección a la izquierda';
      // ignore: deprecated_member_use_from_same_package
      case RoadCurvatureType.intersectionTurnRight:
        return 'Giro de intersección a la derecha';
      // ignore: deprecated_member_use_from_same_package
      case RoadCurvatureType.roundabout:
        return 'Glorieta / Rotonda próxima';
    }
  }

  /// Alias de compatibilidad para trazabilidad y UI.
  String get displayName => label;

  IconData get icon {
    switch (this) {
      case RoadCurvatureType.straight:
        return Icons.straight_rounded;
      case RoadCurvatureType.gentleLeft:
        return Icons.turn_slight_left_rounded;
      case RoadCurvatureType.gentleRight:
        return Icons.turn_slight_right_rounded;
      case RoadCurvatureType.sharpLeft:
        return Icons.turn_sharp_left_rounded;
      case RoadCurvatureType.sharpRight:
        return Icons.turn_sharp_right_rounded;
      case RoadCurvatureType.consecutiveCurves:
      case RoadCurvatureType.winding:
        return Icons.alt_route_rounded;
      case RoadCurvatureType.insufficientGeometry:
        return Icons.help_outline_rounded;
      // ignore: deprecated_member_use_from_same_package
      case RoadCurvatureType.intersectionTurnLeft:
        return Icons.turn_left_rounded;
      // ignore: deprecated_member_use_from_same_package
      case RoadCurvatureType.intersectionTurnRight:
        return Icons.turn_right_rounded;
      // ignore: deprecated_member_use_from_same_package
      case RoadCurvatureType.roundabout:
        return Icons.roundabout_right_rounded;
    }
  }

  bool get isLeft =>
      this == RoadCurvatureType.gentleLeft ||
      this == RoadCurvatureType.sharpLeft ||
      // ignore: deprecated_member_use_from_same_package
      this == RoadCurvatureType.intersectionTurnLeft;

  bool get isRight =>
      this == RoadCurvatureType.gentleRight ||
      this == RoadCurvatureType.sharpRight ||
      // ignore: deprecated_member_use_from_same_package
      this == RoadCurvatureType.intersectionTurnRight;

  bool get isSharp =>
      this == RoadCurvatureType.sharpLeft ||
      this == RoadCurvatureType.sharpRight;

  bool get isCurve =>
      this != RoadCurvatureType.straight &&
      this != RoadCurvatureType.insufficientGeometry;
}

/// Resultado tipado de la estimación de curvatura vial sobre geometría real.
///
/// Separa estrictamente la **curvatura física del trazado vial** de las **maniobras
/// discretas de navegación** (giros en intersecciones, retornos o salidas).
class RoadCurvatureInfo {
  /// Clasificación visual compatible con el HUD y paneles existentes.
  final RoadCurvatureType type;

  /// Sentido lateral de la curva detectada.
  final CurveDirection curveDirection;

  /// Clase geométrica de la curva o tramo sinuoso.
  final CurveClass curveClass;

  /// Distancia en metros desde la posición actual hasta el inicio de la curva.
  final double distanceToCurveMeters;

  /// Longitud estimada del arco de curva en metros.
  final double estimatedLengthMeters;

  /// Radio de curvatura estimado en metros (`L / |Δθ_rad|`), o `null` cuando
  /// la geometría no permite una estimación razonable (ej. recta o datos insuficientes).
  final double? estimatedRadiusMeters;

  /// Nivel de confianza de la estimación geométrica en el rango `[0.0, 1.0]`.
  final double confidence;

  /// Fuente de donde proviene la geometría evaluada.
  final GeometrySource geometrySource;

  /// Versión de la ruta activa a la que corresponde esta estimación.
  final int routeVersion;

  /// Marca temporal en la que se calculó la estimación.
  final DateTime timestamp;

  /// Indica si la estimación quedó desactualizada (por tiempo o por cambio de ruta).
  final bool isStale;

  /// Cambio angular acumulado en grados dentro del arco de curva (`-180°` a `+180°`,
  /// positivo = derecha, negativo = izquierda).
  final double bearingDeltaDegrees;

  /// Ventana espacial total inspeccionada hacia adelante en metros.
  final double windowLengthMeters;

  /// Cantidad de curvas individuales detectadas dentro de la ventana de anticipación.
  final int consecutiveCurveCount;

  RoadCurvatureInfo({
    required this.type,
    required this.bearingDeltaDegrees,
    required this.windowLengthMeters,
    CurveDirection? curveDirection,
    CurveClass? curveClass,
    this.distanceToCurveMeters = 0.0,
    double? estimatedLengthMeters,
    this.estimatedRadiusMeters,
    this.confidence = 1.0,
    this.geometrySource = GeometrySource.internalRouteOsrm,
    this.routeVersion = 1,
    DateTime? timestamp,
    this.isStale = false,
    this.consecutiveCurveCount = 0,
  }) : curveDirection = curveDirection ?? _inferDirection(type),
       curveClass = curveClass ?? _inferClass(type),
       estimatedLengthMeters = estimatedLengthMeters ?? windowLengthMeters,
       timestamp = timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);

  /// Instancia por defecto para un tramo recto verificado.
  static final RoadCurvatureInfo straightDefault = RoadCurvatureInfo(
    type: RoadCurvatureType.straight,
    curveDirection: CurveDirection.none,
    curveClass: CurveClass.straight,
    distanceToCurveMeters: 0.0,
    estimatedLengthMeters: 0.0,
    estimatedRadiusMeters: null,
    confidence: 1.0,
    geometrySource: GeometrySource.canonicalSimulation,
    routeVersion: 1,
    bearingDeltaDegrees: 0.0,
    windowLengthMeters: 80.0,
  );

  /// Alias de compatibilidad para geometría indeterminada o insuficiente.
  static final RoadCurvatureInfo undetermined =
      RoadCurvatureInfo.insufficient();

  /// Instancia explícita cuando no existe geometría vial verificada
  /// (por ejemplo, cuando se navega con Waze o Google Maps mediante notificaciones,
  /// o cuando la polilínea está incompleta).
  factory RoadCurvatureInfo.insufficient({
    GeometrySource geometrySource = GeometrySource.none,
    int routeVersion = 1,
    DateTime? timestamp,
  }) {
    return RoadCurvatureInfo(
      type: RoadCurvatureType.insufficientGeometry,
      curveDirection: CurveDirection.none,
      curveClass: CurveClass.insufficientData,
      distanceToCurveMeters: 0.0,
      estimatedLengthMeters: 0.0,
      estimatedRadiusMeters: null,
      confidence: 0.0,
      geometrySource: geometrySource,
      routeVersion: routeVersion,
      timestamp: timestamp ?? DateTime.now(),
      isStale: false,
      bearingDeltaDegrees: 0.0,
      windowLengthMeters: 0.0,
    );
  }

  /// Verifica si esta estimación es inválida respecto a una versión de ruta o reloj actual.
  bool isOutdated({
    required int activeRouteVersion,
    DateTime? now,
    Duration maxAge = const Duration(seconds: 12),
  }) {
    if (isStale) return true;
    if (routeVersion != activeRouteVersion) return true;
    if (now != null &&
        timestamp.millisecondsSinceEpoch > 0 &&
        now.difference(timestamp) > maxAge) {
      return true;
    }
    return false;
  }

  /// Retorna una copia marcada explícitamente como desactualizada (`isStale: true`).
  RoadCurvatureInfo markStale() {
    return RoadCurvatureInfo(
      type: type,
      curveDirection: curveDirection,
      curveClass: curveClass,
      distanceToCurveMeters: distanceToCurveMeters,
      estimatedLengthMeters: estimatedLengthMeters,
      estimatedRadiusMeters: estimatedRadiusMeters,
      confidence: confidence,
      geometrySource: geometrySource,
      routeVersion: routeVersion,
      timestamp: timestamp,
      isStale: true,
      bearingDeltaDegrees: bearingDeltaDegrees,
      windowLengthMeters: windowLengthMeters,
      consecutiveCurveCount: consecutiveCurveCount,
    );
  }

  /// Indica si existe una curva o tramo sinuoso relevante detectado con confianza suficiente.
  bool get hasActiveCurve =>
      !isStale &&
      confidence >= 0.35 &&
      curveClass != CurveClass.straight &&
      curveClass != CurveClass.insufficientData;

  static CurveDirection _inferDirection(RoadCurvatureType type) {
    if (type == RoadCurvatureType.winding ||
        type == RoadCurvatureType.consecutiveCurves) {
      return CurveDirection.alternating;
    }
    if (type.isLeft) return CurveDirection.left;
    if (type.isRight) return CurveDirection.right;
    return CurveDirection.none;
  }

  static CurveClass _inferClass(RoadCurvatureType type) {
    switch (type) {
      case RoadCurvatureType.straight:
        return CurveClass.straight;
      case RoadCurvatureType.gentleLeft:
      case RoadCurvatureType.gentleRight:
        return CurveClass.gentle;
      case RoadCurvatureType.sharpLeft:
      case RoadCurvatureType.sharpRight:
        return CurveClass.sharp;
      case RoadCurvatureType.consecutiveCurves:
        return CurveClass.consecutive;
      case RoadCurvatureType.winding:
        return CurveClass.winding;
      case RoadCurvatureType.insufficientGeometry:
        return CurveClass.insufficientData;
      // ignore: deprecated_member_use_from_same_package
      case RoadCurvatureType.intersectionTurnLeft:
      // ignore: deprecated_member_use_from_same_package
      case RoadCurvatureType.intersectionTurnRight:
      // ignore: deprecated_member_use_from_same_package
      case RoadCurvatureType.roundabout:
        return CurveClass.sharp;
    }
  }
}

/// Estado del semáforo dinámico de proximidad a maniobra/curva.
///
/// Reglas de transición:
/// - **Verde**: Distancia > 200 m (aproximación libre).
/// - **Amarillo**: Distancia entre 200 m y 51 m (precaución / preparación).
/// - **Rojo**: Distancia <= 50 m (ejecución inmediata de maniobra / curva).
///
/// Incluye histéresis de 5 m hacia arriba para evitar parpadeos por ruido.
enum ProximityTrafficLight {
  green,
  yellow,
  red;

  static const double yellowThresholdMeters = 200.0;
  static const double redThresholdMeters = 50.0;
  static const double hysteresisMeters = 5.0;

  String get label {
    switch (this) {
      case ProximityTrafficLight.green:
        return 'APROXIMACIÓN LIBRE (> 200 m)';
      case ProximityTrafficLight.yellow:
        return 'PRECAUCIÓN / PREPARAR GIRO (51 - 200 m)';
      case ProximityTrafficLight.red:
        return 'MANIOBRA INMEDIATA (≤ 50 m)';
    }
  }

  Color get color {
    switch (this) {
      case ProximityTrafficLight.green:
        return const Color(0xFF00E676);
      case ProximityTrafficLight.yellow:
        return const Color(0xFFFFD54F);
      case ProximityTrafficLight.red:
        return const Color(0xFFFF5252);
    }
  }

  /// Calcula el estado del semáforo aplicando histéresis opcional respecto al estado previo.
  static ProximityTrafficLight evaluate({
    required double distanceMeters,
    ProximityTrafficLight? previousState,
  }) {
    if (previousState == ProximityTrafficLight.red) {
      if (distanceMeters <= redThresholdMeters + hysteresisMeters) {
        return ProximityTrafficLight.red;
      }
    }
    if (previousState == ProximityTrafficLight.yellow) {
      if (distanceMeters <= redThresholdMeters) {
        return ProximityTrafficLight.red;
      }
      if (distanceMeters <= yellowThresholdMeters + hysteresisMeters) {
        return ProximityTrafficLight.yellow;
      }
    }

    if (distanceMeters <= redThresholdMeters) {
      return ProximityTrafficLight.red;
    }
    if (distanceMeters <= yellowThresholdMeters) {
      return ProximityTrafficLight.yellow;
    }
    return ProximityTrafficLight.green;
  }
}
