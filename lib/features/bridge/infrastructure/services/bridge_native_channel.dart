import 'dart:async';
import 'package:flutter/services.dart';
import '../../domain/entities/bridge_source_type.dart';

/// Estado del permiso de acceso a notificaciones en el sistema Android.
enum BridgePermissionStatus { unknown, granted, denied }

/// Evento crudo normalizado recibido desde el servicio nativo de notificaciones.
class BridgeNotificationEvent {
  final BridgeSourceType source;
  final String? title;
  final String? text;
  final String? subText;
  final DateTime timestamp;
  final bool isRemoved;

  const BridgeNotificationEvent({
    required this.source,
    required this.timestamp,
    this.title,
    this.text,
    this.subText,
    this.isRemoved = false,
  });

  /// Construye un evento a partir del mapa de datos serializado por Kotlin.
  factory BridgeNotificationEvent.fromMap(Map<dynamic, dynamic> map) {
    final pkg = map['packageName'] as String?;
    final source = BridgeSourceType.fromPackageName(pkg);
    final rawTimestamp = map['timestamp'] as num?;
    final timestamp = rawTimestamp != null
        ? DateTime.fromMillisecondsSinceEpoch(rawTimestamp.toInt())
        : DateTime.now();

    return BridgeNotificationEvent(
      source: source,
      title: map['title'] as String?,
      text: map['text'] as String?,
      subText: map['subText'] as String?,
      timestamp: timestamp,
      isRemoved: map['isRemoved'] as bool? ?? false,
    );
  }

  @override
  String toString() =>
      'BridgeNotificationEvent(source: ${source.displayName}, title: "$title", isRemoved: $isRemoved)';
}

/// Adaptador del canal nativo entre Flutter y Android para ESTELA Bridge.
class BridgeNativeChannel {
  static const String _controlChannelName = 'es.estela/bridge_controls';
  static const String _eventChannelName = 'es.estela/navigation_notifications';

  final MethodChannel _controlChannel;
  final EventChannel _eventChannel;
  Stream<BridgeNotificationEvent>? _cachedStream;

  BridgeNativeChannel({
    MethodChannel? controlChannel,
    EventChannel? eventChannel,
  }) : _controlChannel =
           controlChannel ?? const MethodChannel(_controlChannelName),
       _eventChannel = eventChannel ?? const EventChannel(_eventChannelName);

  /// Consulta si el usuario ha habilitado el acceso a notificaciones para ESTELA.
  Future<BridgePermissionStatus> checkNotificationPermission() async {
    try {
      final granted = await _controlChannel.invokeMethod<bool>(
        'isNotificationAccessGranted',
      );
      if (granted == true) {
        return BridgePermissionStatus.granted;
      }
      return BridgePermissionStatus.denied;
    } on PlatformException {
      return BridgePermissionStatus.unknown;
    } catch (_) {
      return BridgePermissionStatus.unknown;
    }
  }

  /// Abre la pantalla del sistema Android donde el usuario puede activar el permiso.
  Future<bool> openNotificationAccessSettings() async {
    try {
      final result = await _controlChannel.invokeMethod<bool>(
        'openNotificationAccessSettings',
      );
      return result ?? false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Limpia la memoria de deduplicación nativa.
  Future<void> clearNativeCache() async {
    try {
      await _controlChannel.invokeMethod<bool>('clearCache');
    } catch (_) {}
  }

  /// Flujo continuo de eventos de notificación emitidos por Google Maps o Waze.
  Stream<BridgeNotificationEvent> get notificationStream {
    _cachedStream ??= _eventChannel
        .receiveBroadcastStream()
        .where((data) => data is Map)
        .map((data) => BridgeNotificationEvent.fromMap(data as Map))
        .asBroadcastStream();
    return _cachedStream!;
  }
}
