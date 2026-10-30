import '../../../bridge/domain/entities/bridge_instruction_status.dart';
import '../../../bridge/domain/entities/bridge_navigation_instruction.dart';
import '../../../bridge/domain/entities/bridge_source_type.dart';
import 'navigation_diagnostic_logger.dart';

/// Acción resultante tras procesar una notificación en el árbitro automático.
enum AutoArbitrationAction {
  /// Notificación descartada (banner genérico, vacía, desconocida, fuera de orden o modo interno).
  ignored,

  /// Primera instrucción válida que activa la fuente de navegación hacia el Tripper.
  activated,

  /// Nueva instrucción válida para la misma fuente activa.
  updated,

  /// Instrucción idéntica consecutiva (se omite reenvío BLE innecesario).
  duplicate,

  /// Otra fuente con instrucción válida más reciente toma el control del viaje.
  switched,

  /// La fuente activa canceló o finalizó la ruta y no hay otra fuente disponible.
  sourceEnded,

  /// La fuente activa finalizó, pero la fuente alternativa tiene una ruta activa y retoma el control.
  fallbackActivated,

  /// La instrucción activa expiró por inactividad y no hay otra fuente válida.
  expired,

  /// Sin ninguna navegación externa activa.
  noActiveNavigation,
}

/// Estado independiente retenido por cada fuente externa compatible (Waze / Google Maps).
class ExternalSourceState {
  final BridgeSourceType source;
  BridgeNavigationInstruction? latestValidInstruction;
  DateTime? latestValidTimestamp;
  String? lastNotificationKey;
  DateTime? lastEventTimestamp;
  bool hasActiveRoute;

  ExternalSourceState({
    required this.source,
    this.latestValidInstruction,
    this.latestValidTimestamp,
    this.lastNotificationKey,
    this.lastEventTimestamp,
    this.hasActiveRoute = false,
  });

  bool isUnexpired({
    DateTime? now,
    Duration maxAge = const Duration(seconds: 45),
  }) {
    if (!hasActiveRoute ||
        latestValidInstruction == null ||
        latestValidTimestamp == null) {
      return false;
    }
    final currentTime = now ?? DateTime.now();
    return currentTime.difference(latestValidTimestamp!) <= maxAge;
  }

  void clear() {
    latestValidInstruction = null;
    latestValidTimestamp = null;
    lastNotificationKey = null;
    lastEventTimestamp = null;
    hasActiveRoute = false;
  }
}

/// Resultado tipado devuelto por el árbitro automático de fuentes de navegación.
class AutoArbitrationResult {
  final AutoArbitrationAction action;
  final BridgeSourceType? previousSource;
  final BridgeSourceType? newSource;
  final BridgeNavigationInstruction? instruction;
  final String reason;
  final CorrelatedBridgeTraceStep traceStep;

  const AutoArbitrationResult({
    required this.action,
    required this.reason,
    required this.traceStep,
    this.previousSource,
    this.newSource,
    this.instruction,
  });

  bool get shouldTransmitToBle =>
      action == AutoArbitrationAction.activated ||
      action == AutoArbitrationAction.updated ||
      action == AutoArbitrationAction.switched ||
      action == AutoArbitrationAction.fallbackActivated;

  bool get shouldStopBleNavigation =>
      action == AutoArbitrationAction.sourceEnded ||
      action == AutoArbitrationAction.expired ||
      action == AutoArbitrationAction.noActiveNavigation;
}

/// Árbitro determinista para la selección automática de fuente de navegación (AUTO).
///
/// Gestiona la concurrencia entre Waze y Google Maps:
/// - Mantiene estados independientes por paquete.
/// - Cambia de fuente ÚNICAMENTE ante instrucciones turn-by-turn válidas y reconocidas.
/// - Resuelve concurrencia por la instrucción válida más reciente en timestamp.
/// - Desplaza fuentes canceladas hacia fuentes secundarias activas (fallback) o pasa a sin navegación.
/// - Bloquea interferencias cuando la navegación interna propia de RoadCompanion está activa.
class AutoNavigationSourceArbiter {
  final Duration stalenessTimeout;
  final Map<BridgeSourceType, ExternalSourceState> _sources = {
    BridgeSourceType.waze: ExternalSourceState(source: BridgeSourceType.waze),
    BridgeSourceType.googleMaps: ExternalSourceState(
      source: BridgeSourceType.googleMaps,
    ),
  };

  BridgeSourceType? _activeSource;
  BridgeNavigationInstruction? _currentActiveInstruction;
  bool _isInternalNavigationActive = false;

  AutoNavigationSourceArbiter({
    this.stalenessTimeout = const Duration(seconds: 45),
  });

  /// Fuente externa que ostenta el control activo de navegación (`null` = sin navegación activa).
  BridgeSourceType? get activeSource => _activeSource;

  /// Última instrucción turn-by-turn válida gobernando el Tripper Pod.
  BridgeNavigationInstruction? get currentActiveInstruction =>
      _currentActiveInstruction;

  /// Indica si la navegación interna de RoadCompanion está en curso.
  bool get isInternalNavigationActive => _isInternalNavigationActive;

  /// Inspecciona el estado retenido de una fuente específica.
  ExternalSourceState? getSourceState(BridgeSourceType source) =>
      _sources[source];

  /// Activa o desactiva la prioridad exclusiva de la navegación interna de RoadCompanion.
  void setInternalNavigationActive(bool active) {
    _isInternalNavigationActive = active;
    if (active) {
      // Al activar navegación interna, las fuentes externas ceden el control inmediatamente.
      _activeSource = null;
      _currentActiveInstruction = null;
    }
  }

  /// Restablece completamente el árbitro (nueva sesión o limpieza manual).
  void reset() {
    _sources[BridgeSourceType.waze]?.clear();
    _sources[BridgeSourceType.googleMaps]?.clear();
    _activeSource = null;
    _currentActiveInstruction = null;
    _isInternalNavigationActive = false;
  }

  /// Procesa una instrucción parseada desde una notificación de Waze o Google Maps.
  AutoArbitrationResult processInstruction(
    BridgeNavigationInstruction instruction, {
    required String correlationId,
    String? notificationKey,
    bool isRemoved = false,
  }) {
    final eventSource = instruction.source;
    final sourceState = _sources[eventSource];

    // Log obligatorio: candidato detectado
    NavigationDiagnosticLogger.logCorrelatedEvent(
      step: CorrelatedBridgeTraceStep.sourceCandidateDetected,
      eventId: correlationId,
      source: eventSource.packageName,
      availableContent:
          'key=${notificationKey ?? "n/a"}, isRemoved=$isRemoved, status=${instruction.status.name}',
      result: 'candidate_detected',
      timestamp: instruction.receivedAt,
    );

    // 1. Regla: si la navegación interna está en ejecución explícita, ignorar fuentes externas.
    if (_isInternalNavigationActive) {
      final reason =
          'Navegación interna explícita activa: ignorando notificación de ${eventSource.displayName}';
      NavigationDiagnosticLogger.logCorrelatedEvent(
        step: CorrelatedBridgeTraceStep.sourceInstructionIgnored,
        eventId: correlationId,
        source: eventSource.packageName,
        availableContent: instruction.rawText,
        result: 'ignored_internal_precedence',
        transitionReason: reason,
        rejectionReason: reason,
        timestamp: instruction.receivedAt,
      );
      return AutoArbitrationResult(
        action: AutoArbitrationAction.ignored,
        reason: reason,
        traceStep: CorrelatedBridgeTraceStep.sourceInstructionIgnored,
        previousSource: _activeSource,
        newSource: _activeSource,
        instruction: instruction,
      );
    }

    // 2. Manejo de eliminación / cancelación de notificación (isRemoved = true)
    if (isRemoved || instruction.status == BridgeInstructionStatus.stale) {
      if (sourceState == null ||
          (!sourceState.hasActiveRoute &&
              sourceState.latestValidInstruction == null)) {
        // Eliminación de una notificación sin instrucción previa en esta fuente
        final reason =
            'Eliminación de notificación sin instrucción previa activa para ${eventSource.displayName}';
        NavigationDiagnosticLogger.logCorrelatedEvent(
          step: CorrelatedBridgeTraceStep.sourceInstructionIgnored,
          eventId: correlationId,
          source: eventSource.packageName,
          availableContent: 'isRemoved=true (sin ruta previa)',
          result: 'ignored_orphan_removal',
          transitionReason: reason,
          rejectionReason: reason,
          timestamp: instruction.receivedAt,
        );
        return AutoArbitrationResult(
          action: AutoArbitrationAction.ignored,
          reason: reason,
          traceStep: CorrelatedBridgeTraceStep.sourceInstructionIgnored,
          previousSource: _activeSource,
          newSource: _activeSource,
        );
      }

      // Finalizar la ruta de esta fuente específica
      sourceState.clear();
      NavigationDiagnosticLogger.logCorrelatedEvent(
        step: CorrelatedBridgeTraceStep.sourceNavigationEnded,
        eventId: correlationId,
        source: eventSource.packageName,
        availableContent: 'Ruta finalizada o cancelada por el usuario',
        result: 'navigation_ended',
        transitionReason:
            'Notificación eliminada de ${eventSource.displayName}',
        timestamp: instruction.receivedAt,
      );

      // Si la fuente cancelada no era la fuente activa, la fuente activa sigue intacta
      if (_activeSource != eventSource) {
        return AutoArbitrationResult(
          action: AutoArbitrationAction.ignored,
          reason:
              'Cancelación de ${eventSource.displayName} no afectó a la fuente activa ${_activeSource?.displayName}',
          traceStep: CorrelatedBridgeTraceStep.sourceNavigationEnded,
          previousSource: _activeSource,
          newSource: _activeSource,
        );
      }

      // La fuente activa era esta: buscar si la otra fuente tiene ruta activa vigente
      final alternativeSource = eventSource == BridgeSourceType.waze
          ? BridgeSourceType.googleMaps
          : BridgeSourceType.waze;
      final alternativeState = _sources[alternativeSource];

      if (alternativeState != null &&
          alternativeState.isUnexpired(
            now: instruction.receivedAt,
            maxAge: stalenessTimeout,
          )) {
        // Fallback exitoso: la otra fuente retoma el control del Tripper
        final prev = _activeSource;
        _activeSource = alternativeSource;
        _currentActiveInstruction = alternativeState.latestValidInstruction;

        final reason =
            '${eventSource.displayName} finalizó. Fallback activado hacia ${alternativeSource.displayName}';
        NavigationDiagnosticLogger.logCorrelatedEvent(
          step: CorrelatedBridgeTraceStep.sourceFallbackActivated,
          eventId: correlationId,
          source: alternativeSource.packageName,
          availableContent: _currentActiveInstruction?.rawText ?? '',
          result: 'fallback_activated',
          previousSource: prev?.displayName,
          newSource: alternativeSource.displayName,
          maneuver: _currentActiveInstruction?.maneuverType.name,
          distanceMeters: _currentActiveInstruction?.distanceMeters,
          transitionReason: reason,
          timestamp: instruction.receivedAt,
        );

        return AutoArbitrationResult(
          action: AutoArbitrationAction.fallbackActivated,
          reason: reason,
          traceStep: CorrelatedBridgeTraceStep.sourceFallbackActivated,
          previousSource: prev,
          newSource: alternativeSource,
          instruction: _currentActiveInstruction,
        );
      } else {
        // Sin otra fuente con ruta vigente: pasar a sin navegación
        final prev = _activeSource;
        _activeSource = null;
        _currentActiveInstruction = null;

        final reason =
            '${eventSource.displayName} finalizó y no hay otra fuente activa: sin navegación';
        NavigationDiagnosticLogger.logCorrelatedEvent(
          step: CorrelatedBridgeTraceStep.sourceNoActiveNavigation,
          eventId: correlationId,
          source: eventSource.packageName,
          availableContent: 'Sin fuentes con rutas vigentes',
          result: 'no_active_navigation',
          previousSource: prev?.displayName,
          newSource: 'none',
          transitionReason: reason,
          timestamp: instruction.receivedAt,
        );

        final staleInstruction = instruction.asStale(discardReason: reason);
        return AutoArbitrationResult(
          action: AutoArbitrationAction.sourceEnded,
          reason: reason,
          traceStep: CorrelatedBridgeTraceStep.sourceNoActiveNavigation,
          previousSource: prev,
          newSource: null,
          instruction: staleInstruction,
        );
      }
    }

    // 3. Descartar eventos fuera de orden temporal para la misma fuente
    if (sourceState != null &&
        sourceState.lastEventTimestamp != null &&
        instruction.receivedAt.isBefore(sourceState.lastEventTimestamp!)) {
      final reason =
          'Notificación antigua recibida después de una nueva en ${eventSource.displayName} (${instruction.receivedAt} < ${sourceState.lastEventTimestamp})';
      NavigationDiagnosticLogger.logCorrelatedEvent(
        step: CorrelatedBridgeTraceStep.sourceInstructionIgnored,
        eventId: correlationId,
        source: eventSource.packageName,
        availableContent: instruction.rawText,
        result: 'out_of_order',
        transitionReason: reason,
        rejectionReason: reason,
        timestamp: instruction.receivedAt,
      );
      return AutoArbitrationResult(
        action: AutoArbitrationAction.ignored,
        reason: reason,
        traceStep: CorrelatedBridgeTraceStep.sourceInstructionIgnored,
        previousSource: _activeSource,
        newSource: _activeSource,
        instruction: instruction,
      );
    }

    sourceState?.lastEventTimestamp = instruction.receivedAt;
    sourceState?.lastNotificationKey = notificationKey;

    // 4. Regla: Notificaciones vacías, banners genéricos ("En ejecución"), recálculos sin maniobra y desconocidos
    if (!instruction.isCompatibleWithTripper) {
      final reason = instruction.isAppRunningNotification
          ? 'Banner genérico "En ejecución / Toca para abrir" de ${eventSource.displayName} no contiene maniobra'
          : (instruction.isEmptyNotification
                ? 'Notificación vacía de ${eventSource.displayName}'
                : (instruction.discardReason ??
                      'Instrucción desconocida o sin distancia válida en ${eventSource.displayName}'));

      NavigationDiagnosticLogger.logCorrelatedEvent(
        step: CorrelatedBridgeTraceStep.sourceInstructionIgnored,
        eventId: correlationId,
        source: eventSource.packageName,
        availableContent: instruction.rawText,
        result: 'ignored_not_compatible',
        transitionReason: reason,
        rejectionReason: reason,
        timestamp: instruction.receivedAt,
      );

      return AutoArbitrationResult(
        action: AutoArbitrationAction.ignored,
        reason: reason,
        traceStep: CorrelatedBridgeTraceStep.sourceInstructionIgnored,
        previousSource: _activeSource,
        newSource: _activeSource,
        instruction: instruction,
      );
    }

    // 5. Instrucción válida y reconocida: aceptar candidato
    NavigationDiagnosticLogger.logCorrelatedEvent(
      step: CorrelatedBridgeTraceStep.sourceInstructionAccepted,
      eventId: correlationId,
      source: eventSource.packageName,
      availableContent: instruction.rawText,
      result: 'instruction_accepted',
      maneuver: instruction.maneuverType.name,
      distanceMeters: instruction.distanceMeters,
      timestamp: instruction.receivedAt,
    );

    // Actualizar estado retenido de esta fuente
    sourceState?.latestValidInstruction = instruction;
    sourceState?.latestValidTimestamp = instruction.receivedAt;
    sourceState?.hasActiveRoute = true;

    // 6. Decisión de activación y cambio de fuente (Arbiter)
    if (_activeSource == null) {
      // Activación inicial
      _activeSource = eventSource;
      _currentActiveInstruction = instruction;

      final reason =
          'Primera maniobra válida recibida: activando ${eventSource.displayName}';
      NavigationDiagnosticLogger.logCorrelatedEvent(
        step: CorrelatedBridgeTraceStep.sourceActivated,
        eventId: correlationId,
        source: eventSource.packageName,
        availableContent: instruction.rawText,
        result: 'source_activated',
        previousSource: 'none',
        newSource: eventSource.displayName,
        maneuver: instruction.maneuverType.name,
        distanceMeters: instruction.distanceMeters,
        transitionReason: reason,
        timestamp: instruction.receivedAt,
      );

      return AutoArbitrationResult(
        action: AutoArbitrationAction.activated,
        reason: reason,
        traceStep: CorrelatedBridgeTraceStep.sourceActivated,
        previousSource: null,
        newSource: eventSource,
        instruction: instruction,
      );
    }

    if (_activeSource == eventSource) {
      // Misma fuente activa: comprobar si es duplicada
      if (_currentActiveInstruction != null &&
          !_currentActiveInstruction!.isStale &&
          _currentActiveInstruction!.maneuverType == instruction.maneuverType &&
          _currentActiveInstruction!.distanceMeters ==
              instruction.distanceMeters &&
          _currentActiveInstruction!.destinationStreet ==
              instruction.destinationStreet &&
          _currentActiveInstruction!.rawText == instruction.rawText) {
        return AutoArbitrationResult(
          action: AutoArbitrationAction.duplicate,
          reason:
              'Instrucción duplicada consecutiva de ${eventSource.displayName}',
          traceStep: CorrelatedBridgeTraceStep.instructionParsed,
          previousSource: eventSource,
          newSource: eventSource,
          instruction: instruction,
        );
      }

      _currentActiveInstruction = instruction;
      return AutoArbitrationResult(
        action: AutoArbitrationAction.updated,
        reason: 'Actualización de maniobra para ${eventSource.displayName}',
        traceStep: CorrelatedBridgeTraceStep.sourceInstructionAccepted,
        previousSource: eventSource,
        newSource: eventSource,
        instruction: instruction,
      );
    }

    // 7. Otra fuente distinta a la activa tiene una maniobra válida
    final currentActiveState = _sources[_activeSource];
    final activeTimestamp =
        currentActiveState?.latestValidTimestamp ??
        DateTime.fromMillisecondsSinceEpoch(0);

    if (instruction.receivedAt.isAfter(activeTimestamp)) {
      // La nueva instrucción es más reciente que la última de la fuente activa: cambio de fuente
      final prev = _activeSource;
      _activeSource = eventSource;
      _currentActiveInstruction = instruction;

      final reason =
          'Cambio de fuente: ${eventSource.displayName} (${instruction.receivedAt}) más reciente que ${prev?.displayName} ($activeTimestamp)';
      NavigationDiagnosticLogger.logCorrelatedEvent(
        step: CorrelatedBridgeTraceStep.sourceSwitched,
        eventId: correlationId,
        source: eventSource.packageName,
        availableContent: instruction.rawText,
        result: 'source_switched',
        previousSource: prev?.displayName,
        newSource: eventSource.displayName,
        maneuver: instruction.maneuverType.name,
        distanceMeters: instruction.distanceMeters,
        transitionReason: reason,
        timestamp: instruction.receivedAt,
      );

      return AutoArbitrationResult(
        action: AutoArbitrationAction.switched,
        reason: reason,
        traceStep: CorrelatedBridgeTraceStep.sourceSwitched,
        previousSource: prev,
        newSource: eventSource,
        instruction: instruction,
      );
    } else {
      // Evento no es más reciente que la fuente activa actual: ignorar cambio
      final reason =
          'Instrucción de ${eventSource.displayName} no es más reciente que la fuente activa actual (${_activeSource?.displayName})';
      NavigationDiagnosticLogger.logCorrelatedEvent(
        step: CorrelatedBridgeTraceStep.sourceInstructionIgnored,
        eventId: correlationId,
        source: eventSource.packageName,
        availableContent: instruction.rawText,
        result: 'ignored_older_than_active',
        transitionReason: reason,
        rejectionReason: reason,
        timestamp: instruction.receivedAt,
      );

      return AutoArbitrationResult(
        action: AutoArbitrationAction.ignored,
        reason: reason,
        traceStep: CorrelatedBridgeTraceStep.sourceInstructionIgnored,
        previousSource: _activeSource,
        newSource: _activeSource,
        instruction: instruction,
      );
    }
  }

  /// Verifica expiración por inactividad de las fuentes.
  AutoArbitrationResult? checkTimeouts({DateTime? now}) {
    if (_activeSource == null) return null;
    final currentTime = now ?? DateTime.now();
    final activeState = _sources[_activeSource];

    if (activeState == null ||
        !activeState.isUnexpired(now: currentTime, maxAge: stalenessTimeout)) {
      final prev = _activeSource;
      final expiredInstruction = _currentActiveInstruction;

      NavigationDiagnosticLogger.logCorrelatedEvent(
        step: CorrelatedBridgeTraceStep.sourceInstructionExpired,
        eventId: 'timeout@${currentTime.millisecondsSinceEpoch}',
        source: prev?.packageName ?? 'unknown',
        availableContent: expiredInstruction?.rawText ?? '',
        result: 'source_expired',
        transitionReason:
            'Sin actualizaciones en ${stalenessTimeout.inSeconds}s',
        timestamp: currentTime,
      );

      // Comprobar si la otra fuente está activa y vigente
      final alternative = prev == BridgeSourceType.waze
          ? BridgeSourceType.googleMaps
          : BridgeSourceType.waze;
      final altState = _sources[alternative];

      if (altState != null &&
          altState.isUnexpired(now: currentTime, maxAge: stalenessTimeout)) {
        _activeSource = alternative;
        _currentActiveInstruction = altState.latestValidInstruction;

        final reason =
            '${prev?.displayName} expiró. Fallback activado hacia ${alternative.displayName}';
        NavigationDiagnosticLogger.logCorrelatedEvent(
          step: CorrelatedBridgeTraceStep.sourceFallbackActivated,
          eventId: 'timeout_fallback@${currentTime.millisecondsSinceEpoch}',
          source: alternative.packageName,
          availableContent: _currentActiveInstruction?.rawText ?? '',
          result: 'fallback_activated',
          previousSource: prev?.displayName,
          newSource: alternative.displayName,
          maneuver: _currentActiveInstruction?.maneuverType.name,
          distanceMeters: _currentActiveInstruction?.distanceMeters,
          transitionReason: reason,
          timestamp: currentTime,
        );

        return AutoArbitrationResult(
          action: AutoArbitrationAction.fallbackActivated,
          reason: reason,
          traceStep: CorrelatedBridgeTraceStep.sourceFallbackActivated,
          previousSource: prev,
          newSource: alternative,
          instruction: _currentActiveInstruction,
        );
      } else {
        _activeSource = null;
        _currentActiveInstruction = null;

        final reason =
            '${prev?.displayName} expiró y no hay alternativa activa: sin navegación';
        NavigationDiagnosticLogger.logCorrelatedEvent(
          step: CorrelatedBridgeTraceStep.sourceNoActiveNavigation,
          eventId: 'timeout_ended@${currentTime.millisecondsSinceEpoch}',
          source: prev?.packageName ?? 'unknown',
          availableContent: 'Todas las fuentes expiraron',
          result: 'no_active_navigation',
          previousSource: prev?.displayName,
          newSource: 'none',
          transitionReason: reason,
          timestamp: currentTime,
        );

        final stale = expiredInstruction?.asStale(discardReason: reason);
        return AutoArbitrationResult(
          action: AutoArbitrationAction.expired,
          reason: reason,
          traceStep: CorrelatedBridgeTraceStep.sourceNoActiveNavigation,
          previousSource: prev,
          newSource: null,
          instruction: stale,
        );
      }
    }
    return null;
  }
}
