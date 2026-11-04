import 'package:flutter_test/flutter_test.dart';
import 'package:road_companion/domain/entities/maneuver_type.dart';
import 'package:road_companion/features/bridge/domain/entities/bridge_instruction_status.dart';
import 'package:road_companion/features/bridge/domain/entities/bridge_source_type.dart';
import 'package:road_companion/features/bridge/domain/services/navigation_instruction_parser.dart';
import 'package:road_companion/features/navigation/domain/services/auto_navigation_source_arbiter.dart';

void main() {
  const parser = NavigationInstructionParser();
  late AutoNavigationSourceArbiter arbiter;
  final baseTime = DateTime(2026, 11, 3, 14, 0, 0);

  setUp(() {
    arbiter = AutoNavigationSourceArbiter(
      stalenessTimeout: const Duration(seconds: 45),
    );
  });

  group('Fixtures Representativos Obligatorios Waze y Google Maps (Sección 4)', () {
    // Fixture 1: Waze con maniobra y distancia
    test(
      '1. Fixture Waze con maniobra y distancia: extrae giro, distancia y calle',
      () {
        final parsed = parser.parseWaze(
          rawTitle: 'En 450 m',
          rawText: 'Gira a la derecha hacia Calle 100',
          receivedAt: baseTime,
          notificationKey: '0|com.waze|101|null|10234',
          notificationCategory: 'navigation',
        );

        expect(parsed.status, equals(BridgeInstructionStatus.recognized));
        expect(parsed.maneuverType, equals(ManeuverType.right));
        expect(parsed.distanceMeters, equals(450));
        expect(parsed.destinationStreet, equals('Calle 100'));
        expect(parsed.isCompatibleWithTripper, isTrue);

        final res = arbiter.processInstruction(parsed, correlationId: 'fix_1');
        expect(res.action, equals(AutoArbitrationAction.activated));
        expect(res.shouldTransmitToBle, isTrue);
      },
    );

    // Fixture 2: Waze con maniobra sin distancia
    test(
      '2. Fixture Waze con maniobra sin distancia: reconoce giro pero sin distancia inventada',
      () {
        final parsed = parser.parseWaze(
          rawTitle: 'Gira a la izquierda',
          rawText: 'por Avenida Boyacá',
          receivedAt: baseTime,
          notificationKey: '0|com.waze|102|null|10234',
        );

        expect(parsed.status, equals(BridgeInstructionStatus.recognized));
        expect(parsed.maneuverType, equals(ManeuverType.left));
        expect(parsed.distanceMeters, isNull); // NO inventa distancia
        expect(parsed.destinationStreet, equals('Avenida Boyacá'));
        // Sin distancia en metros, no puede generar trama turn-by-turn válida al Tripper Pod
        expect(parsed.isCompatibleWithTripper, isFalse);
      },
    );

    // Fixture 3: Waze sin maniobra (ej. aviso de tráfico o evento)
    test(
      '3. Fixture Waze sin maniobra: clasificado como unrecognized sin inventar giros',
      () {
        final parsed = parser.parseWaze(
          rawTitle: 'Tráfico pesado reportado',
          rawText: 'Retraso estimado de 12 min',
          receivedAt: baseTime,
          notificationKey: '0|com.waze|103|null|10234',
        );

        expect(parsed.status, equals(BridgeInstructionStatus.unrecognized));
        expect(parsed.maneuverType, equals(ManeuverType.unknown));
        expect(parsed.distanceMeters, isNull);
        expect(parsed.isCompatibleWithTripper, isFalse);

        final res = arbiter.processInstruction(parsed, correlationId: 'fix_3');
        expect(res.action, equals(AutoArbitrationAction.ignored));
        expect(res.shouldTransmitToBle, isFalse);
      },
    );

    // Fixture 4: Notificación que solo contiene 'Waze' y 'com.waze' (metadatos/banner)
    test(
      '4. Fixture Waze con solo "Waze" y "com.waze": filtrado como banner genérico',
      () {
        final parsed = parser.parseWaze(
          rawTitle: 'Waze',
          rawText: 'com.waze',
          receivedAt: baseTime,
          notificationKey: '0|com.waze|104|null|10234',
        );

        expect(parsed.status, equals(BridgeInstructionStatus.unrecognized));
        expect(parsed.isAppRunningNotification, isTrue);
        expect(parsed.maneuverType, equals(ManeuverType.unknown));
        expect(parsed.discardReason, contains('segundo plano'));
        expect(parsed.isCompatibleWithTripper, isFalse);

        final res = arbiter.processInstruction(parsed, correlationId: 'fix_4');
        expect(res.action, equals(AutoArbitrationAction.ignored));
        expect(res.shouldTransmitToBle, isFalse);
      },
    );

    // Fixture 5: Notificación informativa (ej. "En ejecución", "Buscando señal GPS")
    test(
      '5. Fixture informativa de servicio: catalogada como informativa sin alterar navegación',
      () {
        final parsed = parser.parseWaze(
          rawTitle: 'Waze',
          rawText: 'En ejecución. Toca para abrir.',
          receivedAt: baseTime,
          notificationKey: '0|com.waze|105|service|10234',
        );

        expect(parsed.status, equals(BridgeInstructionStatus.unrecognized));
        expect(parsed.isAppRunningNotification, isTrue);
        expect(parsed.maneuverType, equals(ManeuverType.unknown));
        expect(parsed.isCompatibleWithTripper, isFalse);

        final res = arbiter.processInstruction(parsed, correlationId: 'fix_5');
        expect(res.action, equals(AutoArbitrationAction.ignored));
        expect(res.shouldTransmitToBle, isFalse);
      },
    );

    // Fixture 6: Actualización de instrucción (nueva distancia sobre la misma vía)
    test(
      '6. Fixture actualización de instrucción: actualiza distancia y tipo en la fuente activa',
      () {
        final first = parser.parseWaze(
          rawTitle: 'En 800 m',
          rawText: 'Gira a la derecha por Carrera 15',
          receivedAt: baseTime,
          notificationKey: '0|com.waze|106|null|10234',
        );
        final res1 = arbiter.processInstruction(
          first,
          correlationId: 'fix_6_1',
        );
        expect(res1.action, equals(AutoArbitrationAction.activated));

        final update = parser.parseWaze(
          rawTitle: 'En 300 m',
          rawText: 'Gira a la derecha por Carrera 15',
          receivedAt: baseTime.add(const Duration(seconds: 10)),
          notificationKey: '0|com.waze|106|null|10234',
        );
        final res2 = arbiter.processInstruction(
          update,
          correlationId: 'fix_6_2',
        );

        expect(res2.action, equals(AutoArbitrationAction.updated));
        expect(res2.shouldTransmitToBle, isTrue);
        expect(arbiter.currentActiveInstruction?.distanceMeters, equals(300));
      },
    );

    // Fixture 7: Cancelación de instrucción (stale / usuario cierra viaje)
    test(
      '7. Fixture cancelación de instrucción: elimina la instrucción y apaga BLE',
      () {
        final inst = parser.parseWaze(
          rawTitle: 'En 200 m',
          rawText: 'Gira a la izquierda',
          receivedAt: baseTime,
        );
        arbiter.processInstruction(inst, correlationId: 'fix_7_1');
        expect(arbiter.activeSource, equals(BridgeSourceType.waze));

        // Cancelación explícita
        final cancel = parser
            .parse(
              rawTitle: '',
              rawText: '',
              source: BridgeSourceType.waze,
              receivedAt: baseTime.add(const Duration(seconds: 5)),
            )
            .asStale(discardReason: 'Viaje cancelado por el usuario');

        final res = arbiter.processInstruction(
          cancel,
          correlationId: 'fix_7_2',
          isRemoved: true,
        );

        expect(res.action, equals(AutoArbitrationAction.sourceEnded));
        expect(res.shouldStopBleNavigation, isTrue);
        expect(arbiter.activeSource, isNull);
      },
    );

    // Fixture 8: Google Maps con instrucciones completas
    test(
      '8. Fixture Google Maps con instrucciones: extrae distancia en km y giro',
      () {
        final parsed = parser.parseGoogleMaps(
          rawTitle: 'Gira a la izquierda en 1,2 km',
          rawText: 'hacia Autopista Norte',
          receivedAt: baseTime,
          notificationKey:
              '0|com.google.android.apps.maps|201|navigation|10234',
        );

        expect(parsed.status, equals(BridgeInstructionStatus.recognized));
        expect(parsed.maneuverType, equals(ManeuverType.left));
        expect(parsed.distanceMeters, equals(1200));
        expect(parsed.destinationStreet, equals('Autopista Norte'));
        expect(parsed.isCompatibleWithTripper, isTrue);

        final res = arbiter.processInstruction(parsed, correlationId: 'fix_8');
        expect(res.action, equals(AutoArbitrationAction.activated));
        expect(res.shouldTransmitToBle, isTrue);
        expect(arbiter.activeSource, equals(BridgeSourceType.googleMaps));
      },
    );

    // Fixture 9: Eliminación de notificación (isRemoved = true)
    test(
      '9. Fixture eliminación de notificación: limpia estado de la fuente eliminada',
      () {
        final mapsInst = parser.parseGoogleMaps(
          rawTitle: 'Gira a la derecha',
          rawText: 'en 300 m',
          receivedAt: baseTime,
        );
        arbiter.processInstruction(mapsInst, correlationId: 'fix_9_1');
        expect(arbiter.activeSource, equals(BridgeSourceType.googleMaps));

        // Se recibe evento StatusBarNotification removed
        final removal = parser.parse(
          rawTitle: null,
          rawText: null,
          source: BridgeSourceType.googleMaps,
          receivedAt: baseTime.add(const Duration(seconds: 2)),
        );

        final res = arbiter.processInstruction(
          removal,
          correlationId: 'fix_9_2',
          isRemoved: true,
        );

        expect(res.action, equals(AutoArbitrationAction.sourceEnded));
        expect(res.shouldStopBleNavigation, isTrue);
        expect(arbiter.activeSource, isNull);
      },
    );
  });
}
