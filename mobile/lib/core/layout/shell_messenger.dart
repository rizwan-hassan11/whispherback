import 'package:flutter/material.dart';

import 'responsive.dart';

/// Root [ScaffoldMessenger] key so snackbars survive route pops & sit above
/// the floating bottom navigation bar.
final GlobalKey<ScaffoldMessengerState> rootMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Snackbars and toasts that float above the shell bottom navigation bar.
extension ShellMessenger on BuildContext {
  void showShellSnackBar(
    String message, {
    SnackBarAction? action,
    Duration duration = const Duration(seconds: 3),
    IconData? icon,
  }) {
    final bottom =
        ShellMetrics.reservedBottomHeight(this, miniPlayerVisible: false) + 12;
    final messenger = rootMessengerKey.currentState ?? ScaffoldMessenger.of(this);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: Colors.white),
                const SizedBox(width: 10),
              ],
              Expanded(child: Text(message)),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(16, 0, 16, bottom),
          duration: duration,
          showCloseIcon: true,
          action: action,
        ),
      );
  }
}
