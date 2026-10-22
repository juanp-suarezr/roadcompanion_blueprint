import '../../../../domain/entities/coordinates.dart';
import 'access_restriction.dart';

/// Tipo de problema vial reportado en ruta por el motociclista.
enum NavigationIssueType {
  /// Acceso privado, cerrojo o portón cerrado con candado.
  lockedGate,

  /// Giro incorrecto, sentido vial invertido o maniobra prohibida.
  wrongTurn,

  /// Destino final inaccesible por falta de calzada o bloqueo físico.
  inaccessibleDestination,

  /// Vía destapada inesperada, trocha o afirmado no apto.
  unexpectedUnpaved,

  /// Vía en mal estado, baches severos o deslizamiento.
  badRoadCondition,

  /// Otro problema vial con comentario explicativo.
  other,
}

/// Estado de confirmación de un reporte vial en la memoria inteligente.
enum ReportVerificationStatus {
  /// Confirmado por el usuario: influye como restricción activa en cálculos de ruta.
  confirmed,

  /// Pendiente de verificación: genera advertencia de precaución sin bloquear arbitrariamente.
  unconfirmed,

  /// Descartado o resuelto por el usuario: no afecta el enrutamiento.
  dismissed,
}

/// Representa un reporte vial persistente registrado por el motociclista.
class NavigationIssueReport {
  final String id;
  final Coordinates location;
  final NavigationIssueType type;
  final String? roadSegment;
  final String description;
  final DateTime reportedAt;
  final String source;
  final ReportVerificationStatus status;

  const NavigationIssueReport({
    required this.id,
    required this.location,
    required this.type,
    this.roadSegment,
    required this.description,
    required this.reportedAt,
    this.source = 'Reporte del motociclista',
    this.status = ReportVerificationStatus.confirmed,
  });

  String get typeLabel {
    switch (type) {
      case NavigationIssueType.lockedGate:
        return 'Portón cerrado / Vía privada';
      case NavigationIssueType.wrongTurn:
        return 'Giro incorrecto o prohibido';
      case NavigationIssueType.inaccessibleDestination:
        return 'Destino inaccesible';
      case NavigationIssueType.unexpectedUnpaved:
        return 'Vía destapada inesperada';
      case NavigationIssueType.badRoadCondition:
        return 'Vía en mal estado / baches';
      case NavigationIssueType.other:
        return 'Otro reporte vial';
    }
  }

  /// Convierte el reporte en un registro de restricción de acceso si está confirmado y bloquea el paso.
  AccessRestrictionRecord? toRestrictionRecord() {
    if (status != ReportVerificationStatus.confirmed) {
      return null;
    }

    if (type == NavigationIssueType.lockedGate ||
        type == NavigationIssueType.inaccessibleDestination) {
      return AccessRestrictionRecord(
        id: 'user_report_$id',
        location: location,
        radiusMeters: 35.0,
        type: AccessRestrictionType.lockedGate,
        description: description.isNotEmpty
            ? description
            : 'Paso bloqueado por $typeLabel',
        sourceEvidence:
            '$source (${reportedAt.year}-${reportedAt.month.toString().padLeft(2, '0')}-${reportedAt.day.toString().padLeft(2, '0')})',
      );
    }

    return null;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'location': {
      'latitude': location.latitude,
      'longitude': location.longitude,
    },
    'type': type.name,
    'roadSegment': roadSegment,
    'description': description,
    'reportedAt': reportedAt.toIso8601String(),
    'source': source,
    'status': status.name,
  };

  factory NavigationIssueReport.fromJson(Map<String, dynamic> json) {
    final locMap = json['location'] as Map<String, dynamic>;

    NavigationIssueType parseType(String? val) {
      return NavigationIssueType.values.firstWhere(
        (t) => t.name == val,
        orElse: () => NavigationIssueType.other,
      );
    }

    ReportVerificationStatus parseStatus(String? val) {
      return ReportVerificationStatus.values.firstWhere(
        (s) => s.name == val,
        orElse: () => ReportVerificationStatus.unconfirmed,
      );
    }

    return NavigationIssueReport(
      id: json['id'] as String,
      location: Coordinates(
        (locMap['latitude'] as num).toDouble(),
        (locMap['longitude'] as num).toDouble(),
      ),
      type: parseType(json['type'] as String?),
      roadSegment: json['roadSegment'] as String?,
      description: json['description'] as String? ?? '',
      reportedAt:
          DateTime.tryParse(json['reportedAt'] as String? ?? '') ??
          DateTime.now(),
      source: json['source'] as String? ?? 'Reporte del motociclista',
      status: parseStatus(json['status'] as String?),
    );
  }

  NavigationIssueReport copyWith({
    ReportVerificationStatus? status,
    String? description,
    String? roadSegment,
  }) {
    return NavigationIssueReport(
      id: id,
      location: location,
      type: type,
      roadSegment: roadSegment ?? this.roadSegment,
      description: description ?? this.description,
      reportedAt: reportedAt,
      source: source,
      status: status ?? this.status,
    );
  }
}
