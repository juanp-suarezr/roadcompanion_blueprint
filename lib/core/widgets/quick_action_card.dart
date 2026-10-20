import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';

/// Tarjeta de acceso rápido con área táctil cómoda para motociclistas.
class QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailingBadge;

  const QuickActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailingBadge,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16.0),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
          child: Row(
            children: [
              // Icono con contenedor estilizado
              Container(
                width: 48.0,
                height: 48.0,
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkSurfaceVariant
                      : AppColors.lightSurfaceVariant,
                  borderRadius: BorderRadius.circular(12.0),
                  border: Border.all(
                    color: isDark
                        ? AppColors.deepBlue
                        : const Color(0xFFD7DFE8),
                    width: 1.0,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 26.0,
                  color: isDark ? AppColors.accentBlue : AppColors.deepBlue,
                ),
              ),
              const SizedBox(width: 14.0),

              // Textos
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: AppTypography.sectionTitle.copyWith(
                              color: theme.colorScheme.onSurface,
                              fontSize: 16.0,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (trailingBadge != null) ...[
                          const SizedBox(width: 8.0),
                          trailingBadge!,
                        ],
                      ],
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13.0,
                        color: isDark
                            ? AppColors.secondaryTextDark
                            : AppColors.secondaryTextLight,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Flecha de navegación
              Icon(
                Icons.chevron_right,
                size: 24.0,
                color: isDark
                    ? AppColors.secondaryTextDark.withValues(alpha: 0.6)
                    : AppColors.secondaryTextLight.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
