import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';

/// Clasificación de la curvatura vial calculada a partir de la geometría de calzada.
enum RoadCurvatureType {
  /// Tramo recto o variación de rumbo despreciable (< 10°).
  straight('Tramo recto', Icons.straight_rounded),

  /// Curva suave hacia la izquierda (10° a 35°).
  gentleLeft('Curva suave a la izquierda', Icons.turn_slight_left_rounded),

  /// Curva pronunciada hacia la izquierda (> 35°).
  sharpLeft('Curva pronunciada a la izquierda', Icons.turn_sharp_left_rounded),

  /// Curva suave hacia la derecha (10° a 35°).
  gentleRight('Curva suave a la derecha', Icons.turn_slight_right_rounded),

  /// Curva pronunciada hacia la derecha (> 35°).
  sharpRight('Curva pronunciada a la derecha', Icons.turn_sharp_right_rounded),

  /// Giro hacia la izquierda en intersección vial.
  intersectionTurnLeft('Giro a la izquierda', Icons.turn_left_rounded),

  /// Giro hacia la derecha en intersección vial.
  intersectionTurnRight('Giro a la derecha', Icons.turn_right_rounded),

  /// Intersección de tipo glorieta / rotonda.
  roundabout('Rotonda / Glorieta', Icons.roundabout_left_rounded),

  /// Datos insuficientes o geometría ambigua para determinar curvatura con certeza.
  undetermined('Curva por determinar', Icons.help_outline_rounded);

  final String displayName;
  final IconData icon;

  const RoadCurvatureType(this.displayName, this.icon);

  /// Indica si la clasificación corresponde a una curva física de calzada.
  bool get isCurve =>
      this == gentleLeft ||
      this == sharpLeft ||
      this == gentleRight ||
      this == sharpRight;

  /// Indica si es curva o giro hacia la izquierda.
  bool get isLeft =>
      this == gentleLeft || this == sharpLeft || this == intersectionTurnLeft;

  /// Indica si es curva o giro hacia la derecha.
  bool get isRight =>
      this == gentleRight || this == sharpRight || this == intersectionTurnRight;
}

/// Información analítica de la curvatura de calzada aproximada.
class RoadCurvatureInfo {
  /// Tipo de curvatura clasificada.
  final RoadCurvatureType type;

  /// Delta de rumbo en grados con signo (- izquierda, + derecha) [-180°, 180°].
  final double bearingDeltaDegrees;

  /// Distancia estimada hasta el inicio o vértice de la curva en metros.
  final double distanceToCurveMeters;

  /// Longitud de la ventana de análisis geométrico en metros.
  final double windowLengthMeters;

  const RoadCurvatureInfo({
    required this.type,
    required this.bearingDeltaDegrees,
    required this.distanceToCurveMeters,
    required this.windowLengthMeters,
  });

  static const undetermined = RoadCurvatureInfo(
    type: RoadCurvatureType.undetermined,
    bearingDeltaDegrees: 0.0,
    distanceToCurveMeters: 0.0,
    windowLengthMeters: 0.0,
  );
}

/// Estado del semáforo reactivo de proximidad a la maniobra o curva.
enum ProximityTrafficLight {
  /// Maniobra lejana (> 200 m). Tranquilidad en ruta.
  green('VERDE: Maniobra lejana', Colors.greenAccent, AppColors.success),

  /// Maniobra en aproximación (50 m < d <= 200 m). Atención y desaceleración.
  yellow('AMARILLO: Aproximación', Colors.amberAccent, AppColors.warning),

  /// Maniobra inminente o muy próxima (d <= 50 m). Ejecución inmediata.
  red('ROJO: Maniobra inminente', Colors.redAccent, AppColors.error);

  final String label;
  final Color lightColor;
  final Color solidColor;

  const ProximityTrafficLight(this.label, this.lightColor, this.solidColor);

  /// Evalúa el color de proximidad aplicando histéresis estricta contra parpadeos.
  ///
  /// Umbrales configurables documentados:
  /// - [redThresholdMeters]: Distancia máxima para activar ROJO (por defecto 50.0 m).
  /// - [yellowThresholdMeters]: Distancia máxima para activar AMARILLO (por defecto 200.0 m).
  /// - [hysteresisMeters]: Margen de separación para evitar oscilaciones (por defecto 5.0 m).
  static ProximityTrafficLight evaluate({
    required double distanceMeters,
    ProximityTrafficLight? previousState,
    double redThresholdMeters = 50.0,
    double yellowThresholdMeters = 200.0,
    double hysteresisMeters = 5.0,
  }) {
    if (previousState == null) {
      if (distanceMeters <= redThresholdMeters) return ProximityTrafficLight.red;
      if (distanceMeters <= yellowThresholdMeters) {
        return ProximityTrafficLight.yellow;
      }
      return ProximityTrafficLight.green;
    }

    switch (previousState) {
      case ProximityTrafficLight.red:
        // Solo sale de rojo a amarillo si supera el umbral + margen de histéresis
        if (distanceMeters > redThresholdMeters + hysteresisMeters) {
          if (distanceMeters > yellowThresholdMeters + hysteresisMeters) {
            return ProximityTrafficLight.green;
          }
          return ProximityTrafficLight.yellow;
        }
        return ProximityTrafficLight.red;

      case ProximityTrafficLight.yellow:
        // Cae a rojo si está por debajo del umbral rojo
        if (distanceMeters <= redThresholdMeters) {
          return ProximityTrafficLight.red;
        }
        // Sube a verde solo si supera el umbral amarillo + histéresis
        if (distanceMeters > yellowThresholdMeters + hysteresisMeters) {
          return ProximityTrafficLight.green;
        }
        return ProximityTrafficLight.yellow;

      case ProximityTrafficLight.green:
        // Cae a rojo si es muy pequeña
        if (distanceMeters <= redThresholdMeters) {
          return ProximityTrafficLight.red;
        }
        // Cae a amarillo si cruza por debajo del umbral amarillo
        if (distanceMeters <= yellowThresholdMeters) {
          return ProximityTrafficLight.yellow;
        }
        return ProximityTrafficLight.green;
    }
  }
}
