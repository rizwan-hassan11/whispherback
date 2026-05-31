import 'package:flutter/widgets.dart';

import '../domain/entities/playback_schedule.dart';
import 'app_localizations.dart';

extension PlaybackScheduleL10n on PlaybackSchedule {
  String daysLabelL10n(BuildContext context) {
    return AppLocalizations.ofOrThrow(context).daysLabelFromMask(daysMask);
  }

  String intervalLabelL10n(BuildContext context) {
    return AppLocalizations.ofOrThrow(context).intervalLabel(intervalMinutes);
  }
}
