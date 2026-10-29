import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../domain/entities/maneuver_type.dart';
import '../../../navigation/domain/entities/road_curvature.dart';
import '../../../navigation/domain/services/navigation_diagnostic_logger.dart';
import '../../../navigation/domain/services/navigation_source.dart';
import '../../../navigation/domain/services/tripper_ble_service.dart';
import '../../../navigation/domain/services/tripper_navigation_adapter.dart';
import '../../domain/entities/bridge_instruction_status.dart';
import '../../domain/entities/bridge_navigation_instruction.dart';
import '../../domain/entities/bridge_source_type.dart';
import '../../domain/services/navigation_instruction_parser.dart';
import '../../infrastructure/services/bridge_native_channel.dart';

/// Controlador reactivo del Modo Compañero y estado de diagnóstico para ESTELA Bridge.
///
/// Mantiene en memoria volátil (exclusiva de la sesión activa) los últimos eventos
/// capturados, filtra por la fuente seleccionada (`Waze` o `Google Maps`), gestiona
/// la máquina de estados explícita [CompanionNavigationStateMachine], adapta y transmite
/// las maniobras válidas hacia [TripperBleService] y administra el estado del
/// permiso de escucha del sistema Android.
class BridgeDiagnosticController extends ChangeNotifier {
  final BridgeNativeChannel _nativeChannel;
  final NavigationInstructionParser _parser;
  final TripperNavigationAdapter _adapter;
  final TripperBleService? _bleService;
  final CompanionNavigationStateMachine _stateMachine;

  BridgePermissionStatus _permissionStatus = BridgePermissionStatus.unknown;
  bool _isListening = false;
  bool _strictSourceFilter;
  BridgeNotificationEvent? _lastRawEvent;
  BridgeNavigationInstruction? _lastInstruction;
  DateTime? _lastEventTimestamp;
  final List<BridgeNavigationInstruction> _sessionHistory = [];
  String? _errorMessage;
  bool _lastTransmittedToTripper = false;

  StreamSubscription<BridgeNotificationEvent>? _subscription;

  BridgeDiagnosticController({
    BridgeNativeChannel? nativeChannel,
    NavigationInstructionParser? parser,
    TripperNavigationAdapter? adapter,
    TripperBleService? bleService,
    SelectedNavigationSourceType initialSource =
        SelectedNavigationSourceType.waze,
    bool strictSourceFilter = false,
  }) : _nativeChannel = nativeChannel ?? BridgeNativeChannel(),
       _parser = parser ?? const NavigationInstructionParser(),
       _adapter = adapter ?? const TripperNavigationAdapter(),
       _bleService = bleService,
       _strictSourceFilter = strictSourceFilter,
       _stateMachine = CompanionNavigationStateMachine(
         bleService: bleService,
         initialSource: switch (initialSource) {
           SelectedNavigationSourceType.waze => const WazeNavigationSource(),
           SelectedNavigationSourceType.googleMaps =>
             const GoogleMapsNavigationSource(),
           SelectedNavigationSourceType.internal =>
             const InternalNavigationSource(),
         },
       );

  BridgePermissionStatus get permissionStatus => _permissionStatus;
  bool get isListening => _isListening;
  BridgeNotificationEvent? get lastRawEvent => _lastRawEvent;
  BridgeNavigationInstruction? get lastInstruction => _lastInstruction;
  List<BridgeNavigationInstruction> get sessionHistory =>
      List.unmodifiable(_sessionHistory);
  String? get errorMessage => _errorMessage;
  bool get lastTransmittedToTripper => _lastTransmittedToTripper;

  SelectedNavigationSourceType get selectedSource =>
      _stateMachine.selectedSourceType;
  CompanionNavigationState get companionState => _stateMachine.state;
  NavigationSourceCapabilities get sourceCapabilities =>
      _stateMachine.capabilities;
  RoadCurvatureInfo get curvatureInfo => _stateMachine.curvatureInfo;

  /// Cambia la fuente de navegación seleccionada para el viaje e invalida datos anteriores.
  Future<void> selectNavigationSource(
    SelectedNavigationSourceType source, {
    bool strictFilter = true,
  }) async {
    _strictSourceFilter = strictFilter;
    if (_stateMachine.selectedSourceType == source) return;
    await _stateMachine.selectSource(
      source,
      notificationPermissionGranted:
          _permissionStatus == BridgePermissionStatus.granted,
    );
    _lastRawEvent = null;
    _lastInstruction = null;
    _lastEventTimestamp = null;
    await _nativeChannel.setSelectedSourcePackage(source.androidPackageName);
    notifyListeners();
  }

  /// Inicializa la verificación de permisos y conecta la escucha pasiva.
  Future<void> initialize() async {
    await _nativeChannel.setSelectedSourcePackage(
      _stateMachine.selectedSourceType.androidPackageName,
    );
    await checkPermission();
    startListening();
  }

  /// Consulta el estado de activación del servicio de notificaciones en Android.
  Future<void> checkPermission() async {
    try {
      _permissionStatus = await _nativeChannel.checkNotificationPermission();
      _stateMachine.updateNotificationPermission(
        _permissionStatus == BridgePermissionStatus.granted,
      );
      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Error al consultar permiso: $e';
    }
    notifyListeners();
  }

  /// Se invoca cuando la aplicación vuelve al primer plano (`AppLifecycleState.resumed`)
  /// tras visitar los ajustes del sistema Android.
  Future<void> onAppResumed() async {
    await checkPermission();
    if (_permissionStatus == BridgePermissionStatus.granted && !_isListening) {
      startListening();
    }
  }

  /// Solicita al sistema operativo abrir los ajustes de acceso a notificaciones.
  Future<void> openSettings() async {
    await _nativeChannel.openNotificationAccessSettings();
    // Reintentar verificación tras una breve espera para cuando el usuario vuelva
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

  /// Limpia la sesión de diagnóstico en memoria.
  Future<void> clearSession() async {
    _lastRawEvent = null;
    _lastInstruction = null;
    _lastEventTimestamp = null;
    _sessionHistory.clear();
    _errorMessage = null;
    await _stateMachine.stopNavigation();
    await _nativeChannel.clearNativeCache();
    notifyListeners();
  }

  void _handleEvent(BridgeNotificationEvent event) {
    if (_strictSourceFilter) {
      if (selectedSource == SelectedNavigationSourceType.internal) {
        return;
      }
      final targetBridgeSource = selectedSource.bridgeSourceType;
      if (targetBridgeSource != null && event.source != targetBridgeSource) {
        return;
      }
    }

    if (!_strictSourceFilter) {
      if (event.source == BridgeSourceType.waze &&
          selectedSource != SelectedNavigationSourceType.waze) {
        _stateMachine.selectSource(
          SelectedNavigationSourceType.waze,
          notificationPermissionGranted:
              _permissionStatus == BridgePermissionStatus.granted,
        );
      } else if (event.source == BridgeSourceType.googleMaps &&
          selectedSource != SelectedNavigationSourceType.googleMaps) {
        _stateMachine.selectSource(
          SelectedNavigationSourceType.googleMaps,
          notificationPermissionGranted:
              _permissionStatus == BridgePermissionStatus.granted,
        );
      }
    }

    NavigationDiagnosticLogger.logPipeline(
      stage: DiagnosticPipelineStage.l1AndroidEvent,
      source: event.source.displayName,
      summary: event.isRemoved
          ? 'pkg=${event.source.packageName} | Notificación eliminada (isRemoved=true)'
          : 'pkg=${event.source.packageName} | title="${event.title ?? ""}" | text="${event.text ?? ""}" | extras=${event.availableExtras} | remoteViews=${event.remoteViewsTexts}',
      timestamp: event.timestamp,
    );

    _lastRawEvent = event;

    if (event.isRemoved) {
      final stale = _lastInstruction != null
          ? _lastInstruction!.asStale()
          : BridgeNavigationInstruction(
              source: event.source,
              maneuverType: ManeuverType.unknown,
              rawText: '',
              receivedAt: event.timestamp,
              status: BridgeInstructionStatus.stale,
              discardReason: 'Notificación retirada o ruta cancelada',
            );
      _lastInstruction = stale;
      _lastEventTimestamp = event.timestamp;
      _lastTransmittedToTripper = false;
      _stateMachine.onExternalInstruction(stale);
      _bleService?.clearActiveNavPacket(
        reason: 'Notificación de ${event.source.displayName} eliminada',
      );
      if (_bleService != null &&
          _bleService.currentState.isReadyForNavigation) {
        _bleService.stopNavigation();
      }
      _addToHistory(stale);
      notifyListeners();
      return;
    }

    // Rechazar estrictamente eventos fuera de orden temporal (anteriores al último evento o cancelación)
    if (_lastEventTimestamp != null &&
        event.timestamp.isBefore(_lastEventTimestamp!)) {
      NavigationDiagnosticLogger.logPipeline(
        stage: DiagnosticPipelineStage.l1AndroidEvent,
        source: event.source.displayName,
        summary:
            'DESCARTADO [ORDEN_TEMPORAL]: Evento tardío (${event.timestamp.toIso8601String()}) anterior al último válido/cancelación',
        timestamp: event.timestamp,
      );
      return;
    }

    final instruction = switch (event.source) {
      BridgeSourceType.waze => _parser.parseWaze(
        rawTitle: event.title,
        rawText: event.text,
        rawSubText: event.subText,
        receivedAt: event.timestamp,
        availableExtras: event.availableExtras,
        remoteViewsTexts: event.remoteViewsTexts,
      ),
      BridgeSourceType.googleMaps => _parser.parseGoogleMaps(
        rawTitle: event.title,
        rawText: event.text,
        rawSubText: event.subText,
        receivedAt: event.timestamp,
        availableExtras: event.availableExtras,
        remoteViewsTexts: event.remoteViewsTexts,
      ),
      _ => _parser.parse(
        rawTitle: event.title,
        rawText: event.text,
        rawSubText: event.subText,
        source: event.source,
        receivedAt: event.timestamp,
        availableExtras: event.availableExtras,
        remoteViewsTexts: event.remoteViewsTexts,
      ),
    };

    // Si es un banner de "En ejecución. Toca para abrir." y ya teníamos una maniobra válida activa,
    // registrar en historial y logs pero NO sobrescribir la maniobra activa ni alterar el Tripper.
    if (instruction.isAppRunningNotification &&
        _lastInstruction != null &&
        _lastInstruction!.isCompatibleWithTripper &&
        !_lastInstruction!.isStale) {
      NavigationDiagnosticLogger.logPipeline(
        stage: DiagnosticPipelineStage.l2ParsedEvent,
        source: instruction.source.displayName,
        summary:
            'DESCARTADO [APP_RUNNING_BANNER]: "${instruction.rawText}" ignorado para preservar maniobra activa',
        timestamp: instruction.receivedAt,
      );
      _addToHistory(instruction);
      notifyListeners();
      return;
    }

    _lastInstruction = instruction;
    _lastEventTimestamp = event.timestamp;
    _stateMachine.onExternalInstruction(instruction);
    _addToHistory(instruction);

    final adaptation = _adapter.adaptBridgeInstruction(instruction);
    NavigationDiagnosticLogger.logPipeline(
      stage: DiagnosticPipelineStage.l3InternalModel,
      source: instruction.source.displayName,
      summary: instruction.discardReason ?? adaptation.description,
      timestamp: instruction.receivedAt,
    );

    if (adaptation.isSupported &&
        adaptation.packet != null &&
        _bleService != null &&
        _bleService.currentState.isReadyForNavigation) {
      _bleService.sendRawPacket(adaptation.packet!).then((ok) {
        _lastTransmittedToTripper = ok;
        NavigationDiagnosticLogger.logPipeline(
          stage: DiagnosticPipelineStage.l4BleTx,
          source: instruction.source.displayName,
          summary: 'txSuccess=$ok | hex=${adaptation.hexString ?? "n/a"}',
        );
        notifyListeners();
      });
    } else {
      _lastTransmittedToTripper = false;
    }

    notifyListeners();
  }

  void _addToHistory(BridgeNavigationInstruction instruction) {
    _sessionHistory.insert(0, instruction);
    if (_sessionHistory.length > 20) {
      _sessionHistory.removeLast();
    }
  }

  @override
  void dispose() {
    stopListening();
    super.dispose();
  }
}
