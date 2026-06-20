import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/widgets/permission_required_dialog.dart';
import '../../core/layout/shell_messenger.dart';
import '../../l10n/app_localizations.dart';
import 'android_runtime_permissions.dart';

enum PermissionPromptOutcome { granted, denied, permanentlyDenied }

/// Which app capability needs a runtime permission.
enum AppPermissionKind {
  microphone,
  location,
  notifications,
  exactAlarms,
  batteryOptimization,
  audioImport,
}

class PermissionCopy {
  const PermissionCopy({
    required this.title,
    required this.body,
    required this.settingsPath,
    this.deniedSnack,
  });

  final String title;
  final String body;
  final String settingsPath;
  final String? deniedSnack;
}

PermissionCopy permissionCopy(AppLocalizations l10n, AppPermissionKind kind) {
  switch (kind) {
    case AppPermissionKind.microphone:
      return PermissionCopy(
        title: l10n.permissionMicrophoneTitle,
        body: l10n.permissionMicrophoneBody,
        settingsPath: l10n.permissionMicrophoneSettingsPath,
        deniedSnack: l10n.micPermissionSnack,
      );
    case AppPermissionKind.location:
      return PermissionCopy(
        title: l10n.permissionLocationTitle,
        body: l10n.permissionLocationBody,
        settingsPath: l10n.permissionLocationSettingsPath,
        deniedSnack: l10n.permissionLocationDeniedSnack,
      );
    case AppPermissionKind.notifications:
      return PermissionCopy(
        title: l10n.permissionNotificationsTitle,
        body: l10n.permissionNotificationsBody,
        settingsPath: l10n.permissionNotificationsSettingsPath,
        deniedSnack: l10n.permissionNotificationsDeniedSnack,
      );
    case AppPermissionKind.exactAlarms:
      return PermissionCopy(
        title: l10n.permissionExactAlarmsTitle,
        body: l10n.permissionExactAlarmsBody,
        settingsPath: l10n.permissionExactAlarmsSettingsPath,
        deniedSnack: l10n.permissionExactAlarmsDeniedSnack,
      );
    case AppPermissionKind.batteryOptimization:
      return PermissionCopy(
        title: l10n.permissionBatteryTitle,
        body: l10n.permissionBatteryBody,
        settingsPath: l10n.permissionBatterySettingsPath,
        deniedSnack: l10n.permissionBatteryDeniedSnack,
      );
    case AppPermissionKind.audioImport:
      return PermissionCopy(
        title: l10n.permissionAudioTitle,
        body: l10n.permissionAudioBody,
        settingsPath: l10n.permissionAudioSettingsPath,
        deniedSnack: l10n.permissionAudioDeniedSnack,
      );
  }
}

Future<PermissionPromptOutcome> requestHandlerPermission(
  Permission permission,
) async {
  var status = await permission.status;
  if (status.isGranted || status.isLimited) {
    return PermissionPromptOutcome.granted;
  }

  status = await permission.request();
  if (status.isGranted || status.isLimited) {
    return PermissionPromptOutcome.granted;
  }
  if (status.isPermanentlyDenied) {
    return PermissionPromptOutcome.permanentlyDenied;
  }
  return PermissionPromptOutcome.denied;
}

Future<PermissionPromptOutcome> requestLocationPermission() async {
  if (!Platform.isAndroid && !Platform.isIOS) {
    return PermissionPromptOutcome.granted;
  }

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.always ||
      permission == LocationPermission.whileInUse) {
    return PermissionPromptOutcome.granted;
  }
  if (permission == LocationPermission.deniedForever) {
    return PermissionPromptOutcome.permanentlyDenied;
  }

  permission = await Geolocator.requestPermission();
  if (permission == LocationPermission.always ||
      permission == LocationPermission.whileInUse) {
    return PermissionPromptOutcome.granted;
  }
  if (permission == LocationPermission.deniedForever) {
    return PermissionPromptOutcome.permanentlyDenied;
  }
  return PermissionPromptOutcome.denied;
}

Permission? permissionForKind(AppPermissionKind kind) {
  switch (kind) {
    case AppPermissionKind.microphone:
      return Permission.microphone;
    case AppPermissionKind.notifications:
      return Permission.notification;
    case AppPermissionKind.exactAlarms:
      return Permission.scheduleExactAlarm;
    case AppPermissionKind.batteryOptimization:
      return Permission.ignoreBatteryOptimizations;
    case AppPermissionKind.audioImport:
      if (!Platform.isAndroid) return null;
      return Permission.audio;
    case AppPermissionKind.location:
      return null;
  }
}

Future<PermissionPromptOutcome> requestAppPermissionKind(
  AppPermissionKind kind,
) async {
  if (kind == AppPermissionKind.location) {
    return requestLocationPermission();
  }

  final permission = permissionForKind(kind);
  if (permission == null) return PermissionPromptOutcome.granted;
  return requestHandlerPermission(permission);
}

/// Requests permission and guides the user when it is blocked.
///
/// Returns `true` when the permission is granted. On first denial, shows a
/// snackbar so the user can try again (Android will re-show the system prompt).
/// On permanent denial, shows a dialog with **Open Settings**.
Future<bool> ensurePermissionWithUi(
  BuildContext context, {
  required AppPermissionKind kind,
}) async {
  final l10n = context.l10n;
  final copy = permissionCopy(l10n, kind);
  final outcome = await requestAppPermissionKind(kind);

  if (outcome == PermissionPromptOutcome.granted) return true;
  if (!context.mounted) return false;

  if (outcome == PermissionPromptOutcome.permanentlyDenied) {
    final openSettings = await showPermissionRequiredDialog(
      context,
      title: copy.title,
      body: copy.body,
      settingsPath: copy.settingsPath,
      openSettingsLabel: l10n.permissionOpenSettings,
      notNowLabel: l10n.permissionNotNow,
    );
    if (openSettings) await openAppSettings();
    return false;
  }

  final snack = copy.deniedSnack ?? l10n.permissionDeniedSnack;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(snack),
      action: SnackBarAction(
        label: l10n.permissionOpenSettings,
        onPressed: () => openAppSettings(),
      ),
    ),
  );
  return false;
}

/// After turning Active ON, explain any missing scheduling permissions.
Future<void> promptMissingSchedulingPermissions(
  BuildContext context,
  AndroidSchedulingPermissions permissions,
) async {
  if (permissions.fullyReady) return;

  final l10n = context.l10n;
  final missing = <String>[];
  if (!permissions.notificationsGranted) {
    missing.add(l10n.permissionNotificationsShort);
  }
  if (!permissions.exactAlarmsGranted) {
    missing.add(l10n.permissionExactAlarmsShort);
  }
  if (!permissions.batteryUnrestricted) {
    missing.add(l10n.permissionBatteryShort);
  }
  if (missing.isEmpty || !context.mounted) return;

  final openSettings = await showPermissionRequiredDialog(
    context,
    title: l10n.schedulingPermissionsTitle,
    body: l10n.schedulingPermissionsBody(missing.join('\n• ')),
    settingsPath: l10n.schedulingPermissionsSettingsPath,
    openSettingsLabel: l10n.permissionOpenSettings,
    notNowLabel: l10n.permissionNotNow,
  );
  if (openSettings) await openAppSettings();
}

/// Guided setup when the user turns **Active ON**.
///
/// Uses Android system dialogs first (2–3 taps, stay in the app). Opens Settings
/// only if something is still blocked afterward.
Future<void> runSchedulingSetupWizard(BuildContext context) async {
  if (!Platform.isAndroid) return;

  final l10n = context.l10n;

  context.showShellSnackBar(
    l10n.schedulingSetupIntro,
    duration: const Duration(seconds: 4),
  );

  await requestAppPermissionKind(AppPermissionKind.notifications);
  await requestAppPermissionKind(AppPermissionKind.exactAlarms);
  await requestBatteryExemption();

  if (!context.mounted) return;

  var perms = await ensureAndroidSchedulingPermissions();

  if (!perms.notificationsGranted && context.mounted) {
    await ensurePermissionWithUi(
      context,
      kind: AppPermissionKind.notifications,
    );
  }
  if (!context.mounted) return;

  perms = await ensureAndroidSchedulingPermissions();
  if (!perms.exactAlarmsGranted && context.mounted) {
    await ensurePermissionWithUi(context, kind: AppPermissionKind.exactAlarms);
  }
  if (!context.mounted) return;

  perms = await ensureAndroidSchedulingPermissions();
  if (!perms.batteryUnrestricted && context.mounted) {
    await ensurePermissionWithUi(
      context,
      kind: AppPermissionKind.batteryOptimization,
    );
  }

  if (!context.mounted) return;
  perms = await ensureAndroidSchedulingPermissions();

  if (perms.fullyReady) {
    context.showShellSnackBar(l10n.schedulingSetupComplete);
    return;
  }

  await promptMissingSchedulingPermissions(context, perms);
}

/// Checks whether background scheduling has everything it needs.
Future<bool> isSchedulingFullyReady() async {
  final perms = await ensureAndroidSchedulingPermissions();
  return perms.fullyReady;
}
