import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../domain/entities/maneuver_type.dart';
import '../../../navigation/domain/entities/road_curvature.dart';
import '../../../navigation/domain/services/navigation_diagnostic_logger.dart';
import '../../../navigation/domain/services/navigation_source.dart';
import '../../domain/entities/bridge_instruction_status.dart';
import '../../domain/entities/bridge_navigation_instruction.dart';
import '../../domain/entities/bridge_source_type.dart';
import '../../domain/services/navigation_instruction_parser.dart';
import '../../infrastructure/services/bridge_native_channel.dart';

/// Controlador reactivo del Modo Compañero y estado de diagnóstico para ESTELA Bridge.
///
/// Mantiene en memoria volátil (exclusiva de la sesión activa) los últimos eventos
/// capturados, filtra por la fuente seleccionada (`Waze` o `Google Maps`), gestiona
/// la máquina de estados explícita [CompanionNavigationStateMachine] y el estado del
/// permiso de escucha del sistema Android.
class BridgeDiagnosticController extends ChangeNotifier {
  final BridgeNativeChannel _nativeChannel;
  final NavigationInstructionParser _parser;
  final CompanionNavigationStateMachine _stateMachine;

  BridgePermissionStatus _permissionStatus = BridgePermissionStatus.unknown;
  bool _isListening = false;
  bool _strictSourceFilter;
  BridgeNotificationEvent? _lastRawEvent;
  BridgeNavigationInstruction? _lastInstruction;
  DateTime? _lastEventTimestamp;
  final List<BridgeNavigationInstruction> _sessionHistory = [];
  String? _errorMessage;

  StreamSubscription<BridgeNotificationEvent>? _subscription;

  BridgeDiagnosticController({
    BridgeNativeChannel? nativeChannel,
    NavigationInstructionParser? parser,
    SelectedNavigationSourceType initialSource =
        SelectedNavigationSourceType.waze,
    bool strictSourceFilter = false,
  }) : _nativeChannel = nativeChannel ?? BridgeNativeChannel(),
       _parser = parser ?? const NavigationInstructionParser(),
       _strictSourceFilter = strictSourceFilter,
       _stateMachine = CompanionNavigationStateMachine(
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
    final targetBridgeSource = selectedSource.bridgeSourceType;
    if (_strictSourceFilter &&
        targetBridgeSource != null &&
        event.source != targetBridgeSource) {
      return;
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
          ? 'Notificación eliminada (isRemoved=true)'
          : 'title="${event.title ?? ""}" | text="${event.text ?? ""}"',
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
            );
      _lastInstruction = stale;
      _lastEventTimestamp = event.timestamp;
      _stateMachine.onExternalInstruction(stale);
      _addToHistory(stale);
      notifyListeners();
      return;
    }

    // Rechazar eventos fuera de orden temporal
    if (_lastEventTimestamp != null &&
        event.timestamp.isBefore(
          _lastEventTimestamp!.subtract(const Duration(seconds: 2)),
        )) {
      return;
    }

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

    _lastInstruction = instruction;
    _lastEventTimestamp = event.timestamp;
    _stateMachine.onExternalInstruction(instruction);
    _addToHistory(instruction);
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
