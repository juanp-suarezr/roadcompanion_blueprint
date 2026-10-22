import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../domain/entities/bridge_navigation_instruction.dart';
import '../../domain/services/navigation_instruction_parser.dart';
import '../../infrastructure/services/bridge_native_channel.dart';

/// Controlador reactivo del estado de diagnóstico para ESTELA Bridge.
///
/// Mantiene en memoria volátil (exclusiva de la sesión activa de diagnóstico)
/// los últimos eventos capturados y el estado del permiso de escucha del sistema.
class BridgeDiagnosticController extends ChangeNotifier {
  final BridgeNativeChannel _nativeChannel;
  final NavigationInstructionParser _parser;

  BridgePermissionStatus _permissionStatus = BridgePermissionStatus.unknown;
  bool _isListening = false;
  BridgeNotificationEvent? _lastRawEvent;
  BridgeNavigationInstruction? _lastInstruction;
  final List<BridgeNavigationInstruction> _sessionHistory = [];
  String? _errorMessage;

  StreamSubscription<BridgeNotificationEvent>? _subscription;

  BridgeDiagnosticController({
    BridgeNativeChannel? nativeChannel,
    NavigationInstructionParser? parser,
  }) : _nativeChannel = nativeChannel ?? BridgeNativeChannel(),
       _parser = parser ?? const NavigationInstructionParser();

  BridgePermissionStatus get permissionStatus => _permissionStatus;
  bool get isListening => _isListening;
  BridgeNotificationEvent? get lastRawEvent => _lastRawEvent;
  BridgeNavigationInstruction? get lastInstruction => _lastInstruction;
  List<BridgeNavigationInstruction> get sessionHistory =>
      List.unmodifiable(_sessionHistory);
  String? get errorMessage => _errorMessage;

  /// Inicializa la verificación de permisos y conecta la escucha pasiva.
  Future<void> initialize() async {
    await checkPermission();
    startListening();
  }

  /// Consulta el estado de activación del servicio de notificaciones en Android.
  Future<void> checkPermission() async {
    try {
      _permissionStatus = await _nativeChannel.checkNotificationPermission();
      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Error al consultar permiso: $e';
    }
    notifyListeners();
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

    _subscription = _nativeChannel.notificationStream.listen(
      _handleEvent,
      onError: (err) {
        _errorMessage = 'Error en canal nativo: $err';
        notifyListeners();
      },
    );
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
    _sessionHistory.clear();
    _errorMessage = null;
    await _nativeChannel.clearNativeCache();
    notifyListeners();
  }

  void _handleEvent(BridgeNotificationEvent event) {
    _lastRawEvent = event;

    if (event.isRemoved) {
      if (_lastInstruction != null) {
        final stale = _lastInstruction!.asStale();
        _lastInstruction = stale;
        _addToHistory(stale);
      }
      notifyListeners();
      return;
    }

    final instruction = _parser.parse(
      rawTitle: event.title,
      rawText: event.text,
      rawSubText: event.subText,
      source: event.source,
      receivedAt: event.timestamp,
    );

    _lastInstruction = instruction;
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
