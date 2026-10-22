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
  DateTime? _speakStartedAt;
  String _activeLanguage = 'es-ES';
  VoiceServiceStatus _status = VoiceServiceStatus.uninitialized;
  String? _statusMessage;
  final _statusController = StreamController<VoiceServiceStatus>.broadcast();

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
      _setStatus(VoiceServiceStatus.muted, 'Audio silenciado por el usuario.');
    } else {
      if (_isAvailable) {
        _setStatus(VoiceServiceStatus.ready, 'Voz lista en $_activeLanguage.');
      } else {
        _setStatus(VoiceServiceStatus.uninitialized, 'Pendiente de inicialización.');
      }
    }
  }

  @override
  void toggleMute() {
    isMuted = !isMuted;
  }

  @override
  bool get isAvailable => _isAvailable;

  @override
  VoiceServiceStatus get status => _status;

  @override
  String? get statusMessage => _statusMessage;

  @override
  Stream<VoiceServiceStatus> get statusStream => _statusController.stream;

  void _setStatus(VoiceServiceStatus newStatus, String? message) {
    _status = newStatus;
    _statusMessage = message;
    if (!_statusController.isClosed) {
      _statusController.add(newStatus);
    }
    debugPrint('[TTS] Estado: ${newStatus.name} - $message');
  }

  @override
  Future<void> init() async {
    try {
      if (kIsWeb) {
        _setStatus(
          VoiceServiceStatus.error,
          'TTS no disponible en plataforma web.',
        );
        return;
      }

      _setStatus(VoiceServiceStatus.initializing, 'Inicializando motor TTS...');

      // Configurar callbacks de ciclo de vida TTS
      _tts.setStartHandler(() {
        _isSpeaking = true;
        _speakStartedAt = DateTime.now();
      });
      _tts.setCompletionHandler(() {
        _isSpeaking = false;
        _speakStartedAt = null;
      });
      _tts.setCancelHandler(() {
        _isSpeaking = false;
        _speakStartedAt = null;
      });
      _tts.setErrorHandler((msg) {
        _isSpeaking = false;
        _speakStartedAt = null;
        debugPrint('Aviso TTS de error de reproducción: $msg');
      });

      // Configurar parámetros de voz para intercomunicador de casco
      await _tts.setSpeechRate(0.50);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);

      // Comprobar disponibilidad de idioma español (es-ES, es-419, es-US, es)
      String chosenLanguage = 'es-ES';
      bool languageFound = false;

      final dynamic languages = await _tts.getLanguages;
      if (languages is List && languages.isNotEmpty) {
        final list = languages.cast<dynamic>().map((e) => e.toString()).toList();
        final candidate = list.firstWhere(
          (l) =>
              l.toLowerCase() == 'es-es' ||
              l.toLowerCase() == 'es_es' ||
              l.toLowerCase() == 'es-419' ||
              l.toLowerCase() == 'es_419' ||
              l.toLowerCase() == 'es-us' ||
              l.toLowerCase().startsWith('es'),
          orElse: () => '',
        );
        if (candidate.isNotEmpty) {
          chosenLanguage = candidate;
          languageFound = true;
        }
      }

      // Si no se encontró en la lista dinámica, verificar con isLanguageAvailable
      if (!languageFound) {
        final dynamic isEsAvailable = await _tts.isLanguageAvailable('es-ES');
        if (isEsAvailable == 1 || isEsAvailable == true) {
          chosenLanguage = 'es-ES';
          languageFound = true;
        } else {
          final dynamic isLatamAvailable =
              await _tts.isLanguageAvailable('es-419');
          if (isLatamAvailable == 1 || isLatamAvailable == true) {
            chosenLanguage = 'es-419';
            languageFound = true;
          }
        }
      }

      await _tts.setLanguage(chosenLanguage);
      _activeLanguage = chosenLanguage;
      _isAvailable = true;

      if (_isMuted) {
        _setStatus(
          VoiceServiceStatus.muted,
          'Motor listo en $_activeLanguage (Silenciado).',
        );
      } else {
        _setStatus(
          VoiceServiceStatus.ready,
          'Voz lista en $_activeLanguage para indicaciones viales.',
        );
      }
    } catch (e) {
      debugPrint('No se pudo inicializar FlutterTts: $e');
      _isAvailable = false;
      _setStatus(
        VoiceServiceStatus.error,
        'Error inicializando voz: $e. Verifica que los Servicios de Voz de Google estén activos.',
      );
    }
  }

  @override
  Future<bool> testVoice({String? sampleText}) async {
    if (!_isAvailable) {
      await init();
    }
    if (!_isAvailable) {
      return false;
    }

    final text = sampleText ?? 'REstelar: audio de navegación por voz listo.';
    await speak(text, interrupt: true);
    return true;
  }

  @override
  Future<void> speak(String text, {bool interrupt = false}) async {
    if (_isMuted || text.trim().isEmpty) return;

    if (!_isAvailable) {
      await init();
      if (!_isAvailable) return;
    }

    try {
      // Mecanismo de seguridad contra audio atascado (watchdog)
      if (_isSpeaking) {
        final elapsed = _speakStartedAt != null
            ? DateTime.now().difference(_speakStartedAt!)
            : Duration.zero;
        if (elapsed.inSeconds > 8) {
          debugPrint('[TTS] Watchdog: Reiniciando estado de audio atascado.');
          _isSpeaking = false;
        } else if (!interrupt) {
          // No encimar anuncios secundarios mientras otro se reproduce
          return;
        }
      }

      if (interrupt) {
        await stop();
      }

      _isSpeaking = true;
      _speakStartedAt = DateTime.now();
      await _tts.speak(text);
    } catch (e) {
      _isSpeaking = false;
      _speakStartedAt = null;
      debugPrint('Error al reproducir voz TTS: $e');
    }
  }

  @override
  Future<void> stop() async {
    _isSpeaking = false;
    _speakStartedAt = null;
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

    // Adaptar umbrales continuos según la velocidad del motociclista
    final double advanceThreshold = currentSpeedKmh > 60.0 ? 600.0 : 450.0;
    final double prepThreshold = currentSpeedKmh > 60.0 ? 250.0 : 180.0;
    final double imminentThreshold = currentSpeedKmh > 60.0 ? 50.0 : 30.0;

    // 1. Maniobra Inminente (<= 30m - 50m)
    if (distanceToManeuverMeters <= imminentThreshold && distanceToManeuverMeters >= 0.0) {
      final key = '${maneuverIndex}_imminent';
      if (!_announcedStages.contains(key)) {
        _announcedStages.add(key);
        final prompt = _buildImmediateInstruction(maneuver);
        await speak(prompt, interrupt: true);
      }
      return;
    }

    // 2. Maniobra de Preparación (imminentThreshold < dist <= prepThreshold) — Sin huecos
    if (distanceToManeuverMeters <= prepThreshold &&
        distanceToManeuverMeters > imminentThreshold) {
      final key = '${maneuverIndex}_prep';
      if (!_announcedStages.contains(key)) {
        _announcedStages.add(key);
        final roundedDist = (distanceToManeuverMeters / 10).round() * 10;
        final prompt = _buildDistanceInstruction(maneuver, roundedDist);
        await speak(prompt, interrupt: false);
      }
      return;
    }

    // 3. Maniobra de Anticipación (prepThreshold < dist <= advanceThreshold) — Sin huecos
    if (distanceToManeuverMeters <= advanceThreshold &&
        distanceToManeuverMeters > prepThreshold) {
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
      return; // Evitar saturar al piloto en recalculo
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
    _statusController.close();
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

