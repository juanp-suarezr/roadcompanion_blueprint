import 'dart:async';

import '../../../../domain/entities/maneuver_type.dart';
import '../../../bridge/domain/entities/bridge_navigation_instruction.dart';
import '../../../bridge/infrastructure/services/bridge_navigation_source.dart';
import '../../domain/services/tripper_ble_service.dart';
import '../../domain/services/tripper_navigation_adapter.dart';

/// Evento de ciclo de vida del puente de navegación entre Waze/Maps y el Tripper Pod.
class NavigationBridgeEvent {
  final BridgeNavigationInstruction? instruction;
  final TripperNavAdaptationResult adaptationResult;
  final bool transmittedToTripper;
  final DateTime timestamp;
  final String? transmissionError;

  const NavigationBridgeEvent({
    required this.adaptationResult,
    required this.transmittedToTripper,
    required this.timestamp,
    this.instruction,
    this.transmissionError,
  });

  /// Resumen técnico legible para interfaces de diagnóstico.
  String toSummaryString() {
    if (transmittedToTripper) {
      return '[ENVIADO AL TRIPPER] ${adaptationResult.description}';
    }
    if (!adaptationResult.isSupported) {
      return '[NO COMPATIBLE] ${adaptationResult.description}';
    }
    return '[RETENIDO] Indicación válida pero Tripper Pod no autenticado en BLE.';
  }
}

/// Orquesta la recepción de notificaciones de Waze/Google Maps, su validación y
/// adaptación desacoplada hacia el transporte Bluetooth LE del Tripper Pod.
///
/// Arquitectura desacoplada:
/// NavigationNotificationListenerService -> BridgeNavigationSource -> NavigationInstructionBridge -> TripperNavigationAdapter -> TripperBleService
class NavigationInstructionBridge {
  final BridgeNavigationSource _navigationSource;
  final TripperNavigationAdapter _adapter;
  final TripperBleService _bleService;

  StreamSubscription<BridgeNavigationInstruction>? _sourceSubscription;
  final StreamController<NavigationBridgeEvent> _eventsController =
      StreamController<NavigationBridgeEvent>.broadcast();

  NavigationBridgeEvent? _lastEvent;
  bool _isActive = false;

  NavigationInstructionBridge({
    required BridgeNavigationSource navigationSource,
    required TripperBleService bleService,
    TripperNavigationAdapter? adapter,
  }) : _navigationSource = navigationSource,
       _bleService = bleService,
       _adapter = adapter ?? const TripperNavigationAdapter();

  /// Flujo continuo de eventos de adaptación y transmisión.
  Stream<NavigationBridgeEvent> get eventsStream => _eventsController.stream;
  Stream<NavigationBridgeEvent> get events => eventsStream;

  /// Último evento procesado por el puente.
  NavigationBridgeEvent? get lastEvent => _lastEvent;

  /// Última instrucción recibida desde la fuente.
  BridgeNavigationInstruction? get lastInstruction =>
      _navigationSource.lastInstruction;

  /// Indica si el puente está escuchando activamente notificaciones externas.
  bool get isActive => _isActive;
  bool get isListening => _isActive;

  /// Inicia la escucha reactiva del flujo de instrucciones externas.
  void start() {
    if (_isActive) return;
    _isActive = true;
    _navigationSource.start();
    _sourceSubscription?.cancel();
    _sourceSubscription = _navigationSource.instructions.listen(
      _processIncomingInstruction,
      onError: (err) {
        // Fallos del canal no bloquean el puente
      },
    );
  }

  /// Detiene la escucha y libera suscripciones activas.
  void stop() {
    _isActive = false;
    _sourceSubscription?.cancel();
    _sourceSubscription = null;
  }

  void dispose() {
    stop();
    _eventsController.close();
  }

  /// Procesa una instrucción recibida desde Waze o Google Maps.
  Future<void> _processIncomingInstruction(
    BridgeNavigationInstruction instruction,
  ) async {
    final adaptation = _adapter.adaptBridgeInstruction(instruction);

    if (!adaptation.isSupported || adaptation.packet == null) {
      final event = NavigationBridgeEvent(
        instruction: instruction,
        adaptationResult: adaptation,
        transmittedToTripper: false,
        timestamp: DateTime.now(),
      );
      _lastEvent = event;
      _eventsController.add(event);
      return;
    }

    // Verificar si el Tripper Pod está en un estado BLE apto para recibir paquetes
    final isReady = _bleService.currentState.isReadyForNavigation;
    if (!isReady) {
      final event = NavigationBridgeEvent(
        instruction: instruction,
        adaptationResult: adaptation,
        transmittedToTripper: false,
        timestamp: DateTime.now(),
      );
      _lastEvent = event;
      _eventsController.add(event);
      return;
    }

    try {
      final txSuccess = await _bleService.sendRawPacket(adaptation.packet!);
      final event = NavigationBridgeEvent(
        instruction: instruction,
        adaptationResult: adaptation,
        transmittedToTripper: txSuccess,
        timestamp: DateTime.now(),
        transmissionError: txSuccess ? null : 'Fallo en escritura GATT nativa',
      );
      _lastEvent = event;
      _eventsController.add(event);
    } catch (e) {
      final event = NavigationBridgeEvent(
        instruction: instruction,
        adaptationResult: adaptation,
        transmittedToTripper: false,
        timestamp: DateTime.now(),
        transmissionError: e.toString(),
      );
      _lastEvent = event;
      _eventsController.add(event);
    }
  }

  /// Permite transmitir una indicación de navegación generada internamente por REStelar.
  Future<bool> transmitNativeManeuver({
    required ManeuverType maneuverType,
    required int distanceMeters,
    int? roundaboutExit,
    int? totalDistanceMeters,
  }) async {
    final adaptation = _adapter.adaptNativeManeuver(
      maneuverType: maneuverType,
      distanceMeters: distanceMeters,
      roundaboutExit: roundaboutExit,
      totalDistanceMeters: totalDistanceMeters,
    );

    if (!adaptation.isSupported || adaptation.packet == null) {
      final event = NavigationBridgeEvent(
        adaptationResult: adaptation,
        transmittedToTripper: false,
        timestamp: DateTime.now(),
      );
      _lastEvent = event;
      _eventsController.add(event);
      return false;
    }

    if (!_bleService.currentState.isReadyForNavigation) {
      final event = NavigationBridgeEvent(
        adaptationResult: adaptation,
        transmittedToTripper: false,
        timestamp: DateTime.now(),
      );
      _lastEvent = event;
      _eventsController.add(event);
      return false;
    }

    try {
      final ok = await _bleService.sendRawPacket(adaptation.packet!);
      final event = NavigationBridgeEvent(
        adaptationResult: adaptation,
        transmittedToTripper: ok,
        timestamp: DateTime.now(),
      );
      _lastEvent = event;
      _eventsController.add(event);
      return ok;
    } catch (e) {
      final event = NavigationBridgeEvent(
        adaptationResult: adaptation,
        transmittedToTripper: false,
        timestamp: DateTime.now(),
        transmissionError: e.toString(),
      );
      _lastEvent = event;
      _eventsController.add(event);
      return false;
    }
  }
}
