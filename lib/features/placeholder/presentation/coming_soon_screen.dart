import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/widgets/storm_badge.dart';

/// Pantalla informativa honesta para funcionalidades en desarrollo.
///
/// Evita botones o estados simulados que aparenten operar cuando todavía no están listos.
class ComingSoonScreen extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;

  const ComingSoonScreen({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Contenedor de icono
                Container(
                  width: 80.0,
                  height: 80.0,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkSurfaceVariant
                        : AppColors.lightSurfaceVariant,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark ? AppColors.deepBlue : AppColors.steelBlue,
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    icon,
                    size: 40.0,
                    color: isDark ? AppColors.accentBlue : AppColors.deepBlue,
                  ),
                ),
                const SizedBox(height: 24.0),

                const StormBadge(
                  label: 'Próximamente',
                  variant: StormBadgeVariant.info,
                ),
                const SizedBox(height: 16.0),

                Text(
                  title,
                  style: AppTypography.appTitle.copyWith(
                    fontSize: 22.0,
                    color: theme.colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8.0),

                Text(
                  description,
                  style: TextStyle(
                    fontSize: 15.0,
                    color: isDark
                        ? AppColors.secondaryTextDark
                        : AppColors.secondaryTextLight,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32.0),

                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Volver al inicio'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
