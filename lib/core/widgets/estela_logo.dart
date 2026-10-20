import 'dart:math';
import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';

/// Variantes de presentación del logotipo oficial de ESTELA.
enum EstelaLogoVariant {
  /// Emblema geométrico aislado (icono).
  emblem,

  /// Emblema + Nombre ESTELA + Descriptor (vertical centrado).
  full,

  /// Emblema + Nombre ESTELA (horizontal compacto).
  compact,
}

/// Logotipo oficial y emblema reutilizable de ESTELA.
///
/// Dibuja vectorialmente mediante [CustomPainter] la flecha aerodinámica ascendente,
/// la órbita astronómica/brújula y los trazos dinámicos de estela, sin recurrir a dependencias externas.
class EstelaLogo extends StatelessWidget {
  final double size;
  final EstelaLogoVariant variant;
  final bool isMonochrome;
  final Color? customColor;
  final bool showDescriptor;

  const EstelaLogo({
    super.key,
    this.size = 48.0,
    this.variant = EstelaLogoVariant.emblem,
    this.isMonochrome = false,
    this.customColor,
    this.showDescriptor = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final emblem = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _EstelaLogoPainter(
          isMonochrome: isMonochrome,
          customColor: customColor,
          isDark: isDark,
        ),
      ),
    );

    switch (variant) {
      case EstelaLogoVariant.emblem:
        return emblem;

      case EstelaLogoVariant.compact:
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            emblem,
            const SizedBox(width: 10.0),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'ESTELA',
                  style: TextStyle(
                    fontSize: size * 0.42,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.0,
                    color:
                        customColor ??
                        (isDark
                            ? AppColors.coldWhite
                            : AppColors.primaryTextLight),
                    height: 1.0,
                  ),
                ),
                if (showDescriptor) ...[
                  const SizedBox(height: 2.0),
                  Text(
                    'NAVEGADOR COMPLEMENTARIO',
                    style: TextStyle(
                      fontSize: (size * 0.16).clamp(8.0, 11.0),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                      color: isDark
                          ? AppColors.cyanLuminous
                          : AppColors.electricBlue,
                      height: 1.0,
                    ),
                  ),
                ],
              ],
            ),
          ],
        );

      case EstelaLogoVariant.full:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            emblem,
            const SizedBox(height: 14.0),
            Text(
              'ESTELA',
              style: TextStyle(
                fontSize: 28.0,
                fontWeight: FontWeight.w900,
                letterSpacing: 4.5,
                color:
                    customColor ??
                    (isDark ? AppColors.coldWhite : AppColors.primaryTextLight),
              ),
            ),
            if (showDescriptor) ...[
              const SizedBox(height: 4.0),
              Text(
                'NAVEGADOR DE RUTA COMPLEMENTARIO',
                style: AppTypography.badgeLabel.copyWith(
                  fontSize: 10.5,
                  letterSpacing: 2.0,
                  color: isDark
                      ? AppColors.cyanLuminous
                      : AppColors.electricBlue,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        );
    }
  }
}

class _EstelaLogoPainter extends CustomPainter {
  final bool isMonochrome;
  final Color? customColor;
  final bool isDark;

  _EstelaLogoPainter({
    required this.isMonochrome,
    this.customColor,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width / 2.0;
    final double cy = size.height / 2.0;
    final double r = min(size.width, size.height) / 2.0;

    final Color primaryColor = isMonochrome
        ? (customColor ?? (isDark ? Colors.white : Colors.black87))
        : AppColors.cyanLuminous;

    final Color secondaryColor = isMonochrome
        ? (customColor ?? (isDark ? Colors.white70 : Colors.black54))
        : AppColors.electricBlue;

    // 1. Órbita circular / brújula estilizada exterior con inclinación
    final orbitPaint = Paint()
      ..color = secondaryColor.withValues(alpha: isMonochrome ? 0.35 : 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.5, r * 0.08)
      ..strokeCap = StrokeCap.round;

    final orbitRect = Rect.fromCenter(
      center: Offset(cx, cy + (r * 0.05)),
      width: r * 1.65,
      height: r * 1.65,
    );

    // Arco superior de 220 grados simulando órbita y anillo de brújula
    canvas.drawArc(orbitRect, -pi * 0.95, pi * 1.35, false, orbitPaint);

    // Punto estelar de la órbita (cardinal norte / satélite)
    final orbitDotPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;
    final double dotX = cx + (r * 0.825 * cos(-pi * 0.95));
    final double dotY = (cy + (r * 0.05)) + (r * 0.825 * sin(-pi * 0.95));
    canvas.drawCircle(Offset(dotX, dotY), max(1.8, r * 0.07), orbitDotPaint);

    // 2. Trazos de movimiento de la «Estela» (wake lines detrás del vértice)
    final wakePaint = Paint()
      ..color = primaryColor.withValues(alpha: isMonochrome ? 0.25 : 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.2, r * 0.06)
      ..strokeCap = StrokeCap.round;

    // Trazo de estela 1 (inferior izquierda)
    final wakePath1 = Path();
    wakePath1.moveTo(cx - (r * 0.22), cy + (r * 0.40));
    wakePath1.quadraticBezierTo(
      cx - (r * 0.35),
      cy + (r * 0.60),
      cx - (r * 0.50),
      cy + (r * 0.72),
    );
    canvas.drawPath(wakePath1, wakePaint);

    // Trazo de estela 2 (inferior derecha)
    final wakePath2 = Path();
    wakePath2.moveTo(cx + (r * 0.22), cy + (r * 0.40));
    wakePath2.quadraticBezierTo(
      cx + (r * 0.35),
      cy + (r * 0.60),
      cx + (r * 0.50),
      cy + (r * 0.72),
    );
    canvas.drawPath(wakePath2, wakePaint);

    // 3. Flecha de navegación central facetada en dos mitades (efecto metálico 3D)
    final double tipY = cy - (r * 0.75);
    final double wingY = cy + (r * 0.35);
    final double innerY = cy + (r * 0.10);
    final double wingSpan = r * 0.52;

    // Faceta izquierda (Cian Luminoso - reflexiva)
    final leftFacetPath = Path();
    leftFacetPath.moveTo(cx, tipY);
    leftFacetPath.lineTo(cx - wingSpan, wingY);
    leftFacetPath.lineTo(cx, innerY);
    leftFacetPath.close();

    final leftFacetPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(leftFacetPath, leftFacetPaint);

    // Faceta derecha (Azul Eléctrico / sombra metálica)
    final rightFacetPath = Path();
    rightFacetPath.moveTo(cx, tipY);
    rightFacetPath.lineTo(cx + wingSpan, wingY);
    rightFacetPath.lineTo(cx, innerY);
    rightFacetPath.close();

    final rightFacetPaint = Paint()
      ..color = secondaryColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(rightFacetPath, rightFacetPaint);

    // Nervadura central de precisión
    final spinePaint = Paint()
      ..color = isDark ? Colors.white.withValues(alpha: 0.8) : Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.0, r * 0.04);
    canvas.drawLine(Offset(cx, tipY), Offset(cx, innerY), spinePaint);
  }

  @override
  bool shouldRepaint(covariant _EstelaLogoPainter oldDelegate) {
    return oldDelegate.isMonochrome != isMonochrome ||
        oldDelegate.customColor != customColor ||
        oldDelegate.isDark != isDark;
  }
}
