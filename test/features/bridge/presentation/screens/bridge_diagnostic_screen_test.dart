import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_companion/road_companion.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BridgeDiagnosticScreen - Pruebas de Interfaz y Diagnóstico', () {
    late StreamController<Map<dynamic, dynamic>> eventController;
    late MethodChannel controlChannel;
    late _MockEventChannel mockEventChannel;
    late BridgeNativeChannel nativeChannel;
    late BridgeDiagnosticController controller;

    setUp(() {
      eventController = StreamController<Map<dynamic, dynamic>>.broadcast();
      mockEventChannel = _MockEventChannel(eventController.stream);
      controlChannel = const MethodChannel('es.estela/bridge_controls_mock');

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, (MethodCall call) async {
            if (call.method == 'isNotificationAccessGranted') {
              return true;
            }
            if (call.method == 'clearCache') {
              return true;
            }
            return true;
          });

      nativeChannel = BridgeNativeChannel(
        controlChannel: controlChannel,
        eventChannel: mockEventChannel,
      );

      controller = BridgeDiagnosticController(nativeChannel: nativeChannel);
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, null);
      controller.dispose();
      await eventController.close();
    });

    Widget createWidgetUnderTest() {
      return MaterialApp(home: BridgeDiagnosticScreen(controller: controller));
    }

    testWidgets('renderiza estado inicial y banner de permiso concedido', (
      tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('Diagnóstico ESTELA Bridge'), findsOneWidget);
      expect(find.text('Google Maps & Waze -> Tripper'), findsOneWidget);
      expect(find.text('Acceso a Notificaciones: CONCEDIDO'), findsOneWidget);
      expect(find.text('Escucha nativa activa'), findsOneWidget);
      expect(
        find.text('Sin indicaciones capturadas en esta sesión'),
        findsOneWidget,
      );
    });

    testWidgets(
      'muestra tarjeta de instrucción cuando se recibe evento de Maps',
      (tester) async {
        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        // Emitir notificación de Google Maps
        eventController.add({
          'packageName': 'com.google.android.apps.maps',
          'title': 'Gira a la derecha',
          'text': 'en 400 m hacia Carrera 7',
          'timestamp': 1729600000000,
          'isRemoved': false,
        });

        await tester.pumpAndSettle();

        // La tarjeta de última instrucción debe actualizarse
        expect(find.text('Google Maps'), findsOneWidget);
        expect(find.text('Gira a la derecha'), findsWidgets);
        expect(find.text('400 m'), findsOneWidget);
        expect(find.text('Vía: Carrera 7'), findsOneWidget);
        expect(find.text('RECOGNIZED'), findsOneWidget);
      },
    );

    testWidgets('limpia la sesión al presionar el botón de eliminar', (
      tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      eventController.add({
        'packageName': 'com.waze',
        'text': 'En 1,2 km gira a la izquierda',
        'timestamp': 1729600000000,
        'isRemoved': false,
      });

      await tester.pumpAndSettle();
      expect(find.text('Waze'), findsOneWidget);

      // Tocar botón de limpiar sesión
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      // Debe volver al estado vacío
      expect(
        find.text('Sin indicaciones capturadas en esta sesión'),
        findsOneWidget,
      );
    });
  });
}

class _MockEventChannel extends EventChannel {
  final Stream<dynamic> _stream;

  const _MockEventChannel(this._stream) : super('mock_event_channel_screen');

  @override
  Stream<dynamic> receiveBroadcastStream([dynamic arguments]) {
    return _stream;
  }
}
