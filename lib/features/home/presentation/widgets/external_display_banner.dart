import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';

/// Banner informativo sobre el estado del pod o pantalla externa de navegación.
///
/// Comunica de forma transparente que la integración de hardware externo está en desarrollo
/// sin realizar búsquedas Bluetooth ni solicitar permisos innecesarios.
class ExternalDisplayBanner extends StatelessWidget {
  final VoidCallback? onTap;

  const ExternalDisplayBanner({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceVariant.withValues(alpha: 0.5)
            : AppColors.lightSurfaceVariant,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: isDark ? const Color(0xFF263A48) : const Color(0xFFD7DFE8),
          width: 1.0,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: isDark ? AppColors.stormNavy : Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.bluetooth_disabled,
              size: 18.0,
              color: isDark ? AppColors.silver : AppColors.secondaryTextLight,
            ),
          ),
          const SizedBox(width: 12.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      'Pantalla externa: ',
                      style: TextStyle(
                        fontSize: 13.0,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      'No conectada',
                      style: TextStyle(
                        fontSize: 13.0,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppColors.silver
                            : AppColors.secondaryTextLight,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2.0),
                Text(
                  'Integración con pods de manillar en desarrollo.',
                  style: TextStyle(
                    fontSize: 12.0,
                    color: isDark
                        ? AppColors.secondaryTextDark
                        : AppColors.secondaryTextLight,
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null)
            IconButton(
              icon: const Icon(Icons.info_outline, size: 20.0),
              color: isDark ? AppColors.silver : AppColors.secondaryTextLight,
              tooltip: 'Más información',
              onPressed: onTap,
            ),
        ],
      ),
    );
  }
}
