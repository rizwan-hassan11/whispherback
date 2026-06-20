import 'package:flutter/material.dart';

import 'responsive.dart';

/// Snackbars and toasts that float above the shell bottom navigation bar.
extension ShellMessenger on BuildContext {
  void showShellSnackBar(
    String message, {
    SnackBarAction? action,
    Duration duration = const Duration(seconds: 4),
  }) {
    final bottom =
        ShellMetrics.reservedBottomHeight(this, miniPlayerVisible: false) + 12;
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(16, 0, 16, bottom),
        duration: duration,
        showCloseIcon: true,
        action: action,
      ),
    );
  }
}
