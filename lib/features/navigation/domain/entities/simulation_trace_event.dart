import 'package:road_companion/domain/entities/coordinates.dart';
import 'package:road_companion/features/navigation/domain/entities/road_curvature.dart';

/// Acción adoptada respecto a la transmisión hacia el Tripper Pod.
enum SimulationTraceAction {
  /// Trama de navegación (0x10 0x11) generada y transmitida por BLE con CRC actualizado.
  transmitted('TRANSMITIDA'),

  /// Maniobra u opcode no soportado en hardware; omitida para evitar desestabilizar el Pod.
  omitted('OMITIDA_HARDWARE'),

  /// Se mantiene la trama anterior en el bucle keepalive (ej. en reposo/pausa).
  reused('REUTILIZADA'),

  /// Actualización pospuesta para no saturar el canal BLE (< 800ms o cambio < umbral).
  throttled('POSPUESTA_THROTTLING'),

  /// Refresco periódico de pantalla activa para mantener el watchdog de 5s del hardware.
  refreshed('REFRESH_PANTALLA'),

  /// Limpieza explícita de paquete al finalizar la sesión de navegación.
  cleared('LIMPIEZA_PANTALLA');

  final String label;
  const SimulationTraceAction(this.label);
}

/// Registro inmutable de trazabilidad por cada actualización de la simulación.
class SimulationTraceEvent {
  /// Marca temporal exacta del evento.
  final DateTime timestamp;

  /// Distancia acumulada recorrida sobre la ruta en metros.
  final double accumulatedDistanceMeters;

  /// Posición virtual interpolada en la calzada.
  final Coordinates? virtualPosition;

  /// Número de paso de maniobra actual (1-based).
  final int stepNumber;

  /// Número de paso de maniobra subsiguiente (si existe).
  final int? nextStepNumber;

  /// Identificador o texto descriptivo de la maniobra activa.
  final String maneuverIdentifier;

  /// Tipo formal de la maniobra vehicular (straight, turnLeft, etc.).
  final String maneuverType;

  /// Opcode de maniobra en hexadecimal (ej. 0x15, 0x09) o null si no está mapeado.
  final String? opcodeHex;

  /// Clasificación local de la curvatura vial calculada por geometría.
  final RoadCurvatureType curvatureType;

  /// Variación angular en grados del cambio de rumbo próximo.
  final double curvatureDeltaDegrees;

  /// Distancia dinámica restante en metros hasta el vértice de la maniobra/curva.
  final int distanceToManeuverMeters;

  /// Trama hexadecimal de 20 bytes enviada al Tripper (o null si se omitió).
  final String? generatedPacketHex;

  /// Acción ejecutada en este ciclo.
  final SimulationTraceAction action;

  /// Razón explícita por la que se transmitió, omitió o reutilizó la trama.
  final String reason;

  /// Tiempo transcurrido en milisegundos desde la última trama de pantalla 10 11 emitida.
  final int? timeSinceLastNavScreenMs;

  /// Estado de conexión BLE actual (ej. Autenticado, Listo para navegación).
  final String? bleConnectionState;

  const SimulationTraceEvent({
    required this.timestamp,
    required this.accumulatedDistanceMeters,
    this.virtualPosition,
    required this.stepNumber,
    this.nextStepNumber,
    required this.maneuverIdentifier,
    required this.maneuverType,
    this.opcodeHex,
    required this.curvatureType,
    required this.curvatureDeltaDegrees,
    required this.distanceToManeuverMeters,
    this.generatedPacketHex,
    required this.action,
    required this.reason,
    this.timeSinceLastNavScreenMs,
    this.bleConnectionState,
  });

  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'accumulatedDistanceMeters': accumulatedDistanceMeters,
      'virtualPosition': virtualPosition != null
          ? {'lat': virtualPosition!.latitude, 'lon': virtualPosition!.longitude}
          : null,
      'stepNumber': stepNumber,
      'nextStepNumber': nextStepNumber,
      'maneuverIdentifier': maneuverIdentifier,
      'maneuverType': maneuverType,
      'opcodeHex': opcodeHex,
      'curvatureType': curvatureType.name,
      'curvatureDeltaDegrees': curvatureDeltaDegrees,
      'distanceToManeuverMeters': distanceToManeuverMeters,
      'generatedPacketHex': generatedPacketHex,
      'action': action.label,
      'reason': reason,
      'timeSinceLastNavScreenMs': timeSinceLastNavScreenMs,
      'bleConnectionState': bleConnectionState,
    };
  }

  @override
  String toString() {
    final hex = generatedPacketHex ?? 'SIN_TRAMA';
    final latLng = virtualPosition != null
        ? '${virtualPosition!.latitude.toStringAsFixed(5)}, ${virtualPosition!.longitude.toStringAsFixed(5)}'
        : 'N/A';
    final sign = curvatureDeltaDegrees >= 0 ? '+' : '';
    final nextStr = nextStepNumber != null ? ' -> Próx #$nextStepNumber' : '';
    final opcStr = opcodeHex != null ? ' [Op: $opcodeHex]' : '';
    final timeStr = timeSinceLastNavScreenMs != null ? ' | ΔtPantalla: ${timeSinceLastNavScreenMs}ms' : '';
    final bleStr = bleConnectionState != null ? ' | BLE: $bleConnectionState' : '';
    return '[${timestamp.toIso8601String().substring(11, 19)}] '
        'Paso #$stepNumber$nextStr ($maneuverType$opcStr) | '
        'DistRestante: ${distanceToManeuverMeters}m | '
        'Pos: ${accumulatedDistanceMeters.toStringAsFixed(1)}m ($latLng) | '
        'Curva: ${curvatureType.displayName} ($sign${curvatureDeltaDegrees.toStringAsFixed(1)}°) | '
        'Acción: ${action.label} | '
        'Trama: $hex | '
        'Motivo: $reason'
        '$timeStr$bleStr';
  }
}
