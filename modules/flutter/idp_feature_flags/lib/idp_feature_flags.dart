/// Vendor-neutral feature flags for IDP-bootstrapped Flutter apps.
///
/// The app depends on this package only. Backends arrive as separate packages
/// implementing [FlagSource] — see `idp_feature_flags_firebase` (Remote Config)
/// and `idp_feature_flags_appconfig` (AWS AppConfig).
library;

export 'src/feature_flags.dart';
export 'src/flag.dart';
export 'src/resolution.dart';
export 'src/source.dart';
