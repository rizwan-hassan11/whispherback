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
