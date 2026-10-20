/// Tipos de maniobra normalizados para el sistema de navegación.
///
/// Si un proveedor de rutas entrega una instrucción no mapeable con certeza,
/// debe emplearse [ManeuverType.unknown] en conformidad con las reglas de desarrollo.
enum ManeuverType {
  straight,
  slightLeft,
  left,
  sharpLeft,
  slightRight,
  right,
  sharpRight,
  uTurn,
  roundabout,
  depart,
  arrive,
  unknown;

  /// Convierte una cadena de texto proveniente de un proveedor a un [ManeuverType].
  ///
  /// Si el valor es nulo, vacío o no reconocido, retorna de forma segura [ManeuverType.unknown].
  static ManeuverType fromString(String? value) {
    if (value == null) return ManeuverType.unknown;

    final normalized = value
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');

    switch (normalized) {
      case 'straight':
      case 'continue':
        return ManeuverType.straight;
      case 'slight_left':
      case 'turn_slight_left':
        return ManeuverType.slightLeft;
      case 'left':
      case 'turn_left':
        return ManeuverType.left;
      case 'sharp_left':
      case 'turn_sharp_left':
        return ManeuverType.sharpLeft;
      case 'slight_right':
      case 'turn_slight_right':
        return ManeuverType.slightRight;
      case 'right':
      case 'turn_right':
        return ManeuverType.right;
      case 'sharp_right':
      case 'turn_sharp_right':
        return ManeuverType.sharpRight;
      case 'u_turn':
      case 'uturn':
        return ManeuverType.uTurn;
      case 'roundabout':
      case 'rotary':
        return ManeuverType.roundabout;
      case 'depart':
      case 'start':
        return ManeuverType.depart;
      case 'arrive':
      case 'destination':
        return ManeuverType.arrive;
      default:
        return ManeuverType.unknown;
    }
  }
}
