/// Biblioteca principal de dominio para ESTELA — Navegador de ruta complementario.
///
/// Contiene las entidades esenciales de navegación, maniobras, cartografía y cálculo de rutas.
library;

export 'domain/entities/coordinates.dart';
export 'domain/entities/maneuver.dart';
export 'domain/entities/maneuver_type.dart';
export 'domain/entities/route_plan.dart';
export 'domain/entities/route_progress.dart';
export 'domain/services/route_progress_calculator.dart';
export 'features/navigation/domain/entities/calculated_route.dart';
export 'features/navigation/domain/entities/destination.dart';
export 'features/navigation/domain/entities/gps_position.dart';
export 'features/navigation/domain/entities/gpx_point.dart';
export 'features/navigation/domain/entities/gpx_segment.dart';
export 'features/navigation/domain/entities/gpx_tracking_status.dart';
export 'features/navigation/domain/entities/imported_gpx_route.dart';
export 'features/navigation/domain/entities/navigation_session.dart';
export 'features/navigation/domain/entities/saved_route_metadata.dart';
export 'features/navigation/domain/repositories/gpx_route_repository.dart';
export 'features/navigation/domain/repositories/session_repository.dart';
export 'features/navigation/domain/services/geocoding_service.dart';
export 'features/navigation/domain/services/location_service.dart';
export 'features/navigation/domain/services/routing_service.dart';
export 'features/navigation/infrastructure/parsers/gpx_parser.dart';
export 'features/navigation/infrastructure/repositories/local_gpx_route_repository.dart';
export 'features/navigation/infrastructure/repositories/local_session_repository.dart';
export 'features/navigation/infrastructure/services/geolocator_location_service.dart';
export 'features/navigation/infrastructure/services/gpx_file_picker.dart';
export 'features/navigation/infrastructure/services/gpx_import_service.dart';
export 'features/navigation/infrastructure/services/nominatim_geocoding_service.dart';
export 'features/navigation/infrastructure/services/osrm_routing_service.dart';
export 'features/navigation/presentation/state/gpx_route_tracker.dart';
export 'features/navigation/presentation/state/imported_route_state.dart';
export 'features/navigation/presentation/widgets/active_turn_by_turn_hud.dart';
export 'features/navigation/presentation/widgets/destination_search_sheet.dart';
export 'features/navigation/presentation/widgets/real_map_widget.dart';
export 'features/navigation/presentation/widgets/route_overview_card.dart';
export 'app/road_companion_app.dart';
export 'app/state/app_settings_service.dart';
export 'app/state/app_settings_state.dart';
export 'app/theme/app_colors.dart';
export 'app/theme/app_theme.dart';
export 'app/theme/app_typography.dart';
export 'core/widgets/estela_logo.dart';
