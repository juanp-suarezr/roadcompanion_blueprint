/// Biblioteca principal de dominio para Road Companion.
///
/// Contiene las entidades esenciales de navegación, maniobras y cálculo de rutas.
library;

export 'domain/entities/coordinates.dart';
export 'domain/entities/maneuver.dart';
export 'domain/entities/maneuver_type.dart';
export 'domain/entities/route_plan.dart';
export 'domain/entities/route_progress.dart';
export 'domain/services/route_progress_calculator.dart';
export 'features/navigation/domain/entities/gps_position.dart';
export 'features/navigation/domain/entities/gpx_point.dart';
export 'features/navigation/domain/entities/gpx_segment.dart';
export 'features/navigation/domain/entities/gpx_tracking_status.dart';
export 'features/navigation/domain/entities/imported_gpx_route.dart';
export 'features/navigation/domain/entities/navigation_session.dart';
export 'features/navigation/domain/entities/saved_route_metadata.dart';
export 'features/navigation/domain/repositories/gpx_route_repository.dart';
export 'features/navigation/domain/repositories/session_repository.dart';
export 'features/navigation/domain/services/location_service.dart';
export 'features/navigation/infrastructure/parsers/gpx_parser.dart';
export 'features/navigation/infrastructure/repositories/local_gpx_route_repository.dart';
export 'features/navigation/infrastructure/repositories/local_session_repository.dart';
export 'features/navigation/infrastructure/services/geolocator_location_service.dart';
export 'features/navigation/infrastructure/services/gpx_file_picker.dart';
export 'features/navigation/infrastructure/services/gpx_import_service.dart';
export 'features/navigation/presentation/state/gpx_route_tracker.dart';
export 'features/navigation/presentation/state/imported_route_state.dart';
export 'app/road_companion_app.dart';
export 'app/state/app_settings_service.dart';
export 'app/state/app_settings_state.dart';
export 'app/theme/app_colors.dart';
export 'app/theme/app_theme.dart';
export 'app/theme/app_typography.dart';
export 'core/widgets/estela_logo.dart';
