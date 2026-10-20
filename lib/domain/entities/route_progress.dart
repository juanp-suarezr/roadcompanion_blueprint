import 'coordinates.dart';

/// Representa el resultado inmutable del cálculo del progreso de una ruta.
///
/// Encapsula las métricas de avance por carretera, distancia restante,
/// porcentaje completado y proyección perpendicular sobre el trazado vial.
///
/// COHERENCIA ENTRE DISTANCIAS Y PORCENTAJE DE PROGRESO:
/// 1. Coherencia categórica estricta en la entidad:
///    [RouteProgress] valida de forma determinista y sin tolerancias arbitrarias los estados límite:
///    - Trayecto de longitud cero (recorrida = 0.0 m y restante = 0.0 m) exige [progressPercentage] == 100.0 %.
///    - Arribo a destino (restante = 0.0 m y recorrida > 0.0 m) exige [progressPercentage] == 100.0 %.
///    - Inicio de ruta (recorrida = 0.0 m y restante > 0.0 m) exige [progressPercentage] == 0.0 %.
///    - Avance en curso (recorrida > 0.0 m y restante > 0.0 m) exige [progressPercentage] en el intervalo abierto (0.0, 100.0).
/// 2. Coherencia matemática continua en el calculador:
///    La correlación proporcional continua entre el porcentaje y las distancias
///    ($progressPercentage \approx \frac{d_{traveled}}{d_{traveled} + d_{remaining}} \times 100.0$)
///    corresponde exclusivamente al servicio [RouteProgressCalculator]. La entidad no impone
///    una igualdad aritmética continua con delta fijo (ej. ±0.1% o ±1%), ya que cualquier tolerancia
///    flotante arbitraria carecería de fundamento semántico y penalizaría consumidores que transmiten
///    telemetría con menor resolución o redondeo (como tramas BLE para pods de navegación).
class RouteProgress {
  /// Distancia acumulada recorrida a lo largo de la ruta en metros.
  final double distanceTraveledMeters;

  /// Distancia restante por recorrer por carretera hacia el destino en metros.
  final double remainingDistanceMeters;

  /// Porcentaje de progreso completado del trayecto (en el rango estricto de 0.0 a 100.0).
  final double progressPercentage;

  /// Coordenada geográfica del punto proyectado sobre el segmento más cercano de la ruta.
  final Coordinates projectedPoint;

  /// Distancia ortogonal (desvío lateral) en metros entre la posición actual y [projectedPoint].
  final double distanceToRouteMeters;

  /// Índice del segmento de la ruta (0 a N-2) sobre el cual se proyectó la posición.
  final int closestSegmentIndex;

  /// Crea una instancia inmutable de [RouteProgress] validando estrictamente
  /// que todas las métricas sean números finitos y respeten las invariantes de dominio.
  RouteProgress({
    required this.distanceTraveledMeters,
    required this.remainingDistanceMeters,
    required this.progressPercentage,
    required this.projectedPoint,
    required this.distanceToRouteMeters,
    required this.closestSegmentIndex,
  }) {
    if (!distanceTraveledMeters.isFinite) {
      throw ArgumentError.value(
        distanceTraveledMeters,
        'distanceTraveledMeters',
        'La distancia recorrida debe ser un número finito.',
      );
    }
    if (distanceTraveledMeters < 0.0) {
      throw ArgumentError.value(
        distanceTraveledMeters,
        'distanceTraveledMeters',
        'La distancia recorrida no puede ser negativa.',
      );
    }
    if (!remainingDistanceMeters.isFinite) {
      throw ArgumentError.value(
        remainingDistanceMeters,
        'remainingDistanceMeters',
        'La distancia restante debe ser un número finito.',
      );
    }
    if (remainingDistanceMeters < 0.0) {
      throw ArgumentError.value(
        remainingDistanceMeters,
        'remainingDistanceMeters',
        'La distancia restante no puede ser negativa.',
      );
    }
    if (!progressPercentage.isFinite) {
      throw ArgumentError.value(
        progressPercentage,
        'progressPercentage',
        'El porcentaje de progreso debe ser un número finito.',
      );
    }
    if (progressPercentage < 0.0 || progressPercentage > 100.0) {
      throw ArgumentError.value(
        progressPercentage,
        'progressPercentage',
        'El porcentaje de progreso debe estar comprendido entre 0.0 y 100.0.',
      );
    }
    if (!distanceToRouteMeters.isFinite) {
      throw ArgumentError.value(
        distanceToRouteMeters,
        'distanceToRouteMeters',
        'La distancia a la ruta debe ser un número finito.',
      );
    }
    if (distanceToRouteMeters < 0.0) {
      throw ArgumentError.value(
        distanceToRouteMeters,
        'distanceToRouteMeters',
        'La distancia a la ruta no puede ser negativa.',
      );
    }
    if (!(distanceTraveledMeters + remainingDistanceMeters).isFinite) {
      throw ArgumentError(
        'La suma de distancia recorrida y restante debe ser un número finito.',
      );
    }
    if (distanceTraveledMeters == 0.0 && remainingDistanceMeters == 0.0) {
      if (progressPercentage != 100.0) {
        throw ArgumentError.value(
          progressPercentage,
          'progressPercentage',
          'Para un trayecto de distancia total cero (recorrida y restante de 0.0 m), '
              'el porcentaje de progreso debe ser exactamente 100.0.',
        );
      }
    } else if (remainingDistanceMeters == 0.0) {
      if (progressPercentage != 100.0) {
        throw ArgumentError.value(
          progressPercentage,
          'progressPercentage',
          'Si la distancia restante es 0.0 m y la recorrida es positiva, '
              'el porcentaje de progreso debe ser exactamente 100.0.',
        );
      }
    } else if (distanceTraveledMeters == 0.0) {
      if (progressPercentage != 0.0) {
        throw ArgumentError.value(
          progressPercentage,
          'progressPercentage',
          'Si la distancia recorrida es 0.0 m y la restante es positiva, '
              'el porcentaje de progreso debe ser exactamente 0.0.',
        );
      }
    } else {
      if (progressPercentage <= 0.0 || progressPercentage >= 100.0) {
        throw ArgumentError.value(
          progressPercentage,
          'progressPercentage',
          'Para un trayecto con distancia recorrida y restante positivas, '
              'el porcentaje de progreso no puede ser 0.0 ni 100.0 y debe situarse estrictamente en (0.0, 100.0).',
        );
      }
    }
    if (closestSegmentIndex < 0) {
      throw ArgumentError.value(
        closestSegmentIndex,
        'closestSegmentIndex',
        'El índice del segmento más cercano no puede ser negativo.',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RouteProgress &&
          runtimeType == other.runtimeType &&
          distanceTraveledMeters == other.distanceTraveledMeters &&
          remainingDistanceMeters == other.remainingDistanceMeters &&
          progressPercentage == other.progressPercentage &&
          projectedPoint == other.projectedPoint &&
          distanceToRouteMeters == other.distanceToRouteMeters &&
          closestSegmentIndex == other.closestSegmentIndex;

  @override
  int get hashCode => Object.hash(
        distanceTraveledMeters,
        remainingDistanceMeters,
        progressPercentage,
        projectedPoint,
        distanceToRouteMeters,
        closestSegmentIndex,
      );

  @override
  String toString() =>
      'RouteProgress(traveled: ${distanceTraveledMeters.toStringAsFixed(1)} m, '
      'remaining: ${remainingDistanceMeters.toStringAsFixed(1)} m, '
      'progress: ${progressPercentage.toStringAsFixed(1)}%, '
      'seg: $closestSegmentIndex, '
      'crossTrack: ${distanceToRouteMeters.toStringAsFixed(1)} m)';
}
