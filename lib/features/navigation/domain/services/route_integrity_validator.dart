import '../../../../domain/entities/coordinates.dart';
import '../entities/access_restriction.dart';

/// Estado de integridad y transitabilidad de una ruta calculada frente a la red vial física.
enum RouteValidationStatus {
  /// Ruta con trazado continuo, acceso público permitido y conectividad adecuada.
  viable,

  /// Restricción de acceso confirmada en el trazado (ej. access=private, motor_vehicle=no, vehicle=no, barrier=gate/cerrojo).
  /// Esta vía no está disponible para el público y no debe recomendarse como ruta de libre tránsito.
  confirmedRestrictedAccess,

  /// La calzada vehicular finaliza lejos del destino (> 300 m), indicando posible desconexión vial antes del objetivo.
  destinationGapWarning,

  /// Información cartográfica insuficiente para confirmar permisos de acceso o transitabilidad pública.
  unconfirmedTransitability,

  /// Geometría inválida o corrupta (menos de 2 puntos válidos, coordenadas no finitas o fuera de rango geodésico).
  invalidGeometry,
}

/// Resultado de la verificación de integridad, conectividad y accesibilidad de una ruta vial.
class RouteValidationResult {
  final RouteValidationStatus status;
  final List<String> warnings;
  final double destinationGapMeters;
  final bool hasRestrictedAccess;
  final bool hasUnconfirmedTransitability;
  final bool hasDestinationGap;
  final AccessRestrictionRecord? detectedRestriction;

  /// Siempre false para rutas calculadas por datos públicos sin validación en campo.
  final bool isFieldVerified;

  const RouteValidationResult({
    required this.status,
    this.warnings = const [],
    this.destinationGapMeters = 0.0,
    this.hasRestrictedAccess = false,
    this.hasUnconfirmedTransitability = false,
    this.hasDestinationGap = false,
    this.detectedRestriction,
    this.isFieldVerified = false,
  });

  /// Indica si la geometría es coherente y procesable.
  bool get isValid => status != RouteValidationStatus.invalidGeometry;

  /// Indica si la ruta es transitable por el público general (sin restricciones de acceso confirmadas).
  bool get isPubliclyPassable =>
      isValid &&
      status != RouteValidationStatus.confirmedRestrictedAccess &&
      !hasRestrictedAccess;

  /// Indica si hay evidencia confirmada de restricción de acceso vehicular.
  bool get isConfirmedRestricted =>
      status == RouteValidationStatus.confirmedRestrictedAccess ||
      hasRestrictedAccess;

  RouteValidationResult copyWith({
    RouteValidationStatus? status,
    List<String>? warnings,
    double? destinationGapMeters,
    bool? hasRestrictedAccess,
    bool? hasUnconfirmedTransitability,
    bool? hasDestinationGap,
    AccessRestrictionRecord? detectedRestriction,
    bool? isFieldVerified,
  }) {
    return RouteValidationResult(
      status: status ?? this.status,
      warnings: warnings ?? this.warnings,
      destinationGapMeters: destinationGapMeters ?? this.destinationGapMeters,
      hasRestrictedAccess: hasRestrictedAccess ?? this.hasRestrictedAccess,
      hasUnconfirmedTransitability:
          hasUnconfirmedTransitability ?? this.hasUnconfirmedTransitability,
      hasDestinationGap: hasDestinationGap ?? this.hasDestinationGap,
      detectedRestriction: detectedRestriction ?? this.detectedRestriction,
      isFieldVerified: isFieldVerified ?? this.isFieldVerified,
    );
  }

  bool get hasWarnings =>
      warnings.isNotEmpty || status != RouteValidationStatus.viable;

  @override
  String toString() =>
      'RouteValidationResult(status: $status, warnings: ${warnings.length}, gap: ${destinationGapMeters.toStringAsFixed(1)}m)';
}

/// Validador de trazado, conectividad y restricciones de acceso para motocicletas.
class RouteIntegrityValidator {
  /// Umbral en metros a partir del cual se alerta al motociclista de que la calzada vehicular
  /// finaliza a una distancia considerable del destino exacto.
  static const double maxStandardDestinationGapMeters = 300.0;

  static RouteValidationResult validate({
    required List<Coordinates> geometry,
    required Coordinates origin,
    required Coordinates destination,
    List<Map<String, dynamic>>? rawSteps,
    List<int>? annotationNodes,
    RoadAccessRestrictionRegistry? restrictionRegistry,
  }) {
    final warnings = <String>[];

    // 1. Control de integridad geométrica
    if (geometry.length < 2) {
      return const RouteValidationResult(
        status: RouteValidationStatus.invalidGeometry,
        warnings: [
          'La geometría de la ruta está vacía o contiene menos de 2 puntos válidos.',
        ],
      );
    }

    for (final pt in geometry) {
      if (!pt.latitude.isFinite || !pt.longitude.isFinite) {
        return const RouteValidationResult(
          status: RouteValidationStatus.invalidGeometry,
          warnings: [
            'Se detectaron coordenadas no finitas o inválidas en el trazado.',
          ],
        );
      }
      if (pt.latitude < -90.0 ||
          pt.latitude > 90.0 ||
          pt.longitude < -180.0 ||
          pt.longitude > 180.0) {
        return const RouteValidationResult(
          status: RouteValidationStatus.invalidGeometry,
          warnings: [
            'Se detectaron coordenadas fuera del rango geodésico admisible.',
          ],
        );
      }
    }

    // 2. Inspección rigurosa de pasos de maniobra y restricciones de acceso
    bool hasRestrictedAccess = false;
    bool hasUnconfirmedTransitability = false;
    final confirmedReasons = <String>[];
    AccessRestrictionRecord? detectedRecord;

    // 2.1 Verificación contra el registro territorial de restricciones de acceso (portones, vías privadas)
    final registry = restrictionRegistry ?? RoadAccessRestrictionRegistry();
    final foundRecord = registry.findRestrictionAlongPath(
      geometry,
      nodeIds: annotationNodes,
    );
    if (foundRecord != null) {
      hasRestrictedAccess = true;
      detectedRecord = foundRecord;
      confirmedReasons.add(
        '${foundRecord.description} [Evidencia: ${foundRecord.sourceEvidence}]',
      );
    }

    if (rawSteps != null) {
      for (final step in rawSteps) {
        final access = (step['access'] as String? ?? '').toLowerCase().trim();
        final motorVehicle = (step['motor_vehicle'] as String? ?? '')
            .toLowerCase()
            .trim();
        final vehicle = (step['vehicle'] as String? ?? '').toLowerCase().trim();
        final barrier = (step['barrier'] as String? ?? '').toLowerCase().trim();
        final intersections = step['intersections'] as List<dynamic>?;

        // Comprobación de restricciones confirmadas para vehículos
        final isAccessPrivate =
            access == 'private' || access == 'no' || access == 'restricted';
        final isMotorVehicleRestricted =
            motorVehicle == 'no' ||
            motorVehicle == 'private' ||
            motorVehicle == 'restricted';
        final isVehicleRestricted =
            vehicle == 'no' || vehicle == 'private' || vehicle == 'restricted';
        final isLockedBarrier =
            barrier == 'gate' ||
            barrier == 'lift_gate' ||
            barrier == 'bollard' ||
            barrier == 'chain' ||
            barrier == 'fence' ||
            barrier == 'spikes';

        if (isAccessPrivate ||
            isMotorVehicleRestricted ||
            isVehicleRestricted ||
            isLockedBarrier) {
          hasRestrictedAccess = true;
          final tagDesc = isAccessPrivate
              ? 'access=$access'
              : (isMotorVehicleRestricted
                    ? 'motor_vehicle=$motorVehicle'
                    : (isVehicleRestricted
                          ? 'vehicle=$vehicle'
                          : 'barrier=$barrier (portón/cerrojo)'));
          confirmedReasons.add(tagDesc);
        } else if (access == 'unconfirmed' ||
            access == 'unknown' ||
            step['unconfirmed'] == true) {
          hasUnconfirmedTransitability = true;
        }

        // Inspección de clases en intersecciones
        if (intersections != null) {
          for (final intersection in intersections) {
            if (intersection is Map<String, dynamic>) {
              final classes = intersection['classes'] as List<dynamic>?;
              if (classes != null) {
                if (classes.contains('restricted') ||
                    classes.contains('private')) {
                  hasRestrictedAccess = true;
                  confirmedReasons.add(
                    'intersección clasificada como privada/restringida',
                  );
                }
                if (classes.contains('ferry')) {
                  warnings.add(
                    'La ruta incluye cruce en ferry o transbordador fluvial.',
                  );
                }
              }
            }
          }
        }
      }
    }

    if (hasRestrictedAccess) {
      final reasonsStr = confirmedReasons.toSet().join(', ');
      warnings.add(
        'Acceso restringido o vía privada confirmada ($reasonsStr). '
        'Esta vía no está disponible para libre tránsito público.',
      );
    }

    if (hasUnconfirmedTransitability && !hasRestrictedAccess) {
      warnings.add(
        'Información de acceso no confirmada en la cartografía para el tramo final. '
        'Conduce con precaución.',
      );
    }

    // 3. Control de aproximación final al destino
    // Se valida la distancia entre el último punto de la geometría y el destino buscado.
    final lastPoint = geometry.last;
    final destinationGapMeters = lastPoint.distanceTo(destination);

    bool hasDestinationGap = false;
    if (destinationGapMeters > maxStandardDestinationGapMeters) {
      hasDestinationGap = true;
      warnings.add(
        'La calzada vehicular finaliza a ${destinationGapMeters.toStringAsFixed(0)} m del punto exacto. Verifica la aproximación final.',
      );
    }

    // 4. Determinar estado sintético de validación
    final RouteValidationStatus status;
    if (hasRestrictedAccess) {
      status = RouteValidationStatus.confirmedRestrictedAccess;
    } else if (hasDestinationGap) {
      status = RouteValidationStatus.destinationGapWarning;
    } else if (hasUnconfirmedTransitability) {
      status = RouteValidationStatus.unconfirmedTransitability;
    } else {
      status = RouteValidationStatus.viable;
    }

    return RouteValidationResult(
      status: status,
      warnings: warnings,
      destinationGapMeters: destinationGapMeters,
      hasRestrictedAccess: hasRestrictedAccess,
      hasUnconfirmedTransitability: hasUnconfirmedTransitability,
      hasDestinationGap: hasDestinationGap,
      detectedRestriction: detectedRecord,
      isFieldVerified: false,
    );
  }
}
