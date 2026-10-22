import '../../../../domain/entities/coordinates.dart';

/// Tipo de restricción de acceso vehicular o bloqueo físico en la vía.
enum AccessRestrictionType {
  /// Portón con candado, cerrojo o barrera física infranqueable (barrier=gate/lift_gate).
  lockedGate,

  /// Vía de propiedad privada o acceso cerrado al público (access=private, access=no).
  privateAccess,

  /// Restricción vehicular explícita (motor_vehicle=no, vehicle=no).
  motorVehicleRestricted,

  /// Calzada con transitabilidad no confirmada o información cartográfica insuficiente.
  unconfirmedTransitability,
}

/// Registro documentado de una restricción de acceso vial o portón privado.
class AccessRestrictionRecord {
  /// Identificador único del registro.
  final String id;

  /// Coordenada geográfica exacta del punto de restricción o portón.
  final Coordinates location;

  /// Radio de influencia en metros para detectar trazados que intenten cruzarlo.
  final double radiusMeters;

  /// Tipo de restricción.
  final AccessRestrictionType type;

  /// Descripción legible de la restricción y el sector afectado.
  final String description;

  /// Fuente de verificación (ej. etiquetas OSM, inspección de campo, reporte vial verificado).
  final String sourceEvidence;

  /// ID de la vía OSM asociada si se conoce.
  final int? wayId;

  /// ID del nodo barrera OSM asociado si se conoce.
  final int? nodeId;

  const AccessRestrictionRecord({
    required this.id,
    required this.location,
    this.radiusMeters = 30.0,
    required this.type,
    required this.description,
    required this.sourceEvidence,
    this.wayId,
    this.nodeId,
  });

  /// Comprueba si una coordenada geográfica cae dentro del radio de influencia de la restricción.
  bool containsCoordinate(Coordinates point) {
    return location.distanceTo(point) <= radiusMeters;
  }

  /// Comprueba si alguno de los nodos OSM de la ruta coincide con el nodo barrera documentado.
  bool containsNodeId(int id) {
    return nodeId != null && nodeId == id;
  }
}

/// Registro territorial de restricciones de acceso vial, portones privados y pasos cerrados.
///
/// Proporciona una solución arquitectónica reutilizable y extensible a nivel nacional/regional,
/// evitando condiciones hardcodeadas aisladas.
class RoadAccessRestrictionRegistry {
  final List<AccessRestrictionRecord> _records = [];

  RoadAccessRestrictionRegistry({
    List<AccessRestrictionRecord>? initialRecords,
  }) {
    if (initialRecords != null) {
      _records.addAll(initialRecords);
    } else {
      _registerDefaultKnownRestrictions();
    }
  }

  /// Carga las restricciones verificadas en cartografía y en campo para el área de cobertura.
  void _registerDefaultKnownRestrictions() {
    // 1. Caso documentado y verificado en campo y cartografía OSM:
    // Barrio Guadalupe, Dosquebradas, Risaralda.
    // Vía de servicio Way 1011620142 conectada a Avenida Simón Bolívar con portón cerrado y candado.
    // Nodos OSM 9337280309 y 9337280308 (barrier=gate).
    addRecord(
      AccessRestrictionRecord(
        id: 'dosquebradas_guadalupe_calle35_gate',
        location: Coordinates(4.833360, -75.672461),
        radiusMeters: 30.0,
        type: AccessRestrictionType.lockedGate,
        description:
            'Portón privado con candado en callejón de servicio a Barrio Guadalupe (Way OSM 1011620142)',
        sourceEvidence:
            'OSM Nodes 9337280309/9337280308 (barrier=gate) y verificación de campo comunitaria',
        wayId: 1011620142,
        nodeId: 9337280309,
      ),
    );
  }

  void addRecord(AccessRestrictionRecord record) {
    if (!_records.any((r) => r.id == record.id)) {
      _records.add(record);
    }
  }

  List<AccessRestrictionRecord> get allRecords => List.unmodifiable(_records);

  /// Verifica si una geometría vial o lista de nodos OSM atraviesa alguna restricción documentada.
  AccessRestrictionRecord? findRestrictionAlongPath(
    List<Coordinates> geometry, {
    List<int>? nodeIds,
  }) {
    // 1. Comprobación rápida por IDs de nodos OSM si están disponibles en la respuesta de OSRM
    if (nodeIds != null && nodeIds.isNotEmpty) {
      final nodeSet = nodeIds.toSet();
      for (final record in _records) {
        if (record.nodeId != null && nodeSet.contains(record.nodeId)) {
          return record;
        }
      }
    }

    // 2. Comprobación espacial geodésica sobre los puntos de la geometría
    for (final record in _records) {
      for (final pt in geometry) {
        if (record.containsCoordinate(pt)) {
          return record;
        }
      }
    }

    return null;
  }
}
