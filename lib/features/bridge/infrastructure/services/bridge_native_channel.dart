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
  final String? bigText;
  final int? notificationId;
  final String? notificationKey;
  final String? notificationCategory;
  final bool isOngoing;
  final bool isEmptyText;
  final List<String> availableExtras;
  final List<String> remoteViewsTexts;
  final DateTime timestamp;
  final bool isRemoved;

  const BridgeNotificationEvent({
    required this.source,
    required this.timestamp,
    this.title,
    this.text,
    this.subText,
    this.bigText,
    this.notificationId,
    this.notificationKey,
    this.notificationCategory,
    this.isOngoing = false,
    this.isEmptyText = false,
    this.availableExtras = const [],
    this.remoteViewsTexts = const [],
    this.isRemoved = false,
  });

  /// Identificador correlacionado determinista para trazabilidad de extremo a extremo.
  String get correlationId {
    final keyPart =
        notificationKey ??
        (notificationId != null
            ? '${source.packageName}:$notificationId'
            : source.packageName);
    return '$keyPart@${timestamp.millisecondsSinceEpoch}';
  }

  /// Construye un evento a partir del mapa de datos serializado por Kotlin.
  factory BridgeNotificationEvent.fromMap(Map<dynamic, dynamic> map) {
    final pkg = map['packageName'] as String?;
    final source = BridgeSourceType.fromPackageName(pkg);
    final rawTimestamp = map['timestamp'] as num?;
    final timestamp = rawTimestamp != null
        ? DateTime.fromMillisecondsSinceEpoch(rawTimestamp.toInt())
        : DateTime.now();

    final rawExtras = map['availableExtras'];
    final availableExtras = rawExtras is List
        ? rawExtras.map((e) => e.toString()).toList(growable: false)
        : const <String>[];

    final rawRemote = map['remoteViewsTexts'];
    final remoteViewsTexts = rawRemote is List
        ? rawRemote.map((e) => e.toString()).toList(growable: false)
        : const <String>[];

    final rawNotifId = map['notificationId'];
    final notificationId = rawNotifId is num ? rawNotifId.toInt() : null;

    final title = map['title'] as String?;
    final text = map['text'] as String?;
    final subText = map['subText'] as String?;
    final bigText = map['bigText'] as String?;
    final explicitEmpty = map['isEmptyText'] as bool?;
    final isEmptyText =
        explicitEmpty ??
        ((title == null || title.trim().isEmpty) &&
            (text == null || text.trim().isEmpty) &&
            (subText == null || subText.trim().isEmpty) &&
            remoteViewsTexts.isEmpty);

    return BridgeNotificationEvent(
      source: source,
      title: title,
      text: text,
      subText: subText,
      bigText: bigText,
      notificationId: notificationId,
      notificationKey: map['notificationKey'] as String?,
      notificationCategory: map['notificationCategory'] as String?,
      isOngoing: map['isOngoing'] as bool? ?? false,
      isEmptyText: isEmptyText,
      availableExtras: availableExtras,
      remoteViewsTexts: remoteViewsTexts,
      timestamp: timestamp,
      isRemoved: map['isRemoved'] as bool? ?? false,
    );
  }

  @override
  String toString() =>
      'BridgeNotificationEvent(source: ${source.displayName}, key: "$notificationKey", title: "$title", isRemoved: $isRemoved)';
}

/// Adaptador del canal nativo entre Flutter y Android para ESTELA Bridge.
class BridgeNativeChannel {
  static const String _controlChannelName = 'es.estela/bridge_controls';
  static const String _eventChannelName = 'es.estela/navigation_notifications';

  static Stream<BridgeNotificationEvent>? _sharedDefaultNotificationStream;

  final MethodChannel _controlChannel;
  final EventChannel _eventChannel;
  final bool _usesDefaultEventChannel;
  Stream<BridgeNotificationEvent>? _cachedStream;

  BridgeNativeChannel({
    MethodChannel? controlChannel,
    EventChannel? eventChannel,
  }) : _controlChannel =
           controlChannel ?? const MethodChannel(_controlChannelName),
       _eventChannel = eventChannel ?? const EventChannel(_eventChannelName),
       _usesDefaultEventChannel = eventChannel == null;

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

  /// Solicita al servicio nativo inspeccionar inmediatamente las notificaciones activas en la barra de estado.
  Future<void> syncActiveNotifications() async {
    try {
      await _controlChannel.invokeMethod<bool>('syncActiveNotifications');
    } catch (_) {}
  }

  /// Consulta si el servicio nativo NotificationListenerService está enlazado por Android.
  Future<bool> isListenerConnected() async {
    try {
      final connected = await _controlChannel.invokeMethod<bool>(
        'isNotificationListenerConnected',
      );
      return connected ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Configura el paquete de navegación externo permitido para la sesión actual
  /// (`"com.waze"`, `"com.google.android.apps.maps"`, `"none"`, o `"all"`).
  Future<void> setSelectedSourcePackage(String? packageName) async {
    try {
      await _controlChannel.invokeMethod<bool>('setSelectedSourcePackage', {
        'packageName': packageName,
      });
    } catch (_) {}
  }

  /// Obtiene el paquete de navegación actualmente filtrado en la capa nativa.
  Future<String?> getSelectedSourcePackage() async {
    try {
      return await _controlChannel.invokeMethod<String>(
        'getSelectedSourcePackage',
      );
    } catch (_) {
      return null;
    }
  }

  /// Flujo continuo de eventos de notificación emitidos por Google Maps o Waze.
  ///
  /// Cuando se utiliza el canal nativo por defecto, comparte un único broadcast stream
  /// para que múltiples suscriptores en Flutter no sobrescriban ni cancelen prematuramente
  /// el `StreamHandler` nativo en Android.
  Stream<BridgeNotificationEvent> get notificationStream {
    if (_usesDefaultEventChannel) {
      return _sharedDefaultNotificationStream ??= _eventChannel
          .receiveBroadcastStream()
          .where((data) => data is Map)
          .map((data) => BridgeNotificationEvent.fromMap(data as Map))
          .asBroadcastStream();
    }
    _cachedStream ??= _eventChannel
        .receiveBroadcastStream()
        .where((data) => data is Map)
        .map((data) => BridgeNotificationEvent.fromMap(data as Map))
        .asBroadcastStream();
    return _cachedStream!;
  }
}
