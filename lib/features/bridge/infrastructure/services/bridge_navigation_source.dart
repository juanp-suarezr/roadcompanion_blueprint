import 'dart:async';
import '../../domain/entities/bridge_navigation_instruction.dart';
import '../../domain/services/navigation_instruction_parser.dart';
import 'bridge_native_channel.dart';

/// Fuente reactiva de instrucciones de navegación para ESTELA Bridge.
///
/// Recibe eventos de notificaciones capturados por [BridgeNativeChannel],
/// los procesa mediante [NavigationInstructionParser] y emite modelos
/// tipados [BridgeNavigationInstruction].
class BridgeNavigationSource {
  final BridgeNativeChannel _nativeChannel;
  final NavigationInstructionParser _parser;
  StreamSubscription<BridgeNotificationEvent>? _subscription;
  final StreamController<BridgeNavigationInstruction> _instructionController =
      StreamController<BridgeNavigationInstruction>.broadcast();

  BridgeNavigationInstruction? _lastInstruction;

  BridgeNavigationSource({
    BridgeNativeChannel? nativeChannel,
    NavigationInstructionParser? parser,
  }) : _nativeChannel = nativeChannel ?? BridgeNativeChannel(),
       _parser = parser ?? const NavigationInstructionParser();

  /// Flujo continuo de instrucciones parseadas y normalizadas.
  Stream<BridgeNavigationInstruction> get instructions =>
      _instructionController.stream;

  /// Última instrucción procesada y retenida en memoria.
  BridgeNavigationInstruction? get lastInstruction => _lastInstruction;

  /// Inicia la escucha activa del canal nativo.
  void start() {
    _subscription?.cancel();
    _subscription = _nativeChannel.notificationStream.listen(
      _handleEvent,
      onError: (error) {
        // En caso de error del canal, no bloquear la aplicación
      },
    );
  }

  /// Detiene la escucha y libera recursos.
  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  void dispose() {
    stop();
    _instructionController.close();
  }

  void _handleEvent(BridgeNotificationEvent event) {
    if (event.isRemoved) {
      if (_lastInstruction != null) {
        final stale = _lastInstruction!.asStale();
        _lastInstruction = stale;
        _instructionController.add(stale);
      }
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
    _instructionController.add(instruction);
  }
}
