import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_companion/road_companion.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BridgeNotificationEvent - Deserialización y Filtrado de Paquetes', () {
    test('mapea correctamente mapa emitido por Android para Google Maps', () {
      final map = {
        'packageName': 'com.google.android.apps.maps',
        'title': 'Gira a la derecha',
        'text': 'en 400 m hacia Calle 26',
        'subText': '15 min restante',
        'timestamp': 1729600000000,
        'isRemoved': false,
      };

      final event = BridgeNotificationEvent.fromMap(map);
      expect(event.source, equals(BridgeSourceType.googleMaps));
      expect(event.title, equals('Gira a la derecha'));
      expect(event.text, equals('en 400 m hacia Calle 26'));
      expect(event.subText, equals('15 min restante'));
      expect(event.isRemoved, isFalse);
      expect(event.timestamp.millisecondsSinceEpoch, equals(1729600000000));
    });

    test('mapea correctamente mapa emitido por Android para Waze', () {
      final map = {
        'packageName': 'com.waze',
        'title': 'Waze',
        'text': 'En 1,2 km mantente a la izquierda',
        'subText': null,
        'timestamp': 1729600050000,
        'isRemoved': false,
      };

      final event = BridgeNotificationEvent.fromMap(map);
      expect(event.source, equals(BridgeSourceType.waze));
      expect(event.text, equals('En 1,2 km mantente a la izquierda'));
      expect(event.isRemoved, isFalse);
    });

    test('asigna unknown de forma segura si el paquete es ajeno o nulo', () {
      final map = {
        'packageName': 'com.whatsapp',
        'title': 'Nuevo mensaje',
        'text': 'Hola',
        'timestamp': 1729600000000,
        'isRemoved': false,
      };

      final event = BridgeNotificationEvent.fromMap(map);
      expect(event.source, equals(BridgeSourceType.unknown));
    });
  });

  group('BridgeNativeChannel - Manejo de Canales de Plataforma', () {
    const controlChannel = MethodChannel('es.estela/bridge_controls');
    late List<MethodCall> methodCalls;

    setUp(() {
      methodCalls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, (MethodCall call) async {
            methodCalls.add(call);
            if (call.method == 'isNotificationAccessGranted') {
              return true;
            }
            if (call.method == 'openNotificationAccessSettings') {
              return true;
            }
            if (call.method == 'clearCache') {
              return true;
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, null);
    });

    test(
      'checkNotificationPermission invoca el método nativo y traduce a granted',
      () async {
        final channel = BridgeNativeChannel(controlChannel: controlChannel);
        final status = await channel.checkNotificationPermission();

        expect(status, equals(BridgePermissionStatus.granted));
        expect(methodCalls.length, equals(1));
        expect(methodCalls.first.method, equals('isNotificationAccessGranted'));
      },
    );

    test(
      'openNotificationAccessSettings invoca el método nativo correspondiente',
      () async {
        final channel = BridgeNativeChannel(controlChannel: controlChannel);
        final result = await channel.openNotificationAccessSettings();

        expect(result, isTrue);
        expect(
          methodCalls.any(
            (call) => call.method == 'openNotificationAccessSettings',
          ),
          isTrue,
        );
      },
    );

    test('clearNativeCache invoca clearCache nativo', () async {
      final channel = BridgeNativeChannel(controlChannel: controlChannel);
      await channel.clearNativeCache();

      expect(methodCalls.any((call) => call.method == 'clearCache'), isTrue);
    });
  });

  group('BridgeNavigationSource - Procesamiento Reactivo de Instrucciones', () {
    test(
      'transforma flujo de eventos en instrucciones tipadas mediante el parser',
      () async {
        final eventController = StreamController<Map<dynamic, dynamic>>();
        final mockEventChannel = _MockEventChannel(eventController.stream);
        final nativeChannel = BridgeNativeChannel(
          eventChannel: mockEventChannel,
        );
        final source = BridgeNavigationSource(nativeChannel: nativeChannel);

        final received = <BridgeNavigationInstruction>[];
        final sub = source.instructions.listen(received.add);
        source.start();

        // Emitir evento simulado de Google Maps
        eventController.add({
          'packageName': 'com.google.android.apps.maps',
          'title': 'Gira a la derecha',
          'text': 'en 500 m en Calle 100',
          'timestamp': 1729600000000,
          'isRemoved': false,
        });

        await pumpEventQueue();

        expect(received.length, equals(1));
        final inst = received.first;
        expect(inst.source, equals(BridgeSourceType.googleMaps));
        expect(inst.maneuverType, equals(ManeuverType.right));
        expect(inst.distanceMeters, equals(500));
        expect(inst.status, equals(BridgeInstructionStatus.recognized));
        expect(source.lastInstruction, equals(inst));

        // Emitir evento de notificación retirada
        eventController.add({
          'packageName': 'com.google.android.apps.maps',
          'isRemoved': true,
        });

        await pumpEventQueue();

        expect(received.length, equals(2));
        expect(received.last.status, equals(BridgeInstructionStatus.stale));

        await sub.cancel();
        source.dispose();
        await eventController.close();
      },
    );
  });
}

class _MockEventChannel extends EventChannel {
  final Stream<dynamic> _stream;

  const _MockEventChannel(this._stream) : super('mock_event_channel');

  @override
  Stream<dynamic> receiveBroadcastStream([dynamic arguments]) {
    return _stream;
  }
}
