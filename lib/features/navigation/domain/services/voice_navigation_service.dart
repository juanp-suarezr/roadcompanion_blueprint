import '../../../../domain/entities/maneuver.dart';

/// Estados de disponibilidad del servicio de navegación por voz.
enum VoiceServiceStatus {
  /// Motor TTS aún no inicializado.
  uninitialized,

  /// Inicializando motor, comprobando idiomas y configurando canal de audio.
  initializing,

  /// Motor listo para emitir anuncios en español.
  ready,

  /// Motor listo pero silenciado voluntariamente por el usuario.
  muted,

  /// Error de inicialización, falta de motor de voz o idioma español no soportado.
  error,
}

/// Contrato abstracto para el servicio de instrucciones de navegación por voz (TTS).
abstract class VoiceNavigationService {
  /// Indica si los anuncios por voz están silenciados por el usuario.
  bool get isMuted;

  /// Cambia el estado de silencio.
  set isMuted(bool value);

  /// Alterna el estado de silencio.
  void toggleMute();

  /// Indica si el motor de voz está disponible y listo en español.
  bool get isAvailable;

  /// Estado actual del servicio de voz.
  VoiceServiceStatus get status;

  /// Mensaje descriptivo del estado o causa del error.
  String? get statusMessage;

  /// Última instrucción de voz enviada al motor TTS.
  String? get lastSpokenText;

  /// Stream de cambios en el estado del servicio de voz.
  Stream<VoiceServiceStatus> get statusStream;

  /// Inicializa el motor TTS y configura el idioma español.
  Future<void> init();

  /// Emite una frase de prueba para validar el motor y los intercomunicadores.
  Future<bool> testVoice({String? sampleText});

  /// Emite un mensaje de voz personalizado.
  Future<void> speak(String text, {bool interrupt = false});

  /// Detiene inmediatamente cualquier locución en curso.
  Future<void> stop();

  /// Evalúa la maniobra y distancia actual y emite el anuncio adecuado evitando duplicados.
  Future<void> processManeuverGuidance({
    required int maneuverIndex,
    required Maneuver maneuver,
    required double distanceToManeuverMeters,
    required double currentSpeedKmh,
  });

  /// Anuncia salida de la ruta.
  Future<void> announceOffRoute();

  /// Anuncia llegada al destino.
  Future<void> announceDestinationReached();

  /// Reinicia el historial de anuncios para una nueva ruta.
  void resetGuidance();

  /// Libera los recursos del motor de voz.
  void dispose();
}
