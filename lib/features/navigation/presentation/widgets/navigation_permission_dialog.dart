import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../app/theme/app_colors.dart';
import '../../domain/services/location_service.dart';

/// Diálogo contextual y explicativo de permisos para Android 16 (API 36).
///
/// Explica al motociclista por qué se requiere cada permiso antes de solicitarlo al sistema,
/// evitando denegaciones accidentales y gestionando estados permanentemente denegados.
class NavigationPermissionDialog {
  /// Verifica y explica el permiso de ubicación precisa antes de iniciar navegación.
  static Future<bool> ensureLocationPermission(
    BuildContext context, {
    required LocationService locationService,
  }) async {
    // 1. Comprobar si el sensor GPS del dispositivo está activado físicamente
    final isGpsEnabled = await locationService.isLocationServiceEnabled();
    if (!isGpsEnabled) {
      if (!context.mounted) return false;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.backgroundCard,
          title: const Row(
            children: [
              Icon(Icons.location_off_rounded, color: AppColors.warning),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'GPS Desactivado',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
                ),
              ),
            ],
          ),
          content: const Text(
            'El sensor de ubicación de tu teléfono está apagado. Enciéndelo para que REstelar pueda fijar tu posición en el mapa y guiar tu ruta.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text(
                'Cancelar',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.secondaryCyan,
              ),
              onPressed: () async {
                Navigator.of(ctx).pop();
                await Geolocator.openLocationSettings();
              },
              child: const Text(
                'Abrir Ajustes GPS',
                style: TextStyle(color: Colors.black),
              ),
            ),
          ],
        ),
      );
      return false;
    }

    // 2. Comprobar estado de permiso en el sistema operativo
    final currentPermission = await locationService.checkPermission();
    if (currentPermission == LocationPermissionResult.granted) {
      return true;
    }

    if (currentPermission == LocationPermissionResult.deniedForever) {
      if (!context.mounted) return false;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.backgroundCard,
          title: const Row(
            children: [
              Icon(Icons.block_rounded, color: AppColors.error),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Permiso Denegado en el Sistema',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
                ),
              ),
            ],
          ),
          content: const Text(
            'El acceso a la ubicación fue denegado permanentemente. Para poder trazar rutas y guiarte en carretera, actívalo en los Ajustes de REstelar.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text(
                'Cancelar',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryGold,
              ),
              onPressed: () async {
                Navigator.of(ctx).pop();
                await Geolocator.openAppSettings();
              },
              child: const Text(
                'Abrir Ajustes de la App',
                style: TextStyle(color: Colors.black),
              ),
            ),
          ],
        ),
      );
      return false;
    }

    // 3. Explicar contexto al usuario antes de llamar a la ventana nativa de Android
    if (!context.mounted) return false;
    final userAcceptedExplanation = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundCard,
        title: const Row(
          children: [
            Icon(Icons.my_location_rounded, color: AppColors.secondaryCyan),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Permiso de Ubicación Precisa',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
              ),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'REstelar necesita acceso a tu ubicación precisa para:',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '• Trazar la ruta vial desde tu posición exacta.\n'
              '• Calcular tu velocidad en tiempo real.\n'
              '• Emitir indicaciones de voz y calcular giros antes de cada cruce.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'REstelar no comparte tu ubicación con terceros ni la almacena en servidores externos.',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Ahora no',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.secondaryCyan,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Continuar',
              style: TextStyle(color: Colors.black),
            ),
          ),
        ],
      ),
    );

    if (userAcceptedExplanation != true) return false;

    // 4. Solicitar permiso nativo al sistema operativo
    final requestResult = await locationService.requestPermission();
    return requestResult == LocationPermissionResult.granted;
  }

  /// Comprueba y solicita el permiso de notificaciones (Android 13+ / API 33+)
  /// para que la navegación en segundo plano mantenga el servicio persistente.
  static Future<void> ensureNotificationPermission() async {
    if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    try {
      final status = await Permission.notification.status;
      if (!status.isGranted && !status.isPermanentlyDenied) {
        await Permission.notification.request();
      }
    } catch (_) {}
  }
}
