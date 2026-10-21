import '../../../../domain/entities/maneuver.dart';

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

  /// Inicializa el motor TTS y configura el idioma español.
  Future<void> init();

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
