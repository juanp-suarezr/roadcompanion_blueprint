/// Categorías funcionales de paradas en un itinerario de viaje en REstelar.
enum TripStopType {
  /// Parada o punto de paso seleccionado libremente en el mapa.
  custom(displayName: 'Punto en el mapa'),

  /// Estación de servicio o gasolinera.
  fuel(displayName: 'Gasolinera'),

  /// Restaurante, cafetería o punto de alimentación.
  restaurant(displayName: 'Restaurante / Café'),

  /// Taller mecánico o montallantas especializado en motocicletas.
  motorcycleWorkshop(displayName: 'Taller de motos'),

  /// Mirador, paisaje de interés o punto panorámico en carretera.
  viewpoint(displayName: 'Mirador'),

  /// Barbería o peluquería.
  hairdresser(displayName: 'Barbería / Peluquería'),

  /// Hotel, hostal o lugar de hospedaje.
  lodging(displayName: 'Hospedaje'),

  /// Otro punto de interés o servicio general.
  other(displayName: 'Punto de interés');

  final String displayName;

  const TripStopType({required this.displayName});
}
