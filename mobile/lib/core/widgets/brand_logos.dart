import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Official multicolor Google "G" mark.
class GoogleLogo extends StatelessWidget {
  const GoogleLogo({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/icons/google.svg',
      width: size,
      height: size,
    );
  }
}

/// Apple logo silhouette — uses [color] or current foreground.
class AppleLogo extends StatelessWidget {
  const AppleLogo({super.key, this.size = 18, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? Theme.of(context).colorScheme.onSurface;
    return SvgPicture.asset(
      'assets/icons/apple.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(fg, BlendMode.srcIn),
    );
  }
}

/// WhisperBack soundwave brand mark (oceanic logo).
///
/// Prefers the crisp SVG mark; falls back to the PNG launcher asset.
class WhisperBackLogo extends StatelessWidget {
  const WhisperBackLogo({super.key, this.size = 96, this.borderRadius});

  final double size;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(size * 0.22);
    return ClipRRect(
      borderRadius: radius,
      child: SvgPicture.asset(
        'assets/branding/logo_mark.svg',
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholderBuilder: (_) => Image.asset(
          'assets/branding/app_logo.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}
