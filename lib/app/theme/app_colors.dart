import 'package:flutter/material.dart';

/// Paleta cromática oficial de ESTELA — Navegador de ruta complementario.
///
/// Diseñada con una dirección visual nocturna, tecnológica, minimalista y de alto contraste
/// para motociclistas, combinando azul noche, superficies marinas profundas y acentos en cian luminoso.
abstract class AppColors {
  // --- Paleta Principal ESTELA ---
  /// Azul noche (#071827) — Fondo principal inmersivo en modo oscuro.
  static const Color nightBlue = Color(0xFF071827);
  static const Color stormNavy = nightBlue; // alias de compatibilidad

  /// Azul marino de superficie (#10283B) — Barras de navegación, app bars y contenedores.
  static const Color surfaceNavy = Color(0xFF10283B);
  static const Color deepBlue = surfaceNavy; // alias de compatibilidad

  /// Azul de tarjeta (#183449) — Paneles elevados y tarjetas principales.
  static const Color cardNavy = Color(0xFF183449);
  static const Color darkSurface = cardNavy; // alias de compatibilidad

  /// Azul de contenedor elevado (#21445F) — Estados interactivos y variantes oscuras.
  static const Color darkSurfaceVariant = Color(0xFF21445F);

  /// Cian luminoso (#35D6F2) — Emblema luminoso de ESTELA, acentos activos y progreso.
  static const Color cyanLuminous = Color(0xFF35D6F2);
  static const Color accentBlue = cyanLuminous; // alias de compatibilidad

  /// Azul eléctrico (#58AFFF) — Trazados de ruta, enlaces y énfasis secundario.
  static const Color electricBlue = Color(0xFF58AFFF);
  static const Color steelBlue = electricBlue; // alias de compatibilidad

  /// Blanco frío (#F4F8FC) — Texto primario de máxima legibilidad nocturna.
  static const Color coldWhite = Color(0xFFF4F8FC);
  static const Color primaryTextDark = coldWhite; // alias de compatibilidad

  /// Texto secundario (#AABAC9) — Subtítulos, metadatos y unidades.
  static const Color secondaryText = Color(0xFFAABAC9);
  static const Color secondaryTextDark = secondaryText; // alias de compatibilidad

  /// Plata / Metal (#C8D0D8) — Acentos sutiles y divisores.
  static const Color silver = Color(0xFFC8D0D8);

  // --- Superficies y Fondos Modo Claro ---
  /// Fondo general claro (#F4F7FB) — Suave, minimiza reflejos.
  static const Color lightBackground = Color(0xFFF4F7FB);

  /// Superficie blanca (#FFFFFF) — Tarjetas y componentes elevados en modo claro.
  static const Color whiteSurface = Color(0xFFFFFFFF);

  /// Superficie elevada clara (#E8EEF5) — Contenedores secundarios claros.
  static const Color lightSurfaceVariant = Color(0xFFE8EEF5);

  /// Texto primario claro (#0A1A28) — Máximo contraste en modo diurno.
  static const Color primaryTextLight = Color(0xFF0A1A28);

  /// Texto secundario claro (#55697D) — Datos complementarios diurnos.
  static const Color secondaryTextLight = Color(0xFF55697D);

  // --- Estados y Señalización Vial ESTELA ---
  /// Verde de estado correcto (#55D99A) — GPS activo, ruta completada, destino alcanzado.
  static const Color success = Color(0xFF55D99A);

  /// Rojo de alerta (#FF626C) — Peligro, desconexión crítica o parada de emergencia.
  static const Color error = Color(0xFFFF626C);

  /// Ámbar de advertencia (#FFC66D) — Precaución vial, desvío de ruta, precisión reducida.
  static const Color warning = Color(0xFFFFC66D);

  /// Info / Identificador (#35D6F2) — Etiquetas informativas y badges.
  static const Color info = cyanLuminous;

  /// Inactivo / Desconectado (#6C8296) — Estado inactivo o pendiente.
  static const Color inactive = Color(0xFF6C8296);
}
