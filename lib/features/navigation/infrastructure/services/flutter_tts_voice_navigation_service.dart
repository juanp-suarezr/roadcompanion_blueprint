import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../../../domain/entities/maneuver.dart';
import '../../../../domain/entities/maneuver_type.dart';
import '../../domain/services/voice_navigation_service.dart';

/// Implementación real de [VoiceNavigationService] utilizando `flutter_tts`
/// configurado en español y adaptado para intercomunicadores de casco en motocicleta.
class FlutterTtsVoiceNavigationService implements VoiceNavigationService {
  FlutterTts? _ttsInstance;
  FlutterTts get _tts => _ttsInstance ??= FlutterTts();
  bool _isMuted = false;
  bool _isAvailable = false;
  bool _isSpeaking = false;
  String _activeLanguage = 'es-ES';

  // Registro de etapas de anuncio emitidas: 'index_stage'
  final Set<String> _announcedStages = {};
  DateTime? _lastOffRouteAnnouncedAt;

  FlutterTtsVoiceNavigationService({FlutterTts? tts}) : _ttsInstance = tts;

  @override
  bool get isMuted => _isMuted;

  @override
  set isMuted(bool value) {
    _isMuted = value;
    if (_isMuted) {
      stop();
    }
  }

  @override
  void toggleMute() {
    isMuted = !isMuted;
  }

  @override
  bool get isAvailable => _isAvailable;

  @override
  Future<void> init() async {
    try {
      if (kIsWeb) return;

      // Configurar callbacks de ciclo de vida TTS
      _tts.setStartHandler(() {
        _isSpeaking = true;
      });
      _tts.setCompletionHandler(() {
        _isSpeaking = false;
      });
      _tts.setErrorHandler((msg) {
        _isSpeaking = false;
        debugPrint('Aviso TTS: $msg');
      });

      // Configurar parámetros de voz para casco (claridad y ritmo)
      await _tts.setSpeechRate(0.52);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);

      // Comprobar disponibilidad de idioma español
      final dynamic languages = await _tts.getLanguages;
      if (languages is List) {
        final spanish = languages.cast<dynamic>().map((e) => e.toString()).firstWhere(
              (l) => l.toLowerCase().startsWith('es'),
              orElse: () => '',
            );
        if (spanish.isNotEmpty) {
          _activeLanguage = spanish;
        }
      }

      await _tts.setLanguage(_activeLanguage);
      _isAvailable = true;
    } catch (e) {
      debugPrint('No se pudo inicializar FlutterTts: $e');
      _isAvailable = false;
    }
  }

  @override
  Future<void> speak(String text, {bool interrupt = false}) async {
    if (_isMuted || !_isAvailable || text.trim().isEmpty) return;

    try {
      if (_isSpeaking && !interrupt) {
        // Evitar superposición de anuncios secundarios
        return;
      }

      if (interrupt) {
        await _tts.stop();
      }

      await _tts.speak(text);
    } catch (e) {
      debugPrint('Error al reproducir voz TTS: $e');
    }
  }

  @override
  Future<void> stop() async {
    _isSpeaking = false;
    if (_isAvailable && _ttsInstance != null) {
      try {
        await _ttsInstance!.stop();
      } catch (_) {}
    }
  }

  @override
  Future<void> processManeuverGuidance({
    required int maneuverIndex,
    required Maneuver maneuver,
    required double distanceToManeuverMeters,
    required double currentSpeedKmh,
  }) async {
    if (_isMuted) return;

    // Adaptar umbrales a la velocidad de la motocicleta
    final double advanceThreshold = currentSpeedKmh > 60.0 ? 600.0 : 450.0;
    final double prepThreshold = currentSpeedKmh > 60.0 ? 250.0 : 180.0;
    final double imminentThreshold = currentSpeedKmh > 60.0 ? 50.0 : 30.0;

    // 1. Maniobra Inminente (30m - 50m)
    if (distanceToManeuverMeters <= imminentThreshold && distanceToManeuverMeters >= 0.0) {
      final key = '${maneuverIndex}_imminent';
      if (!_announcedStages.contains(key)) {
        _announcedStages.add(key);
        final prompt = _buildImmediateInstruction(maneuver);
        await speak(prompt, interrupt: true);
      }
      return;
    }

    // 2. Maniobra de Preparación (~180m - 250m)
    if (distanceToManeuverMeters <= prepThreshold &&
        distanceToManeuverMeters > imminentThreshold + 20.0) {
      final key = '${maneuverIndex}_prep';
      if (!_announcedStages.contains(key)) {
        _announcedStages.add(key);
        final roundedDist = (distanceToManeuverMeters / 10).round() * 10;
        final prompt = _buildDistanceInstruction(maneuver, roundedDist);
        await speak(prompt, interrupt: false);
      }
      return;
    }

    // 3. Maniobra de Anticipación (~450m - 600m)
    if (distanceToManeuverMeters <= advanceThreshold &&
        distanceToManeuverMeters > prepThreshold + 40.0) {
      final key = '${maneuverIndex}_advance';
      if (!_announcedStages.contains(key)) {
        _announcedStages.add(key);
        final roundedDist = (distanceToManeuverMeters / 50).round() * 50;
        final prompt = _buildDistanceInstruction(maneuver, roundedDist);
        await speak(prompt, interrupt: false);
      }
      return;
    }
  }

  @override
  Future<void> announceOffRoute() async {
    if (_isMuted) return;
    final now = DateTime.now();
    if (_lastOffRouteAnnouncedAt != null &&
        now.difference(_lastOffRouteAnnouncedAt!) < const Duration(seconds: 20)) {
      return; // No saturar al piloto si está recalculando
    }
    _lastOffRouteAnnouncedAt = now;
    await speak('Has salido de la ruta. Recalculando trayecto.', interrupt: true);
  }

  @override
  Future<void> announceDestinationReached() async {
    if (_isMuted) return;
    await speak('Has llegado a tu destino.', interrupt: true);
  }

  @override
  void resetGuidance() {
    _announcedStages.clear();
    _lastOffRouteAnnouncedAt = null;
    stop();
  }

  @override
  void dispose() {
    stop();
  }

  String _buildDistanceInstruction(Maneuver maneuver, int meters) {
    final action = _formatManeuverAction(maneuver.type);
    final street = maneuver.roadName?.trim();
    if (street != null && street.isNotEmpty) {
      return 'En $meters metros, $action en $street.';
    }
    return 'En $meters metros, $action.';
  }

  String _buildImmediateInstruction(Maneuver maneuver) {
    final action = _formatManeuverAction(maneuver.type, capitalize: true);
    final street = maneuver.roadName?.trim();
    if (street != null && street.isNotEmpty) {
      return '$action en $street.';
    }
    return '$action.';
  }

  String _formatManeuverAction(ManeuverType type, {bool capitalize = false}) {
    String text;
    switch (type) {
      case ManeuverType.left:
        text = 'gira a la izquierda';
        break;
      case ManeuverType.right:
        text = 'gira a la derecha';
        break;
      case ManeuverType.sharpLeft:
        text = 'gira pronunciadamente a la izquierda';
        break;
      case ManeuverType.sharpRight:
        text = 'gira pronunciadamente a la derecha';
        break;
      case ManeuverType.slightLeft:
        text = 'mantente a la izquierda';
        break;
      case ManeuverType.slightRight:
        text = 'mantente a la derecha';
        break;
      case ManeuverType.uTurn:
        text = 'haz un cambio de sentido';
        break;
      case ManeuverType.roundabout:
        text = 'en la glorieta, toma la salida';
        break;
      case ManeuverType.arrive:
        text = 'llegarás a tu destino';
        break;
      case ManeuverType.depart:
        text = 'inicia el recorrido';
        break;
      case ManeuverType.straight:
      default:
        text = 'continúa por la vía';
        break;
    }

    if (capitalize && text.isNotEmpty) {
      return text[0].toUpperCase() + text.substring(1);
    }
    return text;
  }
}
