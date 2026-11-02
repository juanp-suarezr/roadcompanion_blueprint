import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../services/app_build_info_service.dart';

/// Indicador sutil y sobrio de la fecha/hora de compilación y modo del APK.
class AppBuildInfoWidget extends StatelessWidget {
  final TextAlign textAlign;
  final double fontSize;

  const AppBuildInfoWidget({
    super.key,
    this.textAlign = TextAlign.center,
    this.fontSize = 11.0,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark
        ? AppColors.secondaryTextDark
        : AppColors.secondaryTextLight;

    return FutureBuilder<AppBuildInfo>(
      future: AppBuildInfoService.getBuildInfo(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final info = snapshot.data!;
        final displayText = info.formatDisplay();

        return Text(
          displayText,
          textAlign: textAlign,
          style: TextStyle(
            fontSize: fontSize,
            color: textColor.withValues(alpha: 0.75),
            fontWeight: FontWeight.w400,
            letterSpacing: 0.3,
          ),
        );
      },
    );
  }
}
