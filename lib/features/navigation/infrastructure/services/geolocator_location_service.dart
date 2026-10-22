import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../domain/entities/coordinates.dart';
import '../../domain/entities/gps_position.dart';
import '../../domain/services/location_service.dart';

/// Implementación real de [LocationService] utilizando el paquete oficial `geolocator`
/// con soporte opcional para Foreground Service en Android.
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
  Future<bool> checkBackgroundPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always;
  }

  @override
  Future<LocationPermissionResult> requestBackgroundPermission() async {
    final enabled = await isLocationServiceEnabled();
    if (!enabled) {
      return LocationPermissionResult.serviceDisabled;
    }

    final current = await Geolocator.checkPermission();
    if (current == LocationPermission.always) {
      return LocationPermissionResult.granted;
    }

    if (current == LocationPermission.denied) {
      final req = await Geolocator.requestPermission();
      if (req != LocationPermission.whileInUse &&
          req != LocationPermission.always) {
        return _mapPermission(req);
      }
    }

    final reqBg = await Geolocator.requestPermission();
    return _mapPermission(reqBg);
  }

  @override
  Stream<GpsPosition> getPositionStream({
    int distanceFilterMeters = 2,
    int intervalDurationMs = 1000,
    bool enableBackgroundNotification = false,
    String? notificationTitle,
    String? notificationText,
  }) {
    LocationSettings settings;
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        enableBackgroundNotification) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilterMeters,
        intervalDuration: Duration(milliseconds: intervalDurationMs),
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle:
              notificationTitle ?? 'Navegación activa — REstelar',
          notificationText:
              notificationText ?? 'Siguiendo ruta en segundo plano',
          notificationIcon: const AndroidResource(
            name: 'ic_launcher',
            defType: 'mipmap',
          ),
          enableWakeLock: true,
        ),
      );
    } else {
      settings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilterMeters,
        timeLimit: null,
      );
    }

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

  @override
  Future<GpsPosition?> getCurrentPosition({
    Duration timeLimit = const Duration(seconds: 8),
  }) async {
    final enabled = await isLocationServiceEnabled();
    if (!enabled) return null;

    final permission = await checkPermission();
    if (permission != LocationPermissionResult.granted) {
      return null;
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeLimit,
        ),
      );

      if (!pos.latitude.isFinite ||
          !pos.longitude.isFinite ||
          pos.latitude < -90.0 ||
          pos.latitude > 90.0 ||
          pos.longitude < -180.0 ||
          pos.longitude > 180.0) {
        return null;
      }

      return GpsPosition(
        coordinates: Coordinates(pos.latitude, pos.longitude),
        accuracyMeters: pos.accuracy.isFinite && pos.accuracy >= 0.0
            ? pos.accuracy
            : 999.0,
        altitudeMeters: pos.altitude.isFinite ? pos.altitude : null,
        speedMps: (pos.speed.isFinite && pos.speed >= 0.0) ? pos.speed : null,
        headingDegrees: (pos.heading.isFinite && pos.heading >= 0.0)
            ? pos.heading
            : null,
        timestamp: pos.timestamp,
      );
    } catch (_) {
      return null;
    }
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
