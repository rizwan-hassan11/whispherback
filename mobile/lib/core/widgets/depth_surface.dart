import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radii.dart';

/// Layered shadows and highlights for a subtle 3D look.
abstract final class AppDepth {
  static const perspective = 900.0;
  static const lift = 8.0;

  static List<BoxShadow> shadows({
    required bool isDark,
    double intensity = 1,
    bool elevated = false,
  }) {
    final a = intensity;
    if (isDark) {
      return [
        BoxShadow(
          color: Colors.white.withValues(alpha: 0.06 * a),
          offset: const Offset(0, 1),
          blurRadius: 0,
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: (elevated ? 0.38 : 0.28) * a),
          offset: Offset(0, elevated ? 14 : 8),
          blurRadius: elevated ? 32 : 22,
          spreadRadius: elevated ? -2 : -4,
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.18 * a),
          offset: Offset(0, elevated ? 28 : 18),
          blurRadius: elevated ? 48 : 36,
          spreadRadius: -8,
        ),
      ];
    }
    return [
      BoxShadow(
        color: const Color(0xFF061331).withValues(alpha: 0.04 * a),
        offset: const Offset(0, 1),
        blurRadius: 0,
      ),
      BoxShadow(
        color: const Color(0xFF061331)
            .withValues(alpha: (elevated ? 0.12 : 0.08) * a),
        offset: Offset(0, elevated ? 12 : 8),
        blurRadius: elevated ? 28 : 20,
        spreadRadius: -2,
      ),
      BoxShadow(
        color: const Color(0xFF061331).withValues(alpha: 0.05 * a),
        offset: Offset(0, elevated ? 24 : 16),
        blurRadius: elevated ? 40 : 32,
        spreadRadius: -6,
      ),
    ];
  }

  static BoxDecoration surface({
    required bool isDark,
    double radius = AppRadii.sm,
    Color? borderColor,
    bool elevated = false,
    double intensity = 1,
  }) =>
      BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  const Color(0x1FFFFFFF),
                  const Color(0x0DFFFFFF),
                  const Color(0x08000000),
                ]
              : [
                  Colors.white,
                  const Color(0xFFF8FAFC),
                  const Color(0xFFEEF2F7),
                ],
          stops: const [0, 0.55, 1],
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: borderColor ??
              (isDark ? const Color(0x33FFFFFF) : AppColors.lightGlassBorder),
        ),
        boxShadow:
            shadows(isDark: isDark, intensity: intensity, elevated: elevated),
      );

  static BoxDecoration iconTile({required bool isDark, double radius = 10}) =>
      BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [AppColors.cardElevated, AppColors.ink, const Color(0xFF040B1E)]
              : [
                  AppColors.lightBg2,
                  AppColors.lightBg,
                  const Color(0xFFE2E8F0)
                ],
          stops: const [0, 0.6, 1],
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: isDark ? const Color(0x28FFFFFF) : AppColors.lightGlassBorder,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
            offset: const Offset(0, 4),
            blurRadius: 8,
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.9),
            offset: const Offset(0, -1),
            blurRadius: 0,
          ),
        ],
      );
}

/// Perspective wrapper for nested 3D transforms.
class DepthScene extends StatelessWidget {
  const DepthScene({
    super.key,
    required this.child,
    this.perspective = AppDepth.perspective,
    this.alignment = Alignment.center,
  });

  final Widget child;
  final double perspective;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Transform(
      alignment: alignment,
      transform: Matrix4.identity()..setEntry(3, 2, 0.0012),
      child: child,
    );
  }
}

/// Card-like surface with layered depth shadows and a specular highlight.
class DepthSurface extends StatelessWidget {
  const DepthSurface({
    super.key,
    required this.child,
    this.radius = AppRadii.sm,
    this.padding,
    this.elevated = false,
    this.intensity = 1,
    this.borderColor,
    this.tiltX = 0,
    this.tiltY = 0,
    this.lift = 0,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final bool elevated;
  final double intensity;
  final Color? borderColor;
  final double tiltX;
  final double tiltY;
  final double lift;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.001)
        ..rotateX(tiltX)
        ..rotateY(tiltY)
        // ignore: deprecated_member_use
        ..translate(0.0, 0.0, lift),
      child: DecoratedBox(
        decoration: AppDepth.surface(
          isDark: isDark,
          radius: radius,
          elevated: elevated,
          intensity: intensity,
          borderColor: borderColor,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: isDark ? 0.10 : 0.55),
                        Colors.transparent,
                        Colors.black.withValues(alpha: isDark ? 0.10 : 0.03),
                      ],
                      stops: const [0, 0.45, 1],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: padding ?? EdgeInsets.zero,
                child: child,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tappable depth tile — presses down with a 3D squash.
class DepthTile extends StatefulWidget {
  const DepthTile({
    super.key,
    required this.child,
    this.onTap,
    this.radius = AppRadii.sm,
    this.padding,
    this.elevated = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final bool elevated;

  @override
  State<DepthTile> createState() => _DepthTileState();
}

class _DepthTileState extends State<DepthTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown:
          widget.onTap != null ? (_) => setState(() => _pressed = true) : null,
      onTapUp:
          widget.onTap != null ? (_) => setState(() => _pressed = false) : null,
      onTapCancel:
          widget.onTap != null ? () => setState(() => _pressed = false) : null,
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: DepthSurface(
          radius: widget.radius,
          padding: widget.padding,
          elevated: widget.elevated,
          tiltX: _pressed ? 0.04 : 0.02,
          lift: _pressed ? 0 : AppDepth.lift,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Soft floating sphere for ambient 3D decoration.
class DepthOrb extends StatelessWidget {
  const DepthOrb({
    super.key,
    required this.size,
    required this.color,
    this.top,
    this.left,
    this.right,
    this.bottom,
    this.blur = 0,
  });

  final double size;
  final Color color;
  final double? top;
  final double? left;
  final double? right;
  final double? bottom;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Dark theme: bright, luminous orbs. Light theme: keep them subtle so the
    // dark accent colors don't turn into heavy blobs on a pale background.
    final coreAlpha = isDark ? 0.9 : 0.42;
    final midAlpha = isDark ? 0.4 : 0.16;
    final shadowAlpha = isDark ? 0.3 : 0.14;

    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(-0.35, -0.35),
            radius: 0.9,
            colors: [
              color.withValues(alpha: coreAlpha),
              color.withValues(alpha: midAlpha),
              color.withValues(alpha: 0),
            ],
            stops: const [0, 0.5, 1],
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: shadowAlpha),
              blurRadius: blur > 0 ? blur : size * 0.4,
              spreadRadius: size * 0.02,
            ),
          ],
        ),
      ),
    );
  }
}

/// Elliptical pedestal shadow beneath circular controls (power button).
class DepthPedestal extends StatelessWidget {
  const DepthPedestal({
    super.key,
    this.width = 168,
    this.height = 22,
  });

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.001)
        ..rotateX(1.2),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: RadialGradient(
            colors: [
              (isDark ? Colors.white : AppColors.ink)
                  .withValues(alpha: isDark ? 0.10 : 0.08),
              Colors.transparent,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.55 : 0.12),
              blurRadius: 24,
              spreadRadius: 4,
            ),
          ],
        ),
      ),
    );
  }
}
