import 'package:flutter/material.dart';

/// Jerarquía tipográfica especializada para Road Companion.
///
/// Diseñada para maximizar la legibilidad rápida a distancia visual de conducción
/// («at-a-glance readability») con números sobredimensionados y pesos consistentes.
abstract class AppTypography {
  // --- Estilos para Métricas de Conducción y Odometría ---
  /// Números de maniobra y distancia principal (40sp, negrita, espacio condensado).
  static const TextStyle maneuverDistance = TextStyle(
    fontSize: 40.0,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.0,
    height: 1.1,
  );

  /// Unidad de medida adyacente a la distancia (18sp, semi-negrita).
  static const TextStyle maneuverUnit = TextStyle(
    fontSize: 18.0,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5,
  );

  /// Porcentaje de progreso de ruta (32sp, negrita).
  static const TextStyle progressPercentage = TextStyle(
    fontSize: 32.0,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
  );

  /// Nombre de vía principal de la siguiente maniobra (22sp, semi-negrita).
  static const TextStyle roadName = TextStyle(
    fontSize: 22.0,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.15,
    height: 1.25,
  );

  /// Texto descriptivo de la maniobra (16sp, regular).
  static const TextStyle instructionText = TextStyle(
    fontSize: 16.0,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
    height: 1.3,
  );

  // --- Títulos y Encabezados ---
  /// Título de la aplicación en el encabezado (26sp, negrita con carácter clásico).
  static const TextStyle appTitle = TextStyle(
    fontSize: 26.0,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.5,
  );

  /// Eslogan de la aplicación (13sp, espacio extendido sobrio).
  static const TextStyle appSlogan = TextStyle(
    fontSize: 13.0,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.5,
  );

  /// Título de sección en tarjetas (18sp, semi-negrita).
  static const TextStyle sectionTitle = TextStyle(
    fontSize: 18.0,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.1,
  );

  /// Etiquetas de badges y estados (12sp, negrita en mayúsculas).
  static const TextStyle badgeLabel = TextStyle(
    fontSize: 12.0,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.2,
  );
}
