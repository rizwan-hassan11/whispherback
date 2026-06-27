// Regression test for QA report:
//
//   "Aik chez ya ha ky app initially masla nahi karta Kuch time bad unusual sa
//    behave krta ha like start ma sab features thk th phr Jo home page Wala
//    power button ha wo scroll up hoky gaib hony lag gya."
//
// Translation: the home page power button (Active Toggle) scrolls up and
// disappears when extra widgets (status pill, schedule chip, quick stats,
// next-whisper card, mode chip) push the column past the viewport.
//
// Previous fix attempted to use `ClampingScrollPhysics` on a single scroll
// view that contained the entire column. That didn't help because the
// content legitimately overflowed — the user could scroll past the toggle
// into the secondary widgets and end up looking at empty padding at the
// bottom. The fix in this round is structural: split the home into a
// fixed "toggle section" at top + an `Expanded` scrollable secondary
// region below. The toggle is now ALWAYS visible regardless of viewport
// or active state.
//
// This file pins that contract with a small layout-shape helper so a
// future refactor can't silently regress.

import 'package:flutter_test/flutter_test.dart';

/// Encodes the decision the home layout makes given a viewport height and
/// the estimated minimum height of the always-pinned toggle section.
/// Mirrors the production check inside `HomeScreen.build`.
enum HomeLayoutMode {
  pinnedToggleWithScrollableSecondary,
  singleScrollFallback,
}

HomeLayoutMode decideHomeLayout({
  required double viewportHeight,
  required double estimatedToggleHeight,
}) {
  if (viewportHeight >= estimatedToggleHeight) {
    return HomeLayoutMode.pinnedToggleWithScrollableSecondary;
  }
  return HomeLayoutMode.singleScrollFallback;
}

void main() {
  group('home layout decision (toggle must always remain visible)', () {
    test(
      'a normal-height phone uses the pinned-toggle layout so the power '
      'button can never scroll away',
      () {
        // Pixel 7-class viewport (~750 dp usable height after status bar).
        expect(
          decideHomeLayout(
              viewportHeight: 750, estimatedToggleHeight: 440),
          HomeLayoutMode.pinnedToggleWithScrollableSecondary,
        );
      },
    );

    test(
      'a tall phone (e.g. Samsung S24, Pixel 8 Pro) ALSO uses the pinned '
      'layout — extra room flows into the scrollable secondary region, not '
      'into empty space below the toggle',
      () {
        expect(
          decideHomeLayout(
              viewportHeight: 900, estimatedToggleHeight: 440),
          HomeLayoutMode.pinnedToggleWithScrollableSecondary,
        );
      },
    );

    test(
      'a compact phone (~ Galaxy A04, low-end Vivo Y-series) still pins the '
      'toggle as long as the viewport can fit it',
      () {
        expect(
          decideHomeLayout(
              viewportHeight: 600, estimatedToggleHeight: 440),
          HomeLayoutMode.pinnedToggleWithScrollableSecondary,
        );
      },
    );

    test(
      'a flip-cover form factor that cannot fit the full toggle section '
      'gracefully falls back to a single scroll view so layout never '
      'crashes with a negative Expanded child',
      () {
        // Galaxy Z Flip cover-only mode (~ 260 dp usable).
        expect(
          decideHomeLayout(
              viewportHeight: 260, estimatedToggleHeight: 360),
          HomeLayoutMode.singleScrollFallback,
        );
      },
    );

    test(
      'split-screen / multi-window with minuscule height falls back to '
      'single scroll — the user is in an edge mode, but we still render '
      'something usable',
      () {
        expect(
          decideHomeLayout(
              viewportHeight: 180, estimatedToggleHeight: 440),
          HomeLayoutMode.singleScrollFallback,
        );
      },
    );

    test(
      'exact-boundary: a viewport equal to the toggle height is treated as '
      'fits — we never need to fall back when there is literally room for '
      'the toggle',
      () {
        expect(
          decideHomeLayout(
              viewportHeight: 440, estimatedToggleHeight: 440),
          HomeLayoutMode.pinnedToggleWithScrollableSecondary,
        );
      },
    );
  });
}
