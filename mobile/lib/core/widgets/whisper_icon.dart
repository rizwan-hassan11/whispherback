import 'package:flutter/material.dart';

/// App icon with consistent Lucide sizing and color.
class WhisperIcon extends StatelessWidget {
  const WhisperIcon(
    this.icon, {
    super.key,
    this.size = 20,
    this.color,
    this.semanticLabel,
  });

  final IconData icon;
  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final themeColor = IconTheme.of(context).color;
    return Icon(
      icon,
      size: size,
      color: color ?? themeColor,
      semanticLabel: semanticLabel,
    );
  }
}
