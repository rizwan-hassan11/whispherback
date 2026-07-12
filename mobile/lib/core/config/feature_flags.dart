/// Product feature toggles.
///
/// Flip a flag here to re-enable a shelved feature without re-wiring
/// every call site. All gates are compile-time constants so dead code
/// is tree-shaken in release builds.
library;

/// Adhan (call-to-prayer audio + prayer-time notifications + prayer pause).
///
/// Disabled for the current client release: QA reported adhan firing on
/// fresh install / download and overriding silent mode. The code paths
/// remain in the tree behind this flag for a future re-enable once
/// acceptance criteria are defined.
const bool kAdhanFeatureEnabled = false;
