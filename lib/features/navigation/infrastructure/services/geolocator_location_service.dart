import 'dart:async';
import 'package:geolocator/geolocator.dart';

import '../../../../domain/entities/coordinates.dart';
import '../../domain/entities/gps_position.dart';
import '../../domain/services/location_service.dart';

/// Implementación real de [LocationService] utilizando el paquete oficial `geolocator`.
class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  @override
  Future<bool> isLocationServiceEnabled() async {
    return Geolocator.isLocationServiceEnabled();
  }

  @override
  Future<LocationPermissionResult> checkPermission() async {
    final enabled = await isLocationServiceEnabled();
    if (!enabled) {
      return LocationPermissionResult.serviceDisabled;
    }

    final permission = await Geolocator.checkPermission();
    return _mapPermission(permission);
  }

  @override
  Future<LocationPermissionResult> requestPermission() async {
    final enabled = await isLocationServiceEnabled();
    if (!enabled) {
      return LocationPermissionResult.serviceDisabled;
    }

    final permission = await Geolocator.requestPermission();
    return _mapPermission(permission);
  }

  @override
  Stream<GpsPosition> getPositionStream({
    int distanceFilterMeters = 2,
    int intervalDurationMs = 1000,
  }) {
    final settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: distanceFilterMeters,
      timeLimit: null,
    );

    return Geolocator.getPositionStream(
      locationSettings: settings,
    ).transform(_positionTransformer());
  }

  StreamTransformer<Position, GpsPosition> _positionTransformer() {
    return StreamTransformer<Position, GpsPosition>.fromHandlers(
      handleData: (Position pos, EventSink<GpsPosition> sink) {
        // Validar coordenadas geográficas
        if (!pos.latitude.isFinite ||
            !pos.longitude.isFinite ||
            pos.latitude < -90.0 ||
            pos.latitude > 90.0 ||
            pos.longitude < -180.0 ||
            pos.longitude > 180.0) {
          return; // Descartar lectura corrompida
        }

        try {
          final coordinates = Coordinates(pos.latitude, pos.longitude);
          final gpsPos = GpsPosition(
            coordinates: coordinates,
            accuracyMeters: pos.accuracy.isFinite && pos.accuracy >= 0.0
                ? pos.accuracy
                : 999.0,
            altitudeMeters: pos.altitude.isFinite ? pos.altitude : null,
            speedMps: (pos.speed.isFinite && pos.speed >= 0.0)
                ? pos.speed
                : null,
            headingDegrees: (pos.heading.isFinite && pos.heading >= 0.0)
                ? pos.heading
                : null,
            timestamp: pos.timestamp,
          );
          sink.add(gpsPos);
        } catch (_) {
          // Descartar si ocurre error de validación
        }
      },
      handleError: (error, stackTrace, sink) {
        sink.addError(error, stackTrace);
      },
    );
  }

  LocationPermissionResult _mapPermission(LocationPermission permission) {
    switch (permission) {
      case LocationPermission.whileInUse:
      case LocationPermission.always:
        return LocationPermissionResult.granted;
      case LocationPermission.denied:
        return LocationPermissionResult.denied;
      case LocationPermission.deniedForever:
      case LocationPermission.unableToDetermine:
        return LocationPermissionResult.deniedForever;
    }
  }
}
