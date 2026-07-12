import 'package:flutter/services.dart';

/// Light haptic on primary taps (play, nav, favourite).
void tapHaptic() {
  HapticFeedback.lightImpact();
}

/// Softer tick for secondary icon actions.
void selectionHaptic() {
  HapticFeedback.selectionClick();
}
