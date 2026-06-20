import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Pops the route stack when possible; otherwise navigates to [fallback].
void popOrGo(BuildContext context, String fallback) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallback);
  }
}

/// Handles Android predictive back and toolbar back consistently.
class RouteBackScope extends StatelessWidget {
  const RouteBackScope({
    super.key,
    required this.fallbackLocation,
    required this.child,
  });

  final String fallbackLocation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: context.canPop(),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        context.go(fallbackLocation);
      },
      child: child,
    );
  }
}
