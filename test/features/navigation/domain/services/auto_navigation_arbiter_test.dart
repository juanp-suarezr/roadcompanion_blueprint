import 'package:flutter_test/flutter_test.dart';
import 'package:road_companion/road_companion.dart';

void main() {
  group('AutoNavigationSourceArbiter - 16 Pruebas Obligatorias de Selección AUTO', () {
    late AutoNavigationSourceArbiter arbiter;
    late DateTime baseTime;

    setUp(() {
      baseTime = DateTime(2026, 10, 30, 10, 0, 0);
      arbiter = AutoNavigationSourceArbiter(
        stalenessTimeout: const Duration(seconds: 45),
      );
    });

    BridgeNavigationInstruction createInstruction({
      required BridgeSourceType source,
      required ManeuverType maneuver,
      int? distanceMeters,
      String? street,
      required String rawText,
      DateTime? timestamp,
      BridgeInstructionStatus status = BridgeInstructionStatus.recognized,
      String? discardReason,
      bool isRemoved = false,
    }) {
      return BridgeNavigationInstruction(
        source: source,
        maneuverType: maneuver,
        distanceMeters: distanceMeters,
        destinationStreet: street,
        rawText: rawText,
        receivedAt: timestamp ?? baseTime,
        status: status,
        discardReason: discardReason,
      );
    }

    // 1. Primera instrucción válida de Waze
    test('1. Primera instrucción válida de Waze activa Waze como fuente', () {
      final wazeInst = createInstruction(
        source: BridgeSourceType.waze,
        maneuver: ManeuverType.right,
        distanceMeters: 500,
        street: 'Calle 100',
        rawText: 'Gira a la derecha en 500 m hacia Calle 100',
        timestamp: baseTime,
      );

      final res = arbiter.processInstruction(
        wazeInst,
        correlationId: 'evt_waze_1',
      );

      expect(res.action, equals(AutoArbitrationAction.activated));
      expect(res.newSource, equals(BridgeSourceType.waze));
      expect(arbiter.activeSource, equals(BridgeSourceType.waze));
      expect(arbiter.currentActiveInstruction, equals(wazeInst));
      expect(res.shouldTransmitToBle, isTrue);
    });

    // 2. Primera instrucción válida de Google Maps
    test(
      '2. Primera instrucción válida de Google Maps activa Maps como fuente',
      () {
        final mapsInst = createInstruction(
          source: BridgeSourceType.googleMaps,
          maneuver: ManeuverType.left,
          distanceMeters: 300,
          street: 'Carrera 7',
          rawText: 'Gira a la izquierda en 300 m hacia Carrera 7',
          timestamp: baseTime,
        );

        final res = arbiter.processInstruction(
          mapsInst,
          correlationId: 'evt_maps_1',
        );

        expect(res.action, equals(AutoArbitrationAction.activated));
        expect(res.newSource, equals(BridgeSourceType.googleMaps));
        expect(arbiter.activeSource, equals(BridgeSourceType.googleMaps));
        expect(arbiter.currentActiveInstruction, equals(mapsInst));
        expect(res.shouldTransmitToBle, isTrue);
      },
    );

    // 3. Banner genérico de Waze
    test(
      '3. Banner genérico de Waze ("En ejecución. Toca para abrir.") es ignorado',
      () {
        final bannerInst = createInstruction(
          source: BridgeSourceType.waze,
          maneuver: ManeuverType.unknown,
          rawText: 'Waze — En ejecución. Toca para abrir.',
          status: BridgeInstructionStatus.unrecognized,
          discardReason: 'Notificación de servicio activo en segundo plano',
          timestamp: baseTime,
        );

        final res = arbiter.processInstruction(
          bannerInst,
          correlationId: 'evt_waze_banner',
        );

        expect(res.action, equals(AutoArbitrationAction.ignored));
        expect(arbiter.activeSource, isNull);
        expect(arbiter.currentActiveInstruction, isNull);
        expect(res.shouldTransmitToBle, isFalse);
      },
    );

    // 4. Notificación vacía
    test('4. Notificación vacía es ignorada sin alterar el estado activo', () {
      final emptyInst = createInstruction(
        source: BridgeSourceType.googleMaps,
        maneuver: ManeuverType.unknown,
        rawText: '',
        status: BridgeInstructionStatus.unrecognized,
        discardReason: 'Notificación vacía',
        timestamp: baseTime,
      );

      final res = arbiter.processInstruction(
        emptyInst,
        correlationId: 'evt_empty',
      );

      expect(res.action, equals(AutoArbitrationAction.ignored));
      expect(arbiter.activeSource, isNull);
      expect(res.shouldTransmitToBle, isFalse);
    });

    // 5. Instrucción desconocida
    test('5. Instrucción desconocida sin giro válido es ignorada', () {
      final unknownInst = createInstruction(
        source: BridgeSourceType.waze,
        maneuver: ManeuverType.unknown,
        rawText: 'Waze buscando señal GPS',
        status: BridgeInstructionStatus.unrecognized,
        discardReason: 'Sin maniobra de navegación válida',
        timestamp: baseTime,
      );

      final res = arbiter.processInstruction(
        unknownInst,
        correlationId: 'evt_unknown',
      );

      expect(res.action, equals(AutoArbitrationAction.ignored));
      expect(arbiter.activeSource, isNull);
      expect(res.shouldTransmitToBle, isFalse);
    });

    // 6. Dos instrucciones válidas de fuentes diferentes: prevalece la más reciente
    test(
      '6. Dos instrucciones válidas de fuentes distintas: prevalece la más reciente en timestamp',
      () {
        final mapsInst = createInstruction(
          source: BridgeSourceType.googleMaps,
          maneuver: ManeuverType.left,
          distanceMeters: 400,
          rawText: 'En 400 m gira a la izquierda',
          timestamp: baseTime,
        );
        final wazeInst = createInstruction(
          source: BridgeSourceType.waze,
          maneuver: ManeuverType.right,
          distanceMeters: 200,
          rawText: 'Gira a la derecha en 200 m',
          timestamp: baseTime.add(const Duration(seconds: 5)),
        );

        arbiter.processInstruction(mapsInst, correlationId: 'evt_maps_6');
        expect(arbiter.activeSource, equals(BridgeSourceType.googleMaps));

        final res2 = arbiter.processInstruction(
          wazeInst,
          correlationId: 'evt_waze_6',
        );

        expect(res2.action, equals(AutoArbitrationAction.switched));
        expect(res2.previousSource, equals(BridgeSourceType.googleMaps));
        expect(res2.newSource, equals(BridgeSourceType.waze));
        expect(arbiter.activeSource, equals(BridgeSourceType.waze));
        expect(arbiter.currentActiveInstruction, equals(wazeInst));
      },
    );

    // 7. Cambio Maps → Waze
    test(
      '7. Transición controlada Maps -> Waze ante maniobra más reciente de Waze',
      () {
        final mapsInst = createInstruction(
          source: BridgeSourceType.googleMaps,
          maneuver: ManeuverType.right,
          distanceMeters: 700,
          rawText: 'Gira a la derecha en 700 m',
          timestamp: baseTime,
        );
        arbiter.processInstruction(mapsInst, correlationId: 'evt_maps_7');

        final wazeInst = createInstruction(
          source: BridgeSourceType.waze,
          maneuver: ManeuverType.left,
          distanceMeters: 300,
          rawText: 'Gira a la izquierda en 300 m',
          timestamp: baseTime.add(const Duration(seconds: 3)),
        );

        final res = arbiter.processInstruction(
          wazeInst,
          correlationId: 'evt_waze_7',
        );

        expect(res.action, equals(AutoArbitrationAction.switched));
        expect(res.previousSource, equals(BridgeSourceType.googleMaps));
        expect(res.newSource, equals(BridgeSourceType.waze));
        expect(arbiter.activeSource, equals(BridgeSourceType.waze));
      },
    );

    // 8. Cambio Waze → Maps
    test(
      '8. Transición controlada Waze -> Maps ante maniobra más reciente de Maps',
      () {
        final wazeInst = createInstruction(
          source: BridgeSourceType.waze,
          maneuver: ManeuverType.left,
          distanceMeters: 600,
          rawText: 'Gira a la izquierda en 600 m',
          timestamp: baseTime,
        );
        arbiter.processInstruction(wazeInst, correlationId: 'evt_waze_8');

        final mapsInst = createInstruction(
          source: BridgeSourceType.googleMaps,
          maneuver: ManeuverType.right,
          distanceMeters: 250,
          rawText: 'Gira a la derecha en 250 m',
          timestamp: baseTime.add(const Duration(seconds: 4)),
        );

        final res = arbiter.processInstruction(
          mapsInst,
          correlationId: 'evt_maps_8',
        );

        expect(res.action, equals(AutoArbitrationAction.switched));
        expect(res.previousSource, equals(BridgeSourceType.waze));
        expect(res.newSource, equals(BridgeSourceType.googleMaps));
        expect(arbiter.activeSource, equals(BridgeSourceType.googleMaps));
      },
    );

    // 9. Cancelación de Waze mientras Maps continúa
    test(
      '9. Cancelación de Waze mientras Maps continúa activa el fallback a Maps',
      () {
        final mapsInst = createInstruction(
          source: BridgeSourceType.googleMaps,
          maneuver: ManeuverType.right,
          distanceMeters: 400,
          rawText: 'Gira a la derecha en 400 m',
          timestamp: baseTime,
        );
        arbiter.processInstruction(mapsInst, correlationId: 'evt_maps_9');

        final wazeInst = createInstruction(
          source: BridgeSourceType.waze,
          maneuver: ManeuverType.left,
          distanceMeters: 100,
          rawText: 'Gira a la izquierda en 100 m',
          timestamp: baseTime.add(const Duration(seconds: 2)),
        );
        arbiter.processInstruction(wazeInst, correlationId: 'evt_waze_9');
        expect(arbiter.activeSource, equals(BridgeSourceType.waze));

        // Se cancela Waze a los 10 segundos (Maps tiene 10s de antigüedad, unexpired <= 45s)
        final wazeRemoval = createInstruction(
          source: BridgeSourceType.waze,
          maneuver: ManeuverType.unknown,
          rawText: '',
          status: BridgeInstructionStatus.stale,
          timestamp: baseTime.add(const Duration(seconds: 10)),
          isRemoved: true,
        );

        final res = arbiter.processInstruction(
          wazeRemoval,
          correlationId: 'evt_waze_cancel',
          isRemoved: true,
        );

        expect(res.action, equals(AutoArbitrationAction.fallbackActivated));
        expect(res.newSource, equals(BridgeSourceType.googleMaps));
        expect(arbiter.activeSource, equals(BridgeSourceType.googleMaps));
        expect(arbiter.currentActiveInstruction, equals(mapsInst));
        expect(res.shouldTransmitToBle, isTrue);
      },
    );

    // 10. Cancelación de Maps mientras Waze continúa
    test(
      '10. Cancelación de Maps mientras Waze continúa activa el fallback a Waze',
      () {
        final wazeInst = createInstruction(
          source: BridgeSourceType.waze,
          maneuver: ManeuverType.right,
          distanceMeters: 550,
          rawText: 'Gira a la derecha en 550 m',
          timestamp: baseTime,
        );
        arbiter.processInstruction(wazeInst, correlationId: 'evt_waze_10');

        final mapsInst = createInstruction(
          source: BridgeSourceType.googleMaps,
          maneuver: ManeuverType.left,
          distanceMeters: 200,
          rawText: 'Gira a la izquierda en 200 m',
          timestamp: baseTime.add(const Duration(seconds: 3)),
        );
        arbiter.processInstruction(mapsInst, correlationId: 'evt_maps_10');
        expect(arbiter.activeSource, equals(BridgeSourceType.googleMaps));

        // Se cancela Maps a los 8 segundos
        final mapsRemoval = createInstruction(
          source: BridgeSourceType.googleMaps,
          maneuver: ManeuverType.unknown,
          rawText: '',
          status: BridgeInstructionStatus.stale,
          timestamp: baseTime.add(const Duration(seconds: 8)),
          isRemoved: true,
        );

        final res = arbiter.processInstruction(
          mapsRemoval,
          correlationId: 'evt_maps_cancel',
          isRemoved: true,
        );

        expect(res.action, equals(AutoArbitrationAction.fallbackActivated));
        expect(res.newSource, equals(BridgeSourceType.waze));
        expect(arbiter.activeSource, equals(BridgeSourceType.waze));
        expect(arbiter.currentActiveInstruction, equals(wazeInst));
        expect(res.shouldTransmitToBle, isTrue);
      },
    );

    // 11. Cancelación de ambas fuentes
    test(
      '11. Cancelación de ambas fuentes pasa a estado sin navegación y detiene BLE',
      () {
        final mapsInst = createInstruction(
          source: BridgeSourceType.googleMaps,
          maneuver: ManeuverType.right,
          distanceMeters: 400,
          rawText: 'Gira a la derecha en 400 m',
          timestamp: baseTime,
        );
        arbiter.processInstruction(mapsInst, correlationId: 'evt_maps_11');

        // Cancelar Maps cuando no hay otra fuente
        final mapsRemoval = createInstruction(
          source: BridgeSourceType.googleMaps,
          maneuver: ManeuverType.unknown,
          rawText: '',
          status: BridgeInstructionStatus.stale,
          timestamp: baseTime.add(const Duration(seconds: 5)),
          isRemoved: true,
        );

        final res = arbiter.processInstruction(
          mapsRemoval,
          correlationId: 'evt_maps_cancel_11',
          isRemoved: true,
        );

        expect(res.action, equals(AutoArbitrationAction.sourceEnded));
        expect(arbiter.activeSource, isNull);
        expect(arbiter.currentActiveInstruction, isNull);
        expect(res.shouldStopBleNavigation, isTrue);
      },
    );

    // 12. Notificación antigua recibida después de una nueva
    test(
      '12. Notificación antigua recibida después de una nueva es ignorada',
      () {
        final newerInst = createInstruction(
          source: BridgeSourceType.waze,
          maneuver: ManeuverType.right,
          distanceMeters: 300,
          rawText: 'Gira a la derecha en 300 m',
          timestamp: baseTime.add(const Duration(seconds: 10)),
        );
        arbiter.processInstruction(newerInst, correlationId: 'evt_waze_new');

        final olderInst = createInstruction(
          source: BridgeSourceType.waze,
          maneuver: ManeuverType.right,
          distanceMeters: 500,
          rawText: 'Gira a la derecha en 500 m',
          timestamp: baseTime, // 10 segundos antes
        );

        final res = arbiter.processInstruction(
          olderInst,
          correlationId: 'evt_waze_old',
        );

        expect(res.action, equals(AutoArbitrationAction.ignored));
        expect(arbiter.currentActiveInstruction, equals(newerInst));
        expect(arbiter.currentActiveInstruction!.distanceMeters, equals(300));
      },
    );

    // 13. Notificación duplicada
    test(
      '13. Notificación duplicada idéntica no provoca transmisión BLE repetida',
      () {
        final inst = createInstruction(
          source: BridgeSourceType.googleMaps,
          maneuver: ManeuverType.left,
          distanceMeters: 400,
          street: 'Carrera 7',
          rawText: 'Gira a la izquierda en 400 m hacia Carrera 7',
          timestamp: baseTime,
        );

        final res1 = arbiter.processInstruction(
          inst,
          correlationId: 'evt_dup_1',
        );
        expect(res1.action, equals(AutoArbitrationAction.activated));

        final dupInst = createInstruction(
          source: BridgeSourceType.googleMaps,
          maneuver: ManeuverType.left,
          distanceMeters: 400,
          street: 'Carrera 7',
          rawText: 'Gira a la izquierda en 400 m hacia Carrera 7',
          timestamp: baseTime.add(const Duration(seconds: 1)),
        );

        final res2 = arbiter.processInstruction(
          dupInst,
          correlationId: 'evt_dup_2',
        );

        expect(res2.action, equals(AutoArbitrationAction.duplicate));
        expect(res2.shouldTransmitToBle, isFalse);
      },
    );

    // 14. Eliminación de una notificación sin instrucción previa
    test(
      '14. Eliminación de notificación sin instrucción previa se descarta limpiamente',
      () {
        final orphanRemoval = createInstruction(
          source: BridgeSourceType.waze,
          maneuver: ManeuverType.unknown,
          rawText: '',
          status: BridgeInstructionStatus.stale,
          isRemoved: true,
        );

        final res = arbiter.processInstruction(
          orphanRemoval,
          correlationId: 'evt_orphan',
          isRemoved: true,
        );

        expect(res.action, equals(AutoArbitrationAction.ignored));
        expect(arbiter.activeSource, isNull);
      },
    );

    // 15. Reconexión BLE durante navegación
    test(
      '15. Reconexión BLE durante navegación conserva la instrucción activa',
      () {
        final mapsInst = createInstruction(
          source: BridgeSourceType.googleMaps,
          maneuver: ManeuverType.right,
          distanceMeters: 350,
          rawText: 'Gira a la derecha en 350 m',
          timestamp: baseTime,
        );
        arbiter.processInstruction(mapsInst, correlationId: 'evt_maps_15');

        expect(arbiter.activeSource, equals(BridgeSourceType.googleMaps));
        expect(arbiter.currentActiveInstruction, equals(mapsInst));

        // Simular reconexión: el árbitro conserva la instrucción activa lista para retransmitir
        final current = arbiter.currentActiveInstruction;
        expect(current, isNotNull);
        expect(current!.isCompatibleWithTripper, isTrue);
        expect(current.maneuverType, equals(ManeuverType.right));
      },
    );

    // 16. Navegación interna explícita sin interferencia de fuentes externas
    test(
      '16. Navegación interna explícita ignora notificaciones externas de Waze y Maps',
      () {
        arbiter.setInternalNavigationActive(true);

        final wazeInst = createInstruction(
          source: BridgeSourceType.waze,
          maneuver: ManeuverType.right,
          distanceMeters: 200,
          rawText: 'Gira a la derecha en 200 m',
          timestamp: baseTime,
        );

        final resWaze = arbiter.processInstruction(
          wazeInst,
          correlationId: 'evt_waze_16',
        );

        expect(resWaze.action, equals(AutoArbitrationAction.ignored));
        expect(arbiter.activeSource, isNull);
        expect(resWaze.shouldTransmitToBle, isFalse);

        final mapsInst = createInstruction(
          source: BridgeSourceType.googleMaps,
          maneuver: ManeuverType.left,
          distanceMeters: 500,
          rawText: 'Gira a la izquierda en 500 m',
          timestamp: baseTime.add(const Duration(seconds: 2)),
        );

        final resMaps = arbiter.processInstruction(
          mapsInst,
          correlationId: 'evt_maps_16',
        );

        expect(resMaps.action, equals(AutoArbitrationAction.ignored));
        expect(arbiter.activeSource, isNull);
        expect(resMaps.shouldTransmitToBle, isFalse);
      },
    );
  });
}
