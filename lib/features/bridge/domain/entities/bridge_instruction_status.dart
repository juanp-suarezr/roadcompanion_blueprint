/// Estado de validez y completitud de una instrucción procesada por ESTELA Bridge.
///
/// Permite discriminar de forma determinista entre datos listos para el Tripper Pod,
/// indicaciones truncadas o ambiguas, y textos ajenos a maniobras viales.
enum BridgeInstructionStatus {
  /// La maniobra y sus parámetros esenciales fueron reconocidos con certeza.
  recognized,

  /// Se identificó contexto de navegación (ej. distancia o indicación parcial)
  /// pero la maniobra es ambigua o incompleta. No debe transmitirse al hardware.
  incomplete,

  /// El texto recibido no corresponde a una maniobra vial reconocible
  /// (ej. alertas de tráfico, recálculo, bienvenida o notificaciones no orientadas a giro).
  /// Bajo ninguna circunstancia debe forzarse como giro recto por defecto.
  unrecognized,

  /// La instrucción era válida pero ha superado el umbral temporal de frescura
  /// y se considera desactualizada.
  stale,
}
