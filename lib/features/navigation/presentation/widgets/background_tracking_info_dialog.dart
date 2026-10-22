import 'package:flutter/material.dart';
import '../../../../app/theme/app_colors.dart';

/// Diálogo informativo y transparente sobre el seguimiento GPS en segundo plano.
///
/// Explica qué datos se recolectan, dónde se almacenan, cómo detener el servicio
/// y las limitaciones de batería impuestas por los fabricantes de Android.
class BackgroundTrackingInfoDialog extends StatelessWidget {
  const BackgroundTrackingInfoDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => const BackgroundTrackingInfoDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.backgroundCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      title: Row(
        children: [
          const Icon(
            Icons.satellite_alt_rounded,
            color: AppColors.primaryGold,
            size: 24,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Navegación en Segundo Plano',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Para mantener el seguimiento activo cuando apagues la pantalla o cambies de aplicación, REstelar utiliza un servicio en primer plano de Android.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            _buildInfoItem(
              icon: Icons.security_rounded,
              title: '¿Qué datos se registran?',
              body:
                  'Coordenadas satelitales, velocidad estimada, rumbo y precisión GPS durante la sesión de ruta activa.',
            ),
            const SizedBox(height: 10),
            _buildInfoItem(
              icon: Icons.folder_special_rounded,
              title: '¿Dónde se guardan?',
              body:
                  'Exclusivamente en el almacenamiento privado de tu teléfono. No se envían a servidores externos ni a terceros sin tu orden.',
            ),
            const SizedBox(height: 10),
            _buildInfoItem(
              icon: Icons.stop_circle_outlined,
              title: '¿Cómo detenerlo?',
              body:
                  'En cualquier instante mediante el botón "Detener" en la notificación persistente o desde el botón rojo de navegación.',
            ),
            const SizedBox(height: 10),
            _buildInfoItem(
              icon: Icons.battery_alert_rounded,
              title: 'Ahorro de batería y fabricantes',
              body:
                  'Si tu teléfono (Xiaomi, Samsung, Huawei, etc.) cierra la app al bloquearse, desactiva la "Optimización de batería" para REstelar en Ajustes.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(
            'Solo en primer plano',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryGold,
            foregroundColor: AppColors.backgroundBlack,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(
            'Entendido y activar',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.primaryGold),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$title\n',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    height: 1.3,
                  ),
                ),
                TextSpan(
                  text: body,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
