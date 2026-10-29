import 'dart:async';
import '../../../../domain/entities/maneuver_type.dart';
import '../../../navigation/domain/services/navigation_diagnostic_logger.dart';
import '../../domain/entities/bridge_instruction_status.dart';
import '../../domain/entities/bridge_navigation_instruction.dart';
import '../../domain/entities/bridge_source_type.dart';
import '../../domain/services/navigation_instruction_parser.dart';
import 'bridge_native_channel.dart';

/// Fuente reactiva de instrucciones de navegación para ESTELA Bridge.
///
/// Recibe eventos de notificaciones capturados por [BridgeNativeChannel],
/// filtra por la fuente seleccionada (`Waze` o `Google Maps`), rechaza eventos
/// fuera de orden o duplicados, los procesa mediante [NavigationInstructionParser]
/// y emite modelos tipados [BridgeNavigationInstruction].
class BridgeNavigationSource {
  final BridgeNativeChannel _nativeChannel;
  final NavigationInstructionParser _parser;
  final Duration? staleDuration;
  StreamSubscription<BridgeNotificationEvent>? _subscription;
  Timer? _stalenessTimer;
  final StreamController<BridgeNavigationInstruction> _instructionController =
      StreamController<BridgeNavigationInstruction>.broadcast();

  BridgeNavigationInstruction? _lastInstruction;
  DateTime? _lastEventTimestamp;
  BridgeSourceType? _allowedSource;

  BridgeNavigationSource({
    BridgeNativeChannel? nativeChannel,
    NavigationInstructionParser? parser,
    BridgeSourceType? allowedSource,
    this.staleDuration,
  }) : _nativeChannel = nativeChannel ?? BridgeNativeChannel(),
       _parser = parser ?? const NavigationInstructionParser(),
       _allowedSource = allowedSource;

  /// Flujo continuo de instrucciones parseadas y normalizadas.
  Stream<BridgeNavigationInstruction> get instructions =>
      _instructionController.stream;

  /// Última instrucción procesada y retenida en memoria.
  BridgeNavigationInstruction? get lastInstruction => _lastInstruction;

  /// Fuente externa permitida actualmente (`null` acepta Waze y Google Maps).
  BridgeSourceType? get allowedSource => _allowedSource;

  /// Cambia la fuente externa permitida e invalida de inmediato datos de otra fuente.
  Future<void> setAllowedSource(BridgeSourceType? source) async {
    if (_allowedSource != source) {
      _allowedSource = source;
      _stalenessTimer?.cancel();
      if (_lastInstruction != null &&
          source != null &&
          _lastInstruction!.source != source) {
        final invalidated = _lastInstruction!.asStale();
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
    // 1. Filtrar por la fuente seleccionada si se configuró una específica
    if (_allowedSource != null && event.source != _allowedSource) {
      return;
    }

    NavigationDiagnosticLogger.logPipeline(
      stage: DiagnosticPipelineStage.l1AndroidEvent,
      source: event.source.displayName,
      summary: event.isRemoved
          ? 'Notificación de navegación eliminada (isRemoved=true)'
          : 'title="${event.title ?? ""}" | text="${event.text ?? ""}"',
      timestamp: event.timestamp,
    );

    // 2. Manejo de eliminación de notificación (fin o cancelación de ruta externa)
    if (event.isRemoved) {
      _stalenessTimer?.cancel();
      final stale = _lastInstruction != null
          ? _lastInstruction!.asStale()
          : BridgeNavigationInstruction(
              source: event.source,
              maneuverType: ManeuverType.unknown,
              rawText: '',
              receivedAt: event.timestamp,
              status: BridgeInstructionStatus.stale,
            );
      _lastInstruction = stale;
      _lastEventTimestamp = event.timestamp;
      if (!_instructionController.isClosed) {
        _instructionController.add(stale);
      }
      return;
    }

    // 3. Rechazar eventos fuera de orden temporal (> 2s más antiguos que el último válido)
    if (_lastEventTimestamp != null &&
        event.timestamp.isBefore(
          _lastEventTimestamp!.subtract(const Duration(seconds: 2)),
        )) {
      return;
    }

    // 4. Parsear usando el perfil específico de Waze o Google Maps
    final instruction = switch (event.source) {
      BridgeSourceType.waze => _parser.parseWaze(
        rawTitle: event.title,
        rawText: event.text,
        rawSubText: event.subText,
        receivedAt: event.timestamp,
      ),
      BridgeSourceType.googleMaps => _parser.parseGoogleMaps(
        rawTitle: event.title,
        rawText: event.text,
        rawSubText: event.subText,
        receivedAt: event.timestamp,
      ),
      _ => _parser.parse(
        rawTitle: event.title,
        rawText: event.text,
        rawSubText: event.subText,
        source: event.source,
        receivedAt: event.timestamp,
      ),
    };

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
      summary:
          'status=${instruction.status.name} | maneuver=${instruction.maneuverType.name} | dist=${instruction.distanceMeters ?? -1}m',
      timestamp: instruction.receivedAt,
    );

    _scheduleStalenessExpiration(instruction);
    if (!_instructionController.isClosed) {
      _instructionController.add(instruction);
    }
  }

  void _scheduleStalenessExpiration(BridgeNavigationInstruction instruction) {
    _stalenessTimer?.cancel();
    final timeout = staleDuration;
    if (timeout == null) return;
    _stalenessTimer = Timer(timeout, () {
      if (_lastInstruction == instruction && !_lastInstruction!.isStale) {
        final stale = instruction.asStale();
        _lastInstruction = stale;
        if (!_instructionController.isClosed) {
          _instructionController.add(stale);
        }
      }
    });
  }
}
