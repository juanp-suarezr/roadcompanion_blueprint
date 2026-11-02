import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Datos estructurados de la compilación de la aplicación.
class AppBuildInfo {
  final DateTime? buildTime;
  final String buildMode;

  const AppBuildInfo({this.buildTime, required this.buildMode});

  /// Formatea la fecha y hora de compilación según la especificación:
  /// `Última actualización: 01 nov 2026 · 20:33 · RELEASE`
  String formatDisplay() {
    final mode = buildMode.toUpperCase();
    if (buildTime == null) {
      return 'Modo $mode';
    }

    final local = buildTime!.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final months = [
      'ene',
      'feb',
      'mar',
      'abr',
      'may',
      'jun',
      'jul',
      'ago',
      'sep',
      'oct',
      'nov',
      'dic',
    ];
    final month = months[local.month - 1];
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');

    return 'Última actualización: $day $month $year · $hour:$minute · $mode';
  }
}

/// Servicio para obtener los metadatos reales de compilación (timestamp Gradle y modo)
/// desde la capa nativa Android mediante el canal de control.
class AppBuildInfoService {
  static const MethodChannel _defaultChannel = MethodChannel(
    'es.estela/bridge_controls',
  );

  static AppBuildInfo? _cachedInfo;

  /// Limpia la caché (útil para pruebas unitarias).
  @visibleForTesting
  static void resetCache() {
    _cachedInfo = null;
  }

  /// Inyecta información manualmente (útil para pruebas de widgets o mocks).
  @visibleForTesting
  static void setMockInfo(AppBuildInfo? info) {
    _cachedInfo = info;
  }

  /// Obtiene los metadatos de compilación del binario actual.
  static Future<AppBuildInfo> getBuildInfo({MethodChannel? channel}) async {
    if (_cachedInfo != null && channel == null) {
      return _cachedInfo!;
    }

    final targetChannel = channel ?? _defaultChannel;
    DateTime? buildTime;
    String buildMode = kDebugMode ? 'DEBUG' : 'RELEASE';

    try {
      final res = await targetChannel.invokeMapMethod<String, dynamic>(
        'getAppBuildInfo',
      );
      if (res != null) {
        final timestamp = res['buildTimestamp'];
        if (timestamp is int && timestamp > 0) {
          buildTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
        }
        final type = res['buildType'];
        if (type is String && type.isNotEmpty) {
          buildMode = type;
        }
      }
    } catch (_) {
      // Entorno no Android o pruebas unitarias sin canal nativo
    }

    final info = AppBuildInfo(buildTime: buildTime, buildMode: buildMode);

    if (channel == null) {
      _cachedInfo = info;
    }
    return info;
  }
}
