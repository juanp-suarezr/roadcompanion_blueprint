/// Estados del ciclo de vida del seguimiento GPS de una ruta GPX.
enum GpxTrackingStatus {
  /// Seguimiento inactivo / en espera.
  idle,

  /// Solicitando permisos y esperando la primera lectura satelital.
  searchingGps,

  /// Señal satelital recibida pero con precisión horizontal insuficiente (ruido alto).
  lowAccuracy,

  /// Navegación activa: siguiendo la ruta dentro del umbral de tolerancia.
  tracking,

  /// Fuera de ruta: el motociclista se ha apartado del trazado más allá del umbral.
  offRoute,

  /// Señal satelital interrumpida o sin nuevas lecturas recientes.
  gpsLost,

  /// Seguimiento pausado temporalmente por el usuario.
  paused,

  /// Ruta completada al aproximarse al destino final con avance suficiente.
  completed,

  /// Seguimiento finalizado o detenido por el usuario.
  stopped,
}
