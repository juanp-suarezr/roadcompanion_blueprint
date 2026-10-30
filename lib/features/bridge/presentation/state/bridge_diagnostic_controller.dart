import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../navigation/domain/entities/road_curvature.dart';
import '../../../navigation/domain/services/auto_navigation_source_arbiter.dart';
import '../../../navigation/domain/services/navigation_diagnostic_logger.dart';
import '../../../navigation/domain/services/navigation_source.dart';
import '../../../navigation/domain/services/tripper_ble_service.dart';
import '../../../navigation/domain/services/tripper_navigation_adapter.dart';
import '../../domain/entities/bridge_navigation_instruction.dart';
import '../../domain/entities/bridge_source_type.dart';
import '../../domain/services/navigation_instruction_parser.dart';
import '../../infrastructure/services/bridge_native_channel.dart';

/// Categorías normalizadas para el historial de eventos en la pantalla de diagnóstico (Sección 6).
enum DiagnosticHistoryCategory {
  validInstruction('Instrucción válida'),
  ignoredNotification('Notificación ignorada'),
  emptyNotification('Notificación sin texto'),
  duplicateInstruction('Instrucción duplicada'),
  sourceSwitched('Fuente sustituida'),
  navigationEnded('Navegación finalizada'),
  sourceRecovered('Fuente recuperada');

  final String label;
  const DiagnosticHistoryCategory(this.label);
}

/// Elemento del historial de sesión con categorización visual explícita.
class DiagnosticHistoryItem {
  final BridgeNavigationInstruction instruction;
  final DiagnosticHistoryCategory category;
  final String? detail;
  final DateTime timestamp;

  const DiagnosticHistoryItem({
    required this.instruction,
    required this.category,
    this.detail,
    required this.timestamp,
  });
}

/// Controlador reactivo del Modo Compañero y estado de diagnóstico para ESTELA Bridge.
///
/// Mantiene en memoria volátil (exclusiva de la sesión activa) los últimos eventos
/// capturados, administra el árbitro de selección automática [AutoNavigationSourceArbiter],
/// gestiona la máquina de estados explícita [CompanionNavigationStateMachine],
/// adapta y transmite las maniobras válidas hacia [TripperBleService] y administra
/// el estado del permiso de escucha del sistema Android.
class BridgeDiagnosticController extends ChangeNotifier {
  final BridgeNativeChannel _nativeChannel;
  final NavigationInstructionParser _parser;
  final TripperNavigationAdapter _adapter;
  final TripperBleService? _bleService;
  final CompanionNavigationStateMachine _stateMachine;
  final AutoNavigationSourceArbiter _arbiter;

  BridgePermissionStatus _permissionStatus = BridgePermissionStatus.unknown;
  bool _isListening = false;
  bool _strictSourceFilter;
  BridgeNotificationEvent? _lastRawEvent;
  BridgeSourceType? _lastEventSource;
  BridgeNavigationInstruction? _lastInstruction;
  DateTime? _lastEventTimestamp;
  final List<BridgeNavigationInstruction> _sessionHistory = [];
  final List<DiagnosticHistoryItem> _historyItems = [];
  String? _errorMessage;
  bool _lastTransmittedToTripper = false;

  StreamSubscription<BridgeNotificationEvent>? _subscription;

  BridgeDiagnosticController({
    BridgeNativeChannel? nativeChannel,
    NavigationInstructionParser? parser,
    TripperNavigationAdapter? adapter,
    TripperBleService? bleService,
    SelectedNavigationSourceType initialSource =
        SelectedNavigationSourceType.auto,
    bool strictSourceFilter = false,
    AutoNavigationSourceArbiter? arbiter,
  }) : _nativeChannel = nativeChannel ?? BridgeNativeChannel(),
       _parser = parser ?? const NavigationInstructionParser(),
       _adapter = adapter ?? const TripperNavigationAdapter(),
       _bleService = bleService,
       _strictSourceFilter = strictSourceFilter,
       _arbiter = arbiter ?? AutoNavigationSourceArbiter(),
       _stateMachine = CompanionNavigationStateMachine(
         bleService: bleService,
         initialSource: switch (initialSource) {
           SelectedNavigationSourceType.auto => const AutoNavigationSource(),
           SelectedNavigationSourceType.waze => const WazeNavigationSource(),
           SelectedNavigationSourceType.googleMaps =>
             const GoogleMapsNavigationSource(),
           SelectedNavigationSourceType.internal =>
             const InternalNavigationSource(),
         },
       );

  BridgePermissionStatus get permissionStatus => _permissionStatus;
  bool get isListening => _isListening;
  bool get strictSourceFilter => _strictSourceFilter;
  BridgeNotificationEvent? get lastRawEvent => _lastRawEvent;
  BridgeNavigationInstruction? get lastInstruction =>
      _arbiter.currentActiveInstruction ?? _lastInstruction;
  List<BridgeNavigationInstruction> get sessionHistory =>
      List.unmodifiable(_sessionHistory);
  List<DiagnosticHistoryItem> get historyItems =>
      List.unmodifiable(_historyItems);
  DateTime? get lastEventTimestamp => _lastEventTimestamp;
  String? get errorMessage => _errorMessage;
  bool get lastTransmittedToTripper => _lastTransmittedToTripper;
  AutoNavigationSourceArbiter get arbiter => _arbiter;

  /// Fuente seleccionada para el viaje.
  SelectedNavigationSourceType get selectedSource =>
      _stateMachine.selectedSourceType;

  /// Fuente activa del viaje que gobierna la máquina de estados y el filtro hacia el Tripper.
  SelectedNavigationSourceType get activeTripSource =>
      _stateMachine.activeSource.sourceType;

  /// Nombre visible de la fuente activa real (Waze / Google Maps / Sin navegación).
  String get activeSourceDisplayName {
    if (selectedSource == SelectedNavigationSourceType.internal) {
      return 'RoadCompanion Interno';
    }
    return switch (_arbiter.activeSource) {
      BridgeSourceType.waze => 'Waze',
      BridgeSourceType.googleMaps => 'Google Maps',
      _ => 'Sin navegación',
    };
  }

  /// Última fuente externa que emitió un evento en la sesión actual.
  BridgeSourceType? get lastEventSource =>
      _lastEventSource ?? _lastRawEvent?.source ?? _lastInstruction?.source;

  /// Estado explícito de navegación del viaje.
  CompanionNavigationState get companionState {
    if (selectedSource == SelectedNavigationSourceType.internal) {
      return _stateMachine.state;
    }
    if (_arbiter.activeSource != null &&
        _arbiter.currentActiveInstruction != null &&
        !_arbiter.currentActiveInstruction!.isStale) {
      return CompanionNavigationState.navigationActive;
    }
    return _stateMachine.state;
  }

  NavigationSourceCapabilities get sourceCapabilities =>
      _stateMachine.capabilities;
  RoadCurvatureInfo get curvatureInfo => _stateMachine.curvatureInfo;

  /// Descripción legible del filtro nativo actualmente aplicado.
  String get activeFilterLabel {
    if (selectedSource == SelectedNavigationSourceType.internal) {
      return 'Interno (notificaciones externas bloqueadas)';
    }
    if (_strictSourceFilter) {
      return switch (selectedSource) {
        SelectedNavigationSourceType.waze => 'Waze (com.waze)',
        SelectedNavigationSourceType.googleMaps =>
          'Google Maps (com.google.android.apps.maps)',
        _ => 'Maps | Waze (AUTO)',
      };
    }
    return 'Maps | Waze (AUTO)';
  }

  /// Cambia la fuente de navegación seleccionada para el viaje e invalida datos anteriores.
  Future<void> selectNavigationSource(
    SelectedNavigationSourceType source, {
    bool strictFilter = false,
  }) async {
    final sourceChanged = _stateMachine.selectedSourceType != source;
    final stateNeedsReset =
        _stateMachine.state == CompanionNavigationState.navigationStopped ||
        _stateMachine.state == CompanionNavigationState.navigationStale;
    _strictSourceFilter = strictFilter;

    if (!sourceChanged && !stateNeedsReset) {
      await _nativeChannel.setSelectedSourcePackage(source.androidPackageName);
      await _nativeChannel.syncActiveNotifications();
      notifyListeners();
      return;
    }

    await _stateMachine.selectSource(
      source,
      notificationPermissionGranted:
          _permissionStatus == BridgePermissionStatus.granted,
    );
    _arbiter.reset();
    _lastRawEvent = null;
    _lastEventSource = null;
    _lastInstruction = null;
    _lastEventTimestamp = null;
    _lastTransmittedToTripper = false;
    if (sourceChanged) {
      _sessionHistory.clear();
      _historyItems.clear();
    }
    await _nativeChannel.setSelectedSourcePackage(source.androidPackageName);
    await _nativeChannel.syncActiveNotifications();
    notifyListeners();
  }

  /// Inicializa el estado del controlador consultando permisos e iniciando escucha.
  Future<void> initialize({
    SelectedNavigationSourceType? initialTripSource,
    bool? strictFilter,
  }) async {
    if (strictFilter != null) {
      _strictSourceFilter = strictFilter;
    }
    final curSource = _stateMachine.selectedSourceType;
    if (curSource.androidPackageName != null) {
      await _nativeChannel.setSelectedSourcePackage(
        curSource.androidPackageName,
      );
    }
    if (initialTripSource != null &&
        _stateMachine.selectedSourceType != initialTripSource) {
      await _stateMachine.selectSource(
        initialTripSource,
        notificationPermissionGranted:
            _permissionStatus == BridgePermissionStatus.granted,
      );
    }
    await checkPermission();
    startListening();
    await _nativeChannel.setSelectedSourcePackage(
      _stateMachine.selectedSourceType.androidPackageName,
    );
    await _nativeChannel.syncActiveNotifications();
  }

  /// Consulta el estado de activación del servicio de notificaciones en Android.
  Future<void> checkPermission() async {
    try {
      _permissionStatus = await _nativeChannel.checkNotificationPermission();
      _stateMachine.updateNotificationPermission(
        _permissionStatus == BridgePermissionStatus.granted,
      );
      _errorMessage = null;
      if (_permissionStatus == BridgePermissionStatus.granted) {
        await _nativeChannel.syncActiveNotifications();
      }
    } catch (e) {
      _errorMessage = 'Error al consultar permiso: $e';
    }
    notifyListeners();
  }

  /// Se invoca cuando la aplicación vuelve al primer plano (`AppLifecycleState.resumed`)
  Future<void> onAppResumed() async {
    await checkPermission();
    if (_permissionStatus == BridgePermissionStatus.granted && !_isListening) {
      startListening();
    }
    await _nativeChannel.syncActiveNotifications();
  }

  /// Solicita al sistema operativo abrir los ajustes de acceso a notificaciones.
  Future<void> openSettings() async {
    await _nativeChannel.openNotificationAccessSettings();
    Future.delayed(const Duration(seconds: 1), checkPermission);
  }

  /// Inicia la escucha de eventos desde el EventChannel nativo.
  void startListening() {
    _subscription?.cancel();
    _isListening = true;
    notifyListeners();

    try {
      _subscription = _nativeChannel.notificationStream.listen(
        _handleEvent,
        onError: (err) {
          _errorMessage = 'Error en canal nativo: $err';
          notifyListeners();
        },
      );
    } catch (_) {}
  }

  /// Detiene la suscripción de eventos.
  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
    _isListening = false;
    notifyListeners();
  }

  /// Limpia la sesión de diagnóstico en memoria y restaura el estado.
  Future<void> clearSession() async {
    _arbiter.reset();
    _lastRawEvent = null;
    _lastEventSource = null;
    _lastInstruction = null;
    _lastEventTimestamp = null;
    _lastTransmittedToTripper = false;
    _sessionHistory.clear();
    _historyItems.clear();
    _errorMessage = null;
    await _stateMachine.stopNavigation();
    await _stateMachine.selectSource(
      _stateMachine.selectedSourceType,
      notificationPermissionGranted:
          _permissionStatus == BridgePermissionStatus.granted,
    );
    await _nativeChannel.clearNativeCache();
    notifyListeners();
  }

  void _handleEvent(BridgeNotificationEvent event) {
    final eventId = event.correlationId;
    final srcLabel = event.source.packageName.isNotEmpty
        ? event.source.packageName
        : event.source.displayName;
    _lastEventSource = event.source;
    _lastRawEvent = event;

    NavigationDiagnosticLogger.logCorrelatedEvent(
      step: CorrelatedBridgeTraceStep.notificationReceived,
      eventId: eventId,
      source: srcLabel,
      availableContent:
          'key=${event.notificationKey ?? "n/a"}, cat=${event.notificationCategory ?? "n/a"}, removed=${event.isRemoved}, extras=${event.availableExtras}',
      result: event.isRemoved ? 'removed' : 'posted',
      timestamp: event.timestamp,
    );

    // 1. Parsear usando el perfil específico de Waze o Google Maps
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

    // 2. Gestionar modo interno explícito si está activo
    if (selectedSource == SelectedNavigationSourceType.internal) {
      _arbiter.setInternalNavigationActive(true);
    } else {
      _arbiter.setInternalNavigationActive(false);
    }

    // 3. Procesar mediante el árbitro automático de fuentes
    final arbiterResult = _arbiter.processInstruction(
      instruction,
      correlationId: eventId,
      notificationKey: event.notificationKey,
      isRemoved: event.isRemoved,
    );

    // 4. Determinar la categoría para la pantalla de historial
    final category = switch (arbiterResult.action) {
      AutoArbitrationAction.activated || AutoArbitrationAction.updated =>
        DiagnosticHistoryCategory.validInstruction,
      AutoArbitrationAction.duplicate =>
        DiagnosticHistoryCategory.duplicateInstruction,
      AutoArbitrationAction.switched =>
        DiagnosticHistoryCategory.sourceSwitched,
      AutoArbitrationAction.fallbackActivated =>
        DiagnosticHistoryCategory.sourceRecovered,
      AutoArbitrationAction.sourceEnded ||
      AutoArbitrationAction.noActiveNavigation =>
        DiagnosticHistoryCategory.navigationEnded,
      AutoArbitrationAction.expired =>
        DiagnosticHistoryCategory.navigationEnded,
      AutoArbitrationAction.ignored =>
        event.isEmptyText
            ? DiagnosticHistoryCategory.emptyNotification
            : DiagnosticHistoryCategory.ignoredNotification,
    };

    _addToHistory(
      instruction,
      category: category,
      detail: arbiterResult.reason,
    );

    // 5. Manejo según el resultado de la acción
    if (arbiterResult.action == AutoArbitrationAction.duplicate) {
      _lastInstruction = instruction;
      _lastTransmittedToTripper = false;
      notifyListeners();
      return;
    }

    if (arbiterResult.shouldStopBleNavigation) {
      final stale = arbiterResult.instruction ?? instruction.asStale();
      _lastInstruction = stale;
      _lastEventTimestamp = event.timestamp;
      _lastTransmittedToTripper = false;
      _stateMachine.onExternalInstruction(stale);
      _bleService?.clearActiveNavPacket(reason: arbiterResult.reason);
      if (_bleService != null &&
          _bleService.currentState.isReadyForNavigation) {
        _bleService.stopNavigation();
      }
      notifyListeners();
      return;
    }

    if (arbiterResult.shouldTransmitToBle) {
      _lastInstruction = arbiterResult.instruction;
      _lastEventTimestamp = event.timestamp;
      _stateMachine.onExternalInstruction(arbiterResult.instruction!);

      final adaptation = _adapter.adaptBridgeInstruction(
        arbiterResult.instruction!,
      );
      NavigationDiagnosticLogger.logPipeline(
        stage: DiagnosticPipelineStage.l3InternalModel,
        source: arbiterResult.instruction!.source.displayName,
        summary:
            arbiterResult.instruction!.discardReason ?? adaptation.description,
        timestamp: arbiterResult.instruction!.receivedAt,
      );

      if (adaptation.isSupported && adaptation.packet != null) {
        NavigationDiagnosticLogger.logCorrelatedEvent(
          step: CorrelatedBridgeTraceStep.instructionMapped,
          eventId: eventId,
          source: srcLabel,
          availableContent: adaptation.description,
          result: 'hex=${adaptation.hexString ?? "n/a"}',
          timestamp: arbiterResult.instruction!.receivedAt,
        );
        if (_bleService != null &&
            _bleService.currentState.isReadyForNavigation) {
          NavigationDiagnosticLogger.logCorrelatedEvent(
            step: CorrelatedBridgeTraceStep.bleWriteStarted,
            eventId: eventId,
            source: srcLabel,
            availableContent: 'hex=${adaptation.hexString ?? "n/a"}',
            result: 'writing_20_bytes',
          );
          _bleService.sendRawPacket(adaptation.packet!).then((ok) {
            _lastTransmittedToTripper = ok;
            if (ok) {
              NavigationDiagnosticLogger.logCorrelatedEvent(
                step: CorrelatedBridgeTraceStep.bleWriteCompleted,
                eventId: eventId,
                source: srcLabel,
                availableContent: 'hex=${adaptation.hexString ?? "n/a"}',
                result: 'txSuccess=true',
              );
            } else {
              NavigationDiagnosticLogger.logCorrelatedEvent(
                step: CorrelatedBridgeTraceStep.bleWriteFailed,
                eventId: eventId,
                source: srcLabel,
                availableContent: 'hex=${adaptation.hexString ?? "n/a"}',
                result: 'txSuccess=false',
                rejectionReason: 'Fallo en escritura GATT nativa',
              );
            }
            NavigationDiagnosticLogger.logPipeline(
              stage: DiagnosticPipelineStage.l4BleTx,
              source: arbiterResult.instruction!.source.displayName,
              summary: 'txSuccess=$ok | hex=${adaptation.hexString ?? "n/a"}',
            );
            notifyListeners();
          });
        } else {
          _lastTransmittedToTripper = false;
          NavigationDiagnosticLogger.logCorrelatedEvent(
            step: CorrelatedBridgeTraceStep.bleWriteFailed,
            eventId: eventId,
            source: srcLabel,
            availableContent: 'hex=${adaptation.hexString ?? "n/a"}',
            result: 'ble_not_ready',
            rejectionReason:
                'Tripper Pod no conectado o no autenticado (${_bleService?.currentState.name ?? "sin servicio BLE"})',
          );
        }
      } else {
        _lastTransmittedToTripper = false;
      }
    }

    notifyListeners();
  }

  void _addToHistory(
    BridgeNavigationInstruction instruction, {
    required DiagnosticHistoryCategory category,
    String? detail,
  }) {
    _sessionHistory.insert(0, instruction);
    if (_sessionHistory.length > 25) {
      _sessionHistory.removeLast();
    }
    _historyItems.insert(
      0,
      DiagnosticHistoryItem(
        instruction: instruction,
        category: category,
        detail: detail,
        timestamp: instruction.receivedAt,
      ),
    );
    if (_historyItems.length > 25) {
      _historyItems.removeLast();
    }
  }

  @override
  void dispose() {
    stopListening();
    super.dispose();
  }
}
