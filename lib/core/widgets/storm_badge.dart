import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';

enum StormBadgeVariant { success, info, warning, neutral }

/// Etiqueta visual de estado sobria y de alta visibilidad para motociclistas.
class StormBadge extends StatelessWidget {
  final String label;
  final IconData? icon;
  final StormBadgeVariant variant;

  const StormBadge({
    super.key,
    required this.label,
    this.icon,
    this.variant = StormBadgeVariant.info,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color bg;
    Color fg;
    Color border;

    switch (variant) {
      case StormBadgeVariant.success:
        bg = isDark
            ? AppColors.success.withValues(alpha: 0.18)
            : AppColors.success.withValues(alpha: 0.12);
        fg = isDark ? const Color(0xFF6AE69A) : const Color(0xFF1B8A48);
        border = isDark
            ? AppColors.success.withValues(alpha: 0.40)
            : AppColors.success.withValues(alpha: 0.30);
        break;
      case StormBadgeVariant.info:
        bg = isDark
            ? AppColors.accentBlue.withValues(alpha: 0.18)
            : AppColors.steelBlue.withValues(alpha: 0.12);
        fg = isDark ? AppColors.accentBlue : AppColors.deepBlue;
        border = isDark
            ? AppColors.accentBlue.withValues(alpha: 0.40)
            : AppColors.steelBlue.withValues(alpha: 0.30);
        break;
      case StormBadgeVariant.warning:
        bg = isDark
            ? AppColors.warning.withValues(alpha: 0.18)
            : AppColors.warning.withValues(alpha: 0.12);
        fg = isDark ? const Color(0xFFFFCC66) : const Color(0xFFB37400);
        border = isDark
            ? AppColors.warning.withValues(alpha: 0.45)
            : AppColors.warning.withValues(alpha: 0.35);
        break;
      case StormBadgeVariant.neutral:
        bg = isDark
            ? AppColors.silver.withValues(alpha: 0.12)
            : const Color(0xFFE2E8F0);
        fg = isDark
            ? AppColors.secondaryTextDark
            : AppColors.secondaryTextLight;
        border = isDark
            ? AppColors.silver.withValues(alpha: 0.25)
            : const Color(0xFFCBD5E1);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: border, width: 1.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14.0, color: fg),
            const SizedBox(width: 5.0),
          ],
          Text(
            label.toUpperCase(),
            style: AppTypography.badgeLabel.copyWith(color: fg),
          ),
        ],
      ),
    );
  }
}
