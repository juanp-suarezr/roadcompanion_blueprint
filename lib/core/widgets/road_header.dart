import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';
import 'estela_logo.dart';

/// Encabezado principal de la aplicación REstelar.
///
/// Presenta el emblema luminoso oficial, el nombre REstelar, el descriptor/eslogan
/// y acceso táctil a Ajustes.
class RoadHeader extends StatelessWidget {
  final VoidCallback onSettingsTap;
  final Widget? trailing;

  const RoadHeader({super.key, required this.onSettingsTap, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Emblema oficial de REstelar (flecha aerodinámica ascendente y órbita)
          const EstelaLogo(size: 42.0, variant: EstelaLogoVariant.emblem),
          const SizedBox(width: 14.0),

          // Título y descriptor de REstelar
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      'REstelar',
                      style: AppTypography.appTitle.copyWith(
                        color: theme.colorScheme.onSurface,
                        letterSpacing: 2.0,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 1.0),
                Text(
                  'NAVEGADOR DE RUTA COMPLEMENTARIO',
                  style: AppTypography.appSlogan.copyWith(
                    fontSize: 9.5,
                    letterSpacing: 1.2,
                    color: isDark
                        ? AppColors.cyanLuminous
                        : AppColors.electricBlue,
                  ),
                ),
              ],
            ),
          ),

          // Acceso a Ajustes con área táctil cómoda (mínimo 48x48)
          trailing ??
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                iconSize: 26.0,
                color: theme.colorScheme.onSurface,
                tooltip: 'Ajustes de la aplicación',
                padding: const EdgeInsets.all(12.0),
                constraints: const BoxConstraints(
                  minWidth: 48.0,
                  minHeight: 48.0,
                ),
                onPressed: onSettingsTap,
              ),
        ],
      ),
    );
  }
}
