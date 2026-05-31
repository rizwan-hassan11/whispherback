import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

String formatPlaylistDurationLocalized(BuildContext context, int totalMs) {
  final l10n = AppLocalizations.ofOrThrow(context);
  if (totalMs <= 0) return l10n.zeroSec;
  final sec = totalMs ~/ 1000;
  if (sec < 60) return l10n.durationSec(sec);
  final min = sec ~/ 60;
  final rem = sec % 60;
  if (rem == 0) return l10n.durationMin(min);
  return l10n.durationMinSec(min, rem);
}
