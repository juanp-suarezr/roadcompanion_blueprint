import 'dart:math';

import '../entities/coordinates.dart';
import '../entities/route_plan.dart';
import '../entities/route_progress.dart';

/// Servicio de dominio puro para calcular el avance y estado de progreso sobre una ruta.
///
/// RESPONSABILIDAD:
/// - Proyectar la posición actual sobre los segmentos de la polilínea ordenada de la ruta.
/// - Calcular la distancia recorrida acumulada y la distancia restante siguiendo la geometría
///   real de la calzada (no distancia en línea recta hasta el destino).
/// - Calcular el porcentaje de progreso acotado deterministamente en [0.0, 100.0].
/// - Preservar coherencia con [RoutePlan.totalDistanceMeters] sin permitir discrepancias
///   que contradigan las validaciones estrictas del dominio.
///
/// JUSTIFICACIÓN DE LA PROPORCIÓN GEOMÉTRICA FRENTE A DISTANCIA DEL PROVEEDOR:
/// Los motores de enrutamiento calculan [RoutePlan.totalDistanceMeters] sobre grafos de red
/// vial de alta resolución, curvas modeladas y perfiles de elevación, mientras que [RoutePlan.geometry]
/// suele ser una polilínea simplificada (vía Ramer-Douglas-Peucker u optimizaciones de red móvil).
/// Por ello, la suma Haversine de los vértices geométricos ($D_{geom}$) difiere legítimamente
/// de [totalDistanceMeters]. Si se sustrajera distancia euclidiana bruta del total del proveedor,
/// se producirían discrepancias graves (ej. distancias restantes mayores a la distancia total
/// o distancias restantes distintas de cero al llegar a destino). Al aplicar la proporción de
/// avance geométrico ($progressRatio = d_{traveled, geom} / D_{geom}$) sobre [totalDistanceMeters],
/// se garantiza que:
/// 1. En el inicio: recorrida = 0.0 m, restante = totalDistanceMeters, progreso = 0.0 %.
/// 2. En el arribo: recorrida = totalDistanceMeters, restante = 0.0 m, progreso = 100.0 %.
/// 3. Coherencia numérica: recorrida + restante converge a totalDistanceMeters dentro de la tolerancia
///    de precisión de punto flotante de 64 bits (IEEE 754, sujeta a épsilon de redondeo aritmético).
/// 4. Compatibilidad: restante <= totalDistanceMeters garantizado deterministamente sin violar
///    las reglas estrictas de dominio de [RoutePlan].
///
/// LIMITACIONES Y RESOLUCIÓN DE AMBIGÜEDADES:
/// 1. Aproximación métrica equirrectangular plana local:
///    La proyección ortogonal asume una superficie plana local tangencial ponderada por
///    $\cos(lat_{mean})$. Esta es una aproximación computacionalmente eficiente adecuada para
///    segmentos viales de calzada, pero representa una simplificación de la geodesia elipsoidal
///    y no garantiza precisión submétrica universal en todas las latitudes, orientaciones o
///    longitudes de arco.
/// 2. Cruce del antimeridiano (+180° / -180°):
///    El cálculo normaliza las diferencias longitudinales al camino geodésico más corto y envuelve
///    las coordenadas proyectadas para que pertenezcan estrictamente al rango [-180.0, 180.0].
/// 3. Lazos, cruces y saltos de tramo (ausencia de estado cinemático temporal):
///    En T1.3 (cálculo funcional puro de dominio), no se inventan umbrales arbitrarios de distancia
///    ni tolerancias silenciosas para descartar tramos. Cuando [maxSegmentLookahead] es null, se
///    evalúa toda la ruta restante hasta el destino; por tanto, este cálculo NO previene por defecto
///    saltos hacia tramos lejanos si una lectura GPS queda geométricamente más próxima a una curva
///    futura, paso elevado o lazo vial. Discernir si dicha proximidad es ruido o un salto requiere
///    variables de estado temporal y cinemático (rumbo/heading GPS, velocidad instantánea, intervalo
///    de tiempo y máquina de estados de off-route), las cuales pertenecen a la capa de sesión de
///    navegación (`NavigationSession`) y quedan fuera del alcance de T1.3.
///    En esta capa pura, el comportamiento es determinista y no promete protecciones inexistentes:
///    - Ante empates exactos de distancia a múltiples tramos, se selecciona el primer tramo en orden
///      de itinerario para evitar saltos hacia adelante sin recorrido acreditado.
///    - Si se provee [lastKnownSegmentIndex], la búsqueda se inicia a partir de dicho tramo, evitando
///      retrocesos a tramos ya superados. Sin embargo, comenzar la búsqueda desde este índice excluye
///      estrictamente los segmentos anteriores (0 a lastKnownSegmentIndex - 1); por tanto, puede
///    - Si se provee [maxSegmentLookahead], la búsqueda se acota estrictamente a los siguientes N
///      segmentos hacia adelante a partir de [lastKnownSegmentIndex], acotando el espacio de evaluación.
///    - Segmentos degenerados y vértices coincidentes (ej. [A, A, B] o [A, B, B]):
///      Cuando una posición coincide exactamente con un vértice adyacente a un segmento degenerado
///      (longitud cero) y a un segmento regular, ambos segmentos arrojan distancia lateral de 0.0 m.
///      En virtud de la regla determinista de desempate (`distanceToP < minDistanceToRoute`), el cálculo
///      selecciona siempre el segmento con menor índice (el primero en orden de itinerario). Por ejemplo,
///      en [A, B, B] en el punto B, se selecciona el segmento 0 ([A, B] con t=1.0) en vez del segmento 1
///      ([B, B]); en [A, A, B] en el punto A, se selecciona el segmento 0 ([A, A] con t=0.0). En ambos
///      casos, las métricas de avance reflejan el progreso exacto (0.0 % y 100.0 % respectivamente),
///      satisfaciendo rigurosamente las invariantes de [RouteProgress] y la compatibilidad con [RoutePlan].
/// 4. Geometría colapsada con distancia de proveedor positiva:
///    Si la geometría está compuesta exclusivamente por puntos coincidentes (distancia geométrica
///    total $D_{geom} == 0.0$ m) pero se suministra un [totalDistanceMeters] positivo (> 0.0 m), no
///    existe una trayectoria espacial sobre la cual proyectar o interpolar el progreso de avance.
///    En lugar de inventar un porcentaje arbitrario o asumir silenciosamente un avance del 0 % o 100 %,
///    el cálculo rechaza explícitamente esta inconsistencia lanzando un [ArgumentError].
///    Por el contrario, cuando la distancia total efectiva es cero (origen y destino coincidentes
///    con [totalDistanceMeters] nulo o igual a 0.0), se reporta arribo a destino (progreso 100.0 %
///    y distancia restante 0.0 m).
class RouteProgressCalculator {
  /// Constructor constante para permitir inyección de dependencias si es requerida.
  const RouteProgressCalculator();

  /// Calcula el progreso sobre una geometría de ruta ordenada a partir de [currentPosition].
  ///
  /// Parámetros:
  /// - [geometry]: Lista ordenada de vértices geográficos del trazado vial. Debe contener al menos 2 puntos.
  /// - [currentPosition]: Ubicación actual que se desea proyectar sobre la calzada.
  /// - [totalDistanceMeters]: Distancia total oficial por carretera según el plan de ruta (opcional).
  /// - [lastKnownSegmentIndex]: Índice de segmento mínimo a evaluar (opcional). Debe estar entre 0 y `geometry.length - 2`.
  ///   ADVERTENCIA: Comenzar la búsqueda a partir de este índice excluye estrictamente todos los segmentos anteriores
  ///   (0 a `lastKnownSegmentIndex - 1`), por lo que puede ocultar un retroceso real del vehículo sobre la calzada
  ///   o perpetuarse ante un índice suministrado obsoleto o erróneo.
  /// - [maxSegmentLookahead]: Número máximo de segmentos adicionales a evaluar hacia adelante (opcional).
  ///   Si es null, se evalúa toda la ruta restante hasta el destino sin restringir saltos a tramos lejanos más cercanos.
  ///
  /// Lanza [ArgumentError] si:
  /// - [geometry] tiene menos de 2 puntos o contiene coordenadas no finitas o fuera de rango.
  /// - [geometry] tiene longitud geométrica de 0.0 m (puntos coincidentes) pero [totalDistanceMeters] es > 0.0.
  /// - [currentPosition] contiene coordenadas fuera de rango o no finitas.
  /// - [totalDistanceMeters] es negativo o no finito.
  /// - [lastKnownSegmentIndex] es menor a 0 o mayor a `geometry.length - 2`.
  /// - [maxSegmentLookahead] es negativo.
  RouteProgress calculate({
    required List<Coordinates> geometry,
    required Coordinates currentPosition,
    double? totalDistanceMeters,
    int? lastKnownSegmentIndex,
    int? maxSegmentLookahead,
  }) {
    if (geometry.length < 2) {
      throw ArgumentError.value(
        geometry.length,
        'geometry',
        'La geometría de la ruta debe contener al menos dos puntos para proyectar el progreso.',
      );
    }

    if (lastKnownSegmentIndex != null) {
      final int maxValidSegmentIndex = geometry.length - 2;
      if (lastKnownSegmentIndex < 0 ||
          lastKnownSegmentIndex > maxValidSegmentIndex) {
        throw ArgumentError.value(
          lastKnownSegmentIndex,
          'lastKnownSegmentIndex',
          'El índice de segmento previo ($lastKnownSegmentIndex) debe estar comprendido entre 0 y $maxValidSegmentIndex (geometry.length - 2).',
        );
      }
    }

    if (!currentPosition.latitude.isFinite ||
        !currentPosition.longitude.isFinite ||
        currentPosition.latitude < -90.0 ||
        currentPosition.latitude > 90.0 ||
        currentPosition.longitude < -180.0 ||
        currentPosition.longitude > 180.0) {
      throw ArgumentError.value(
        currentPosition,
        'currentPosition',
        'La posición actual contiene coordenadas geográficas inválidas o fuera de rango.',
      );
    }

    for (int i = 0; i < geometry.length; i++) {
      final c = geometry[i];
      if (!c.latitude.isFinite ||
          !c.longitude.isFinite ||
          c.latitude < -90.0 ||
          c.latitude > 90.0 ||
          c.longitude < -180.0 ||
          c.longitude > 180.0) {
        throw ArgumentError.value(
          c,
          'geometry[$i]',
          'La coordenada en el índice $i de la geometría contiene valores fuera de rango o no finitos.',
        );
      }
    }

    if (totalDistanceMeters != null) {
      if (!totalDistanceMeters.isFinite) {
        throw ArgumentError.value(
          totalDistanceMeters,
          'totalDistanceMeters',
          'La distancia total debe ser un número finito.',
        );
      }
      if (totalDistanceMeters < 0.0) {
        throw ArgumentError.value(
          totalDistanceMeters,
          'totalDistanceMeters',
          'La distancia total no puede ser negativa.',
        );
      }
    }

    final int numSegments = geometry.length - 1;

    if (maxSegmentLookahead != null) {
      if (maxSegmentLookahead < 0) {
        throw ArgumentError.value(
          maxSegmentLookahead,
          'maxSegmentLookahead',
          'La ventana de búsqueda de segmentos no puede ser negativa.',
        );
      }
    }

    // 1. Precomputar longitudes de segmentos y distancias acumuladas a lo largo de la geometría
    final List<double> segmentLengths = List<double>.filled(numSegments, 0.0);
    final List<double> cumulativeDistances = List<double>.filled(
      numSegments,
      0.0,
    );

    double totalGeomDist = 0.0;
    for (int i = 0; i < numSegments; i++) {
      cumulativeDistances[i] = totalGeomDist;
      final double len = geometry[i].distanceTo(geometry[i + 1]);
      if (!len.isFinite || len < 0.0) {
        throw StateError('La longitud del segmento $i no es válida: $len.');
      }
      segmentLengths[i] = len;
      totalGeomDist += len;
      if (!totalGeomDist.isFinite) {
        throw StateError(
          'La distancia acumulada de la ruta excedió el límite numérico finito.',
        );
      }
    }

    // 2. Proyección de la posición actual sobre los segmentos candidatos
    final int startSegment = lastKnownSegmentIndex ?? 0;
    final int endSegment = maxSegmentLookahead != null
        ? min(numSegments - 1, startSegment + maxSegmentLookahead)
        : numSegments - 1;

    int bestSegmentIndex = startSegment;
    double minDistanceToRoute = double.infinity;
    Coordinates bestProjectedPoint = geometry[startSegment];
    double bestTraveledAlongGeometry = cumulativeDistances[startSegment];

    for (int i = startSegment; i <= endSegment; i++) {
      final Coordinates a = geometry[i];
      final Coordinates b = geometry[i + 1];
      final double segmentLen = segmentLengths[i];

      Coordinates projected;
      double tClamped = 0.0;

      if (segmentLen == 0.0) {
        // Segmento degenerado de longitud cero (puntos consecutivos idénticos)
        projected = a;
        tClamped = 0.0;
      } else {
        // Proyección ortogonal en espacio métrico tangente local (equirrectangular con corrección de latitud media)
        final double latMeanRad =
            ((a.latitude + b.latitude) / 2.0) * (pi / 180.0);
        final double cosLat = cos(latMeanRad);

        // Diferencia longitudinal con tratamiento riguroso del cruce del antimeridiano (+180 / -180)
        double deltaLonAB = (b.longitude - a.longitude);
        if (deltaLonAB > 180.0) deltaLonAB -= 360.0;
        if (deltaLonAB < -180.0) deltaLonAB += 360.0;
        final double dxAB = deltaLonAB * cosLat;
        final double dyAB = b.latitude - a.latitude;

        double deltaLonAP = (currentPosition.longitude - a.longitude);
        if (deltaLonAP > 180.0) deltaLonAP -= 360.0;
        if (deltaLonAP < -180.0) deltaLonAP += 360.0;
        final double dxAP = deltaLonAP * cosLat;
        final double dyAP = currentPosition.latitude - a.latitude;

        final double lenSq = dxAB * dxAB + dyAB * dyAB;
        if (lenSq > 0.0) {
          final double t = (dxAP * dxAB + dyAP * dyAB) / lenSq;
          tClamped = t.clamp(0.0, 1.0);
        }

        if (tClamped == 0.0) {
          projected = a;
        } else if (tClamped == 1.0) {
          projected = b;
        } else {
          final double interpLat =
              a.latitude + tClamped * (b.latitude - a.latitude);
          double interpLon = a.longitude + tClamped * deltaLonAB;
          if (interpLon > 180.0) interpLon -= 360.0;
          if (interpLon < -180.0) interpLon += 360.0;
          if (interpLon > 180.0) interpLon = 180.0;
          if (interpLon < -180.0) interpLon = -180.0;
          projected = Coordinates(interpLat, interpLon);
        }
      }

      final double distanceToP = currentPosition.distanceTo(projected);

      // Desempate determinista estricto (<): si dos segmentos equidistan exactamente de P,
      // se preserva el segmento más temprano en el itinerario para evitar saltos hacia adelante sin estado.
      if (distanceToP < minDistanceToRoute) {
        minDistanceToRoute = distanceToP;
        bestSegmentIndex = i;
        bestProjectedPoint = projected;
        bestTraveledAlongGeometry =
            cumulativeDistances[i] + (tClamped * segmentLen);
      }
    }

    // 3. Manejo de rutas degeneradas de longitud total cero
    final double effectiveTotal = totalDistanceMeters ?? totalGeomDist;

    if (effectiveTotal == 0.0) {
      return RouteProgress(
        distanceTraveledMeters: 0.0,
        remainingDistanceMeters: 0.0,
        progressPercentage: 100.0,
        projectedPoint: bestProjectedPoint,
        distanceToRouteMeters: minDistanceToRoute,
        closestSegmentIndex: bestSegmentIndex,
      );
    }

    if (totalGeomDist == 0.0) {
      // effectiveTotal > 0.0 pero la geometría tiene longitud cero (puntos coincidentes).
      // Es matemáticamente imposible proyectar avance sin inventar un porcentaje arbitrario.
      throw ArgumentError.value(
        geometry,
        'geometry',
        'La geometría de la ruta está compuesta por puntos coincidentes (distancia geométrica total de 0.0 m), '
            'lo que impide determinar el progreso espacial para una ruta con distancia total positiva ($totalDistanceMeters m).',
      );
    }

    // 4. Cálculo de proporción geométrica y traslación a distancias de carretera
    final double progressRatio = (bestTraveledAlongGeometry / totalGeomDist)
        .clamp(0.0, 1.0);

    final double traveled;
    final double remaining;

    if (totalDistanceMeters != null) {
      traveled = (progressRatio * totalDistanceMeters).clamp(
        0.0,
        totalDistanceMeters,
      );
      // remaining = total - traveled garantiza que remaining <= totalDistanceMeters y coherencia de suma dentro de IEEE 754
      remaining = (totalDistanceMeters - traveled).clamp(
        0.0,
        totalDistanceMeters,
      );
    } else {
      traveled = bestTraveledAlongGeometry.clamp(0.0, totalGeomDist);
      remaining = (totalGeomDist - traveled).clamp(0.0, totalGeomDist);
    }

    if (!traveled.isFinite || !remaining.isFinite) {
      throw StateError(
        'Los cálculos de distancia produjeron valores no finitos.',
      );
    }

    double percentage = (progressRatio * 100.0).clamp(0.0, 100.0);
    if (percentage == -0.0) percentage = 0.0;

    return RouteProgress(
      distanceTraveledMeters: traveled,
      remainingDistanceMeters: remaining,
      progressPercentage: percentage,
      projectedPoint: bestProjectedPoint,
      distanceToRouteMeters: minDistanceToRoute,
      closestSegmentIndex: bestSegmentIndex,
    );
  }

  /// Calcula el progreso de una ruta directamente a partir de un [RoutePlan].
  ///
  /// Utiliza [routePlan.geometry] y [routePlan.totalDistanceMeters] para
  /// asegurar consistencia estricta con las invariantes de la entidad.
  ///
  /// Parámetros:
  /// - [routePlan]: Plan de ruta activo cuyo trazado y distancias se emplearán.
  /// - [currentPosition]: Ubicación actual que se desea proyectar.
  /// - [lastKnownSegmentIndex]: Índice de segmento mínimo a evaluar (opcional).
  ///   ADVERTENCIA: Excluye segmentos previos; por ende, puede ocultar retrocesos reales
  ///   si se suministra un índice desactualizado.
  /// - [maxSegmentLookahead]: Número máximo de segmentos adicionales a evaluar hacia adelante (opcional).
  RouteProgress calculateForRoutePlan({
    required RoutePlan routePlan,
    required Coordinates currentPosition,
    int? lastKnownSegmentIndex,
    int? maxSegmentLookahead,
  }) {
    return calculate(
      geometry: routePlan.geometry,
      currentPosition: currentPosition,
      totalDistanceMeters: routePlan.totalDistanceMeters,
      lastKnownSegmentIndex: lastKnownSegmentIndex,
      maxSegmentLookahead: maxSegmentLookahead,
    );
  }
}
