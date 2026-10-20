import 'package:flutter/material.dart';

/// Ilustración vectorial personalizada de carretera y horizonte montañoso.
///
/// Dibuja mediante [CustomPainter] una composición sobria y clásica de carretera
/// que se extiende hacia el horizonte, sin depender de imágenes externas o marcas comerciales.
class CustomRoadArt extends StatelessWidget {
  final double height;
  final double width;

  const CustomRoadArt({
    super.key,
    this.height = 130.0,
    this.width = double.infinity,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: height,
      width: width,
      child: CustomPaint(
        painter: _RoadArtPainter(
          isDark: isDark,
          primaryColor: colorScheme.primary,
          secondaryColor: colorScheme.secondary,
          surfaceVariant: colorScheme.surfaceContainerHighest,
        ),
      ),
    );
  }
}

class _RoadArtPainter extends CustomPainter {
  final bool isDark;
  final Color primaryColor;
  final Color secondaryColor;
  final Color surfaceVariant;

  _RoadArtPainter({
    required this.isDark,
    required this.primaryColor,
    required this.secondaryColor,
    required this.surfaceVariant,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. Silueta de montañas lejanas en el horizonte
    final mountainPaint = Paint()
      ..color = isDark
          ? primaryColor.withValues(alpha: 0.18)
          : primaryColor.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;

    final mountainPath = Path()
      ..moveTo(0, h * 0.55)
      ..lineTo(w * 0.20, h * 0.35)
      ..lineTo(w * 0.35, h * 0.48)
      ..lineTo(w * 0.55, h * 0.28)
      ..lineTo(w * 0.72, h * 0.45)
      ..lineTo(w * 0.88, h * 0.32)
      ..lineTo(w, h * 0.50)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    canvas.drawPath(mountainPath, mountainPaint);

    // 2. Línea de horizonte sutil
    final horizonPaint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.15)
          : primaryColor.withValues(alpha: 0.20)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(0, h * 0.55), Offset(w, h * 0.55), horizonPaint);

    // 3. Calzada en perspectiva (carretera de curvas suaves)
    final roadPaint = Paint()
      ..color = isDark
          ? const Color(0xFF141F28)
          : surfaceVariant.withValues(alpha: 0.95)
      ..style = PaintingStyle.fill;

    final roadBorderPaint = Paint()
      ..color = isDark
          ? primaryColor.withValues(alpha: 0.45)
          : secondaryColor.withValues(alpha: 0.50)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final roadPath = Path()
      ..moveTo(w * 0.15, h)
      ..quadraticBezierTo(w * 0.42, h * 0.75, w * 0.48, h * 0.55)
      ..lineTo(w * 0.52, h * 0.55)
      ..quadraticBezierTo(w * 0.58, h * 0.75, w * 0.85, h)
      ..close();

    canvas.drawPath(roadPath, roadPaint);
    canvas.drawPath(roadPath, roadBorderPaint);

    // 4. Líneas discontinuas del centro de la calzada
    final dashPaint = Paint()
      ..color = isDark
          ? primaryColor.withValues(alpha: 0.90)
          : secondaryColor.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.5;

    // Segmentos discontinuos con perspectiva
    canvas.drawLine(
      Offset(w * 0.50, h * 0.58),
      Offset(w * 0.50, h * 0.63),
      dashPaint,
    );
    dashPaint.strokeWidth = 3.5;
    canvas.drawLine(
      Offset(w * 0.50, h * 0.70),
      Offset(w * 0.50, h * 0.78),
      dashPaint,
    );
    dashPaint.strokeWidth = 5.0;
    canvas.drawLine(
      Offset(w * 0.50, h * 0.85),
      Offset(w * 0.50, h * 0.98),
      dashPaint,
    );

    // 5. Pequeño sol naciente / brújula de horizonte
    final sunPaint = Paint()
      ..color = isDark
          ? primaryColor.withValues(alpha: 0.25)
          : secondaryColor.withValues(alpha: 0.20)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w * 0.50, h * 0.38), 16.0, sunPaint);
  }

  @override
  bool shouldRepaint(covariant _RoadArtPainter oldDelegate) {
    return oldDelegate.isDark != isDark ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.secondaryColor != secondaryColor ||
        oldDelegate.surfaceVariant != surfaceVariant;
  }
}
