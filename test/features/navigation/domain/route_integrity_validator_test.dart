import 'package:flutter_test/flutter_test.dart';
import 'package:road_companion/domain/entities/coordinates.dart';
import 'package:road_companion/features/navigation/domain/services/route_integrity_validator.dart';

void main() {
  group('RouteIntegrityValidator - Validación de trazado, accesos y seguridad vial', () {
    final origin = Coordinates(5.0688, -75.5173);
    final destination = Coordinates(5.0345, -75.4820);

    test('1. Rechaza geometría vacía con status invalidGeometry', () {
      final result = RouteIntegrityValidator.validate(
        geometry: const [],
        origin: origin,
        destination: destination,
      );

      expect(result.isValid, isFalse);
      expect(result.status, equals(RouteValidationStatus.invalidGeometry));
      expect(result.warnings.any((w) => w.contains('vacía')), isTrue);
    });

    test('2. Caso 1 (Urbano): Vía pública transitable que conecta perfectamente con el destino', () {
      final publicRouteCoords = [
        origin,
        Coordinates(5.0500, -75.5000),
        destination,
      ];
      final publicSteps = [
        {
          'name': 'Avenida Santander',
          'access': 'yes',
        },
        {
          'name': 'Carrera 23',
          'access': 'public',
        },
      ];

      final result = RouteIntegrityValidator.validate(
        geometry: publicRouteCoords,
        origin: origin,
        destination: destination,
        rawSteps: publicSteps,
      );

      expect(result.isValid, isTrue);
      expect(result.isPubliclyPassable, isTrue);
      expect(result.isConfirmedRestricted, isFalse);
      expect(result.hasWarnings, isFalse);
      expect(result.status, equals(RouteValidationStatus.viable));
      expect(result.destinationGapMeters, closeTo(0.0, 1.0));
      expect(result.isFieldVerified, isFalse);
    });

    test('3. Caso 2 (Urbano): Vía privada con access=private', () {
      final rawSteps = [
        {
          'name': 'Callejón Empresa Privada',
          'access': 'private',
        },
      ];

      final result = RouteIntegrityValidator.validate(
        geometry: [origin, destination],
        origin: origin,
        destination: destination,
        rawSteps: rawSteps,
      );

      expect(result.isValid, isTrue);
      expect(result.status, equals(RouteValidationStatus.confirmedRestrictedAccess));
      expect(result.isConfirmedRestricted, isTrue);
      expect(result.isPubliclyPassable, isFalse);
      expect(result.hasRestrictedAccess, isTrue);
      expect(result.warnings.any((w) => w.contains('access=private')), isTrue);
    });

    test('4. Caso 3 (Urbano): Vía restringida a vehículos con motor_vehicle=no o vehicle=private', () {
      final rawSteps = [
        {
          'name': 'Paso Peatonal / Restringido',
          'motor_vehicle': 'no',
        },
      ];

      final result = RouteIntegrityValidator.validate(
        geometry: [origin, destination],
        origin: origin,
        destination: destination,
        rawSteps: rawSteps,
      );

      expect(result.isValid, isTrue);
      expect(result.status, equals(RouteValidationStatus.confirmedRestrictedAccess));
      expect(result.isConfirmedRestricted, isTrue);
      expect(result.isPubliclyPassable, isFalse);
      expect(result.warnings.any((w) => w.contains('motor_vehicle=no')), isTrue);
    });

    test('5. Caso 4 (Urbano): Calle pública que termina legítimamente en el destino (callejón sin salida público)', () {
      // La vía es un cul-de-sac público cuyo final vehicular dista 20m de la puerta del destino
      final culDeSacEnd = Coordinates(5.0346, -75.4821);
      final rawSteps = [
        {
          'name': 'Calle 14 Callejón sin salida', // Nombre contiene sin salida pero es pública
          'access': 'yes',
        },
      ];

      final result = RouteIntegrityValidator.validate(
        geometry: [origin, culDeSacEnd],
        origin: origin,
        destination: destination,
        rawSteps: rawSteps,
      );

      // NO debe ser rechazada ni clasificada como privada
      expect(result.isValid, isTrue);
      expect(result.isPubliclyPassable, isTrue);
      expect(result.isConfirmedRestricted, isFalse);
      expect(result.status, equals(RouteValidationStatus.viable));
      expect(result.destinationGapMeters, lessThan(100.0));
      expect(result.hasRestrictedAccess, isFalse);
    });

    test('6. Caso con portón o cerrojo físico barrier=gate', () {
      final rawSteps = [
        {
          'name': 'Entrada Complejo Industrial',
          'barrier': 'gate',
        },
      ];

      final result = RouteIntegrityValidator.validate(
        geometry: [origin, destination],
        origin: origin,
        destination: destination,
        rawSteps: rawSteps,
      );

      expect(result.isValid, isTrue);
      expect(result.status, equals(RouteValidationStatus.confirmedRestrictedAccess));
      expect(result.isConfirmedRestricted, isTrue);
      expect(result.warnings.any((w) => w.contains('portón/cerrojo')), isTrue);
    });

    test('7. Caso 6 (Urbano): Información insuficiente para confirmar acceso (access=unconfirmed/unknown)', () {
      final rawSteps = [
        {
          'name': 'Vía de servicio rural/urbana',
          'access': 'unconfirmed',
        },
      ];

      final result = RouteIntegrityValidator.validate(
        geometry: [origin, destination],
        origin: origin,
        destination: destination,
        rawSteps: rawSteps,
      );

      expect(result.isValid, isTrue);
      expect(result.status, equals(RouteValidationStatus.unconfirmedTransitability));
      expect(result.hasUnconfirmedTransitability, isTrue);
      expect(result.isConfirmedRestricted, isFalse); // No afirma falsamente que sea privada
      expect(result.isPubliclyPassable, isTrue); // Permite el paso con advertencia preventiva
      expect(
        result.warnings.any((w) => w.contains('Información de acceso no confirmada')),
        isTrue,
      );
    });

    test('8. Desconexión vial o brecha grande al destino (> 300m) genera destinationGapWarning', () {
      final farLastPoint = Coordinates(5.0400, -75.4820); // ~610m de distancia
      final result = RouteIntegrityValidator.validate(
        geometry: [origin, farLastPoint],
        origin: origin,
        destination: destination,
      );

      expect(result.isValid, isTrue);
      expect(result.status, equals(RouteValidationStatus.destinationGapWarning));
      expect(result.hasDestinationGap, isTrue);
      expect(result.destinationGapMeters, greaterThan(300.0));
      expect(result.warnings.any((w) => w.contains('finaliza a')), isTrue);
    });
  });
}
