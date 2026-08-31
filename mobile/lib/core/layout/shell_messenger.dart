import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Root [ScaffoldMessenger] key so snackbars survive route pops & sit above
/// the floating bottom navigation bar.
final GlobalKey<ScaffoldMessengerState> rootMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Resolves a context that's safe to read Theme from when the calling
/// context may already be unmounted after a `pop()`.
BuildContext _resolveMessengerContext(BuildContext fallback) {
  final state = rootMessengerKey.currentState;
  final ctx = state?.context;
  if (ctx != null && ctx.mounted) return ctx;
  return fallback;
}

/// Oceanic floating toasts that sit just above the shell bottom chrome.
///
/// Safe to call right after `context.pop()` — the snackbar is enqueued on the
/// root [ScaffoldMessenger] so it survives the route transition.
///
/// Placement: Scaffold already parks floating snackbars above
/// [Scaffold.bottomNavigationBar]. We only add a thin 8px gap — previously
/// stacking a full chrome-height margin on top of that inset pushed
/// toasts toward the middle of the screen.
extension ShellMessenger on BuildContext {
  void showShellSnackBar(
    String message, {
    SnackBarAction? action,
    Duration duration = const Duration(milliseconds: 2800),
    IconData? icon,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final messenger = rootMessengerKey.currentState;
      if (messenger == null) return;
      final ctx = _resolveMessengerContext(this);

      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      final bg = isDark ? AppColors.cardElevated : AppColors.deep;
      const fg = Colors.white;
      const accent = AppColors.neonCyan;

      final styledAction = action == null
          ? null
          : SnackBarAction(
              label: action.label,
              textColor: accent,
              onPressed: action.onPressed,
            );

      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            backgroundColor: bg,
            elevation: 16,
            dismissDirection: DismissDirection.down,
            content: DefaultTextStyle.merge(
              style: const TextStyle(
                color: fg,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: accent),
                    const SizedBox(width: 10),
                  ],
                  Expanded(child: Text(message, style: const TextStyle(color: fg))),
                ],
              ),
            ),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: accent.withValues(alpha: isDark ? 0.35 : 0.45),
              ),
            ),
            duration: duration,
            showCloseIcon: true,
            closeIconColor: fg.withValues(alpha: 0.9),
            action: styledAction,
          ),
        );
    });
  }
}
