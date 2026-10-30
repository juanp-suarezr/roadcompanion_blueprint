import 'dart:async';
import '../../../navigation/domain/services/auto_navigation_source_arbiter.dart';
import '../../../navigation/domain/services/navigation_diagnostic_logger.dart';
import '../../domain/entities/bridge_navigation_instruction.dart';
import '../../domain/entities/bridge_source_type.dart';
import '../../domain/services/navigation_instruction_parser.dart';
import 'bridge_native_channel.dart';

/// Fuente reactiva de instrucciones de navegación para ESTELA Bridge.
///
/// Recibe eventos de notificaciones capturados por [BridgeNativeChannel],
/// gestiona la selección automática mediante [AutoNavigationSourceArbiter]
/// (o filtra por fuente específica si fue solicitada), rechaza eventos fuera de orden
/// o duplicados y emite modelos tipados [BridgeNavigationInstruction].
class BridgeNavigationSource {
  final BridgeNativeChannel _nativeChannel;
  final NavigationInstructionParser _parser;
  final Duration? staleDuration;
  final AutoNavigationSourceArbiter _arbiter;
  StreamSubscription<BridgeNotificationEvent>? _subscription;
  Timer? _stalenessTimer;
  final StreamController<BridgeNavigationInstruction> _instructionController =
      StreamController<BridgeNavigationInstruction>.broadcast();

  BridgeNavigationInstruction? _lastInstruction;
  DateTime? _lastEventTimestamp;
  BridgeSourceType? _allowedSource;
  bool _externalEnabled;

  BridgeNavigationSource({
    BridgeNativeChannel? nativeChannel,
    NavigationInstructionParser? parser,
    BridgeSourceType? allowedSource,
    bool externalEnabled = true,
    this.staleDuration,
    AutoNavigationSourceArbiter? arbiter,
  }) : _nativeChannel = nativeChannel ?? BridgeNativeChannel(),
       _parser = parser ?? const NavigationInstructionParser(),
       _allowedSource = allowedSource,
       _externalEnabled = externalEnabled,
       _arbiter =
           arbiter ??
           AutoNavigationSourceArbiter(
             stalenessTimeout: staleDuration ?? const Duration(seconds: 45),
           );

  /// Árbitro determinista de concurrencia y selección automática entre Waze y Maps.
  AutoNavigationSourceArbiter get arbiter => _arbiter;

  /// Flujo continuo de instrucciones parseadas y normalizadas.
  Stream<BridgeNavigationInstruction> get instructions =>
      _instructionController.stream;

  /// Última instrucción procesada y retenida en memoria.
  BridgeNavigationInstruction? get lastInstruction => _lastInstruction;

  /// Fuente externa permitida actualmente (`null` acepta Waze y Google Maps si [externalEnabled] es true).
  BridgeSourceType? get allowedSource => _allowedSource;

  /// Indica si la captura de fuentes externas está habilitada (false cuando se elige navegación interna).
  bool get externalEnabled => _externalEnabled;

  /// Habilita o deshabilita por completo la recepción de notificaciones externas (ej. al elegir fuente interna).
  Future<void> setExternalEnabled(bool enabled) async {
    if (_externalEnabled == enabled) return;
    _externalEnabled = enabled;
    _arbiter.setInternalNavigationActive(!enabled);
    if (!enabled) {
      _stalenessTimer?.cancel();
      if (_lastInstruction != null && !_lastInstruction!.isStale) {
        final invalidated = _lastInstruction!.asStale(
          discardReason:
              'Fuente externa deshabilitada al pasar a navegación interna',
        );
        _lastInstruction = null;
        _lastEventTimestamp = null;
        if (!_instructionController.isClosed) {
          _instructionController.add(invalidated);
        }
      } else {
        _lastInstruction = null;
        _lastEventTimestamp = null;
      }
      await _nativeChannel.setSelectedSourcePackage('none');
    } else {
      final pkg = _allowedSource == BridgeSourceType.waze
          ? 'com.waze'
          : (_allowedSource == BridgeSourceType.googleMaps
                ? 'com.google.android.apps.maps'
                : 'all');
      await _nativeChannel.setSelectedSourcePackage(pkg);
    }
  }

  /// Cambia la fuente externa permitida e invalida de inmediato datos de otra fuente.
  Future<void> setAllowedSource(BridgeSourceType? source) async {
    _externalEnabled = true;
    _arbiter.setInternalNavigationActive(false);
    if (_allowedSource != source) {
      _allowedSource = source;
      _stalenessTimer?.cancel();
      if (_lastInstruction != null &&
          source != null &&
          _lastInstruction!.source != source) {
        final invalidated = _lastInstruction!.asStale(
          discardReason: 'Cambio de fuente externa a ${source.displayName}',
        );
        _lastInstruction = null;
        _lastEventTimestamp = null;
        if (!_instructionController.isClosed) {
          _instructionController.add(invalidated);
        }
      }
      final pkg = source == BridgeSourceType.waze
          ? 'com.waze'
          : (source == BridgeSourceType.googleMaps
                ? 'com.google.android.apps.maps'
                : 'all');
      await _nativeChannel.setSelectedSourcePackage(pkg);
    }
  }

  /// Invalida manualmente el estado actual (por ejemplo, al cambiar a navegación interna).
  void clearActiveInstruction() {
    _stalenessTimer?.cancel();
    _lastInstruction = null;
    _lastEventTimestamp = null;
    _arbiter.reset();
  }

  /// Inicia la escucha activa del canal nativo.
  void start() {
    _subscription?.cancel();
    try {
      _subscription = _nativeChannel.notificationStream.listen(
        _handleEvent,
        onError: (error) {
          // En caso de error del canal, no bloquear la aplicación
        },
      );
    } catch (_) {
      // Tolerar ausencia de ServicesBinding en pruebas puras de dominio
    }
  }

  /// Detiene la escucha y libera recursos.
  void stop() {
    _stalenessTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;
  }

  void dispose() {
    stop();
    _instructionController.close();
  }

  /// Procesa un evento directamente (útil para pruebas deterministas y canal nativo).
  void processNotificationEvent(BridgeNotificationEvent event) =>
      _handleEvent(event);

  void _handleEvent(BridgeNotificationEvent event) {
    final eventId = event.correlationId;
    final srcLabel = event.source.packageName.isNotEmpty
        ? event.source.packageName
        : event.source.displayName;

    NavigationDiagnosticLogger.logCorrelatedEvent(
      step: CorrelatedBridgeTraceStep.notificationReceived,
      eventId: eventId,
      source: srcLabel,
      availableContent:
          'key=${event.notificationKey ?? "n/a"}, cat=${event.notificationCategory ?? "n/a"}, removed=${event.isRemoved}, extras=${event.availableExtras}',
      result: event.isRemoved ? 'removed' : 'posted',
      timestamp: event.timestamp,
    );

    // 0. Si la captura externa está deshabilitada (navegación interna activa), rechazar.
    if (!_externalEnabled) {
      NavigationDiagnosticLogger.logCorrelatedEvent(
        step: CorrelatedBridgeTraceStep.instructionRejected,
        eventId: eventId,
        source: srcLabel,
        availableContent: 'title="${event.title ?? ""}"',
        result: 'filtered_out',
        rejectionReason:
            'Modo interno activo: ignorando notificación externa de ${event.source.displayName}',
        timestamp: event.timestamp,
      );
      NavigationDiagnosticLogger.logPipeline(
        stage: DiagnosticPipelineStage.l1AndroidEvent,
        source: event.source.displayName,
        summary:
            'DESCARTADO [FILTRO_FUENTE]: Modo interno activo, ignorando notificación externa de ${event.source.displayName}',
        timestamp: event.timestamp,
      );
      return;
    }

    // 1. Filtrar por la fuente seleccionada si se configuró una específica
    if (_allowedSource != null && event.source != _allowedSource) {
      NavigationDiagnosticLogger.logCorrelatedEvent(
        step: CorrelatedBridgeTraceStep.instructionRejected,
        eventId: eventId,
        source: srcLabel,
        availableContent: 'title="${event.title ?? ""}"',
        result: 'filtered_out',
        rejectionReason:
            'Fuente seleccionada es ${_allowedSource!.displayName}, ignorando evento de ${event.source.displayName}',
        timestamp: event.timestamp,
      );
      NavigationDiagnosticLogger.logPipeline(
        stage: DiagnosticPipelineStage.l1AndroidEvent,
        source: event.source.displayName,
        summary:
            'DESCARTADO [FILTRO_FUENTE]: Fuente seleccionada es ${_allowedSource!.displayName}, ignorando evento de ${event.source.displayName}',
        timestamp: event.timestamp,
      );
      return;
    }

    NavigationDiagnosticLogger.logPipeline(
      stage: DiagnosticPipelineStage.l1AndroidEvent,
      source: event.source.displayName,
      summary: event.isRemoved
          ? 'pkg=${event.source.packageName} | key=${event.notificationKey ?? "n/a"} | Notificación de navegación eliminada (isRemoved=true)'
          : 'pkg=${event.source.packageName} | key=${event.notificationKey ?? "n/a"} | cat=${event.notificationCategory ?? "n/a"} | title="${event.title ?? ""}" | text="${event.text ?? ""}" | sub="${event.subText ?? ""}" | extras=${event.availableExtras} | remoteViews=${event.remoteViewsTexts}',
      timestamp: event.timestamp,
    );

    // 2. Manejo de eliminación de notificación (fin o cancelación de ruta externa)
    if (event.isRemoved) {
      _stalenessTimer?.cancel();
      if (_lastInstruction == null) {
        NavigationDiagnosticLogger.logCorrelatedEvent(
          step: CorrelatedBridgeTraceStep.instructionRejected,
          eventId: eventId,
          source: srcLabel,
          availableContent: 'isRemoved=true (sin instrucción activa previa)',
          result: 'ignored_orphan_removal',
          rejectionReason:
              'Notificación retirada sin instrucción activa previa en la sesión',
          timestamp: event.timestamp,
        );
        return;
      }
      final stale = _lastInstruction!.asStale(
        discardReason: 'Notificación eliminada por el sistema o usuario',
      );
      _lastInstruction = stale;
      _lastEventTimestamp = event.timestamp;
      if (!_instructionController.isClosed) {
        _instructionController.add(stale);
      }
      return;
    }

    // 3. Rechazar estrictamente eventos fuera de orden temporal (anteriores al último evento o cancelación)
    if (_lastEventTimestamp != null &&
        event.timestamp.isBefore(_lastEventTimestamp!)) {
      NavigationDiagnosticLogger.logCorrelatedEvent(
        step: CorrelatedBridgeTraceStep.instructionRejected,
        eventId: eventId,
        source: srcLabel,
        availableContent: 'title="${event.title ?? ""}"',
        result: 'out_of_order',
        rejectionReason:
            'Evento tardío (${event.timestamp.toIso8601String()}) anterior al último evento (${_lastEventTimestamp!.toIso8601String()})',
        timestamp: event.timestamp,
      );
      NavigationDiagnosticLogger.logPipeline(
        stage: DiagnosticPipelineStage.l1AndroidEvent,
        source: event.source.displayName,
        summary:
            'DESCARTADO [ORDEN_TEMPORAL]: Evento tardío (${event.timestamp.toIso8601String()}) anterior al último evento/cancelación (${_lastEventTimestamp!.toIso8601String()})',
        timestamp: event.timestamp,
      );
      return;
    }

    if (event.isEmptyText) {
      NavigationDiagnosticLogger.logCorrelatedEvent(
        step: CorrelatedBridgeTraceStep.notificationTextEmpty,
        eventId: eventId,
        source: srcLabel,
        availableContent:
            'key=${event.notificationKey ?? "n/a"}, cat=${event.notificationCategory ?? "n/a"}, extras=${event.availableExtras}, remoteViews=${event.remoteViewsTexts}',
        result: 'empty_text',
        rejectionReason:
            'Notificación recibida sin campos de texto extraíbles en extras ni RemoteViews',
        timestamp: event.timestamp,
      );
    } else {
      NavigationDiagnosticLogger.logCorrelatedEvent(
        step: CorrelatedBridgeTraceStep.notificationExtracted,
        eventId: eventId,
        source: srcLabel,
        availableContent:
            'title="${event.title ?? ""}", text="${event.text ?? ""}", sub="${event.subText ?? ""}", extras=${event.availableExtras}, remoteViews=${event.remoteViewsTexts}',
        result: 'extracted',
        timestamp: event.timestamp,
      );
    }

    // 4. Parsear usando el perfil específico de Waze o Google Maps
    final instruction = switch (event.source) {
      BridgeSourceType.waze => _parser.parseWaze(
        rawTitle: event.title,
        rawText: event.text,
        rawSubText: event.subText,
        receivedAt: event.timestamp,
        availableExtras: event.availableExtras,
        remoteViewsTexts: event.remoteViewsTexts,
        notificationKey: event.notificationKey,
        notificationCategory: event.notificationCategory,
      ),
      BridgeSourceType.googleMaps => _parser.parseGoogleMaps(
        rawTitle: event.title,
        rawText: event.text,
        rawSubText: event.subText,
        receivedAt: event.timestamp,
        availableExtras: event.availableExtras,
        remoteViewsTexts: event.remoteViewsTexts,
        notificationKey: event.notificationKey,
        notificationCategory: event.notificationCategory,
      ),
      _ => _parser.parse(
        rawTitle: event.title,
        rawText: event.text,
        rawSubText: event.subText,
        source: event.source,
        receivedAt: event.timestamp,
        availableExtras: event.availableExtras,
        remoteViewsTexts: event.remoteViewsTexts,
        notificationKey: event.notificationKey,
        notificationCategory: event.notificationCategory,
      ),
    };

    NavigationDiagnosticLogger.logCorrelatedEvent(
      step: CorrelatedBridgeTraceStep.instructionParsed,
      eventId: eventId,
      source: srcLabel,
      availableContent: 'raw="${instruction.rawText}"',
      result:
          'status=${instruction.status.name}, maneuver=${instruction.maneuverType.name}, dist=${instruction.distanceMeters ?? "null"}',
      rejectionReason: instruction.discardReason,
      timestamp: instruction.receivedAt,
    );

    // 2. Manejo en modo AUTO: delegar concurrencia y arbitraje determinista a AutoNavigationSourceArbiter
    if (_allowedSource == null) {
      final arbiterResult = _arbiter.processInstruction(
        instruction,
        correlationId: eventId,
        notificationKey: event.notificationKey,
        isRemoved: event.isRemoved,
      );

      if (arbiterResult.action == AutoArbitrationAction.duplicate) {
        return;
      }

      if (arbiterResult.shouldTransmitToBle) {
        _lastInstruction = arbiterResult.instruction;
        _lastEventTimestamp = event.timestamp;
        _scheduleStalenessExpiration(arbiterResult.instruction!);
        if (!_instructionController.isClosed) {
          _instructionController.add(arbiterResult.instruction!);
        }
        return;
      }

      if (arbiterResult.shouldStopBleNavigation) {
        _stalenessTimer?.cancel();
        _lastInstruction = arbiterResult.instruction;
        _lastEventTimestamp = event.timestamp;
        if (!_instructionController.isClosed &&
            arbiterResult.instruction != null) {
          _instructionController.add(arbiterResult.instruction!);
        }
        return;
      }

      return;
    }

    // 4.1 Si es una notificación de "En ejecución. Toca para abrir." o vacía y ya existe una maniobra válida activa,
    // registrar el descarte sin sobrescribir la maniobra activa.
    if ((instruction.isAppRunningNotification ||
            instruction.isEmptyNotification) &&
        _lastInstruction != null &&
        _lastInstruction!.isCompatibleWithTripper &&
        !_lastInstruction!.isStale) {
      NavigationDiagnosticLogger.logCorrelatedEvent(
        step: CorrelatedBridgeTraceStep.instructionRejected,
        eventId: eventId,
        source: srcLabel,
        availableContent: 'raw="${instruction.rawText}"',
        result: 'ignored_preserves_active_maneuver',
        rejectionReason:
            'Notificación secundaria/banner ignorada para preservar maniobra activa vigente (${_lastInstruction!.maneuverType.name})',
        timestamp: instruction.receivedAt,
      );
      NavigationDiagnosticLogger.logPipeline(
        stage: DiagnosticPipelineStage.l2ParsedEvent,
        source: instruction.source.displayName,
        summary:
            'DESCARTADO [APP_RUNNING_BANNER]: "${instruction.rawText}" ignorado para preservar maniobra activa vigente (${_lastInstruction!.maneuverType.name})',
        timestamp: instruction.receivedAt,
      );
      return;
    }

    if (instruction.isCompatibleWithTripper) {
      NavigationDiagnosticLogger.logCorrelatedEvent(
        step: CorrelatedBridgeTraceStep.instructionAccepted,
        eventId: eventId,
        source: srcLabel,
        availableContent: 'raw="${instruction.rawText}"',
        result:
            'maneuver=${instruction.maneuverType.name}, dist=${instruction.distanceMeters}m',
        timestamp: instruction.receivedAt,
      );
    } else {
      NavigationDiagnosticLogger.logCorrelatedEvent(
        step: CorrelatedBridgeTraceStep.instructionRejected,
        eventId: eventId,
        source: srcLabel,
        availableContent: 'raw="${instruction.rawText}"',
        result: instruction.status.name,
        rejectionReason:
            instruction.discardReason ?? 'Sin maniobra giro a giro válida',
        timestamp: instruction.receivedAt,
      );
    }

    // 5. Ignorar duplicados exactos consecutivos
    if (_lastInstruction != null &&
        !_lastInstruction!.isStale &&
        _lastInstruction!.source == instruction.source &&
        _lastInstruction!.rawText == instruction.rawText &&
        _lastInstruction!.maneuverType == instruction.maneuverType &&
        _lastInstruction!.distanceMeters == instruction.distanceMeters) {
      return;
    }

    _lastInstruction = instruction;
    _lastEventTimestamp = event.timestamp;

    NavigationDiagnosticLogger.logPipeline(
      stage: DiagnosticPipelineStage.l2ParsedEvent,
      source: instruction.source.displayName,
      summary: instruction.isAppRunningNotification
          ? 'CLASIFICADO [APP_ACTIVA_SIN_MANIOBRA]: "${instruction.rawText}"'
          : (instruction.isCompatibleWithTripper
                ? 'CLASIFICADO [MANIOBRA_VALIDA]: maneuver=${instruction.maneuverType.name} | dist=${instruction.distanceMeters}m | via="${instruction.destinationStreet ?? ""}"'
                : 'DESCARTADO [SIN_MANIOBRA_VALIDA]: status=${instruction.status.name} | razón=${instruction.discardReason ?? "incompleta"} | raw="${instruction.rawText}"'),
      timestamp: instruction.receivedAt,
    );

    _scheduleStalenessExpiration(instruction);
    if (!_instructionController.isClosed) {
      _instructionController.add(instruction);
    }
  }

  void _scheduleStalenessExpiration(BridgeNavigationInstruction instruction) {
    _stalenessTimer?.cancel();
    final timeout = staleDuration ?? const Duration(seconds: 45);
    _stalenessTimer = Timer(timeout, () {
      if (_allowedSource == null) {
        final timeoutRes = _arbiter.checkTimeouts();
        if (timeoutRes != null) {
          if (timeoutRes.action == AutoArbitrationAction.fallbackActivated) {
            _lastInstruction = timeoutRes.instruction;
            _scheduleStalenessExpiration(timeoutRes.instruction!);
            if (!_instructionController.isClosed &&
                timeoutRes.instruction != null) {
              _instructionController.add(timeoutRes.instruction!);
            }
          } else if (timeoutRes.shouldStopBleNavigation) {
            _lastInstruction = timeoutRes.instruction;
            if (!_instructionController.isClosed &&
                timeoutRes.instruction != null) {
              _instructionController.add(timeoutRes.instruction!);
            }
          }
        }
        return;
      }

      if (_lastInstruction == instruction && !_lastInstruction!.isStale) {
        final stale = instruction.asStale(
          discardReason:
              'Instrucción expirada por inactividad (${timeout.inSeconds}s sin actualizar)',
        );
        _lastInstruction = stale;
        NavigationDiagnosticLogger.logPipeline(
          stage: DiagnosticPipelineStage.l2ParsedEvent,
          source: instruction.source.displayName,
          summary:
              'EXPIRADO [STALE_TIMEOUT]: Instrucción marcada como obsoleta tras ${timeout.inSeconds}s sin actualización',
        );
        if (!_instructionController.isClosed) {
          _instructionController.add(stale);
        }
      }
    });
  }
}
