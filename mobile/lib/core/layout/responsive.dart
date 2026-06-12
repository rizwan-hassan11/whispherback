import 'dart:ui' show DisplayFeatureType;

import 'package:flutter/material.dart';

/// Material-style width breakpoints for phones, foldables, and tablets.
enum AppSizeClass { compact, medium, expanded }

/// Layout metrics shared by shell chrome, scroll insets, and hero controls.
abstract final class ShellMetrics {
  static const navBarContentHeight = 60.0;
  static const navOuterPaddingBottom = 16.0;
  static const miniPlayerHeight = 64.0;
  static const navHorizontalPadding = 12.0;
  static const railWidthCompact = 88.0;
  static const railWidthExtended = 220.0;

  static double bottomNavTotalHeight(BuildContext context) {
    return navBarContentHeight +
        navOuterPaddingBottom +
        MediaQuery.paddingOf(context).bottom;
  }

  static double scrollBottomInset(BuildContext context, {double extra = 8}) {
    if (Responsive.of(context).useSideNavigation) {
      return MediaQuery.paddingOf(context).bottom + extra;
    }
    return bottomNavTotalHeight(context) + miniPlayerHeight + extra;
  }

  static double playbackModalBottomInset(BuildContext context) {
    if (Responsive.of(context).useSideNavigation) {
      return MediaQuery.paddingOf(context).bottom + 8;
    }
    return bottomNavTotalHeight(context) - 4;
  }

  /// Extra lift for [Scaffold.floatingActionButton] above the glass nav bar.
  static double fabBottomInset(BuildContext context) {
    if (Responsive.of(context).useSideNavigation) {
      return MediaQuery.paddingOf(context).bottom + 8;
    }
    return bottomNavTotalHeight(context);
  }
}

/// Positions a FAB above the shell bottom navigation bar.
class ShellAwareFabLocation extends FloatingActionButtonLocation {
  const ShellAwareFabLocation(this.bottomInset);

  final double bottomInset;

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry geometry) {
    final end = FloatingActionButtonLocation.endFloat.getOffset(geometry);
    return Offset(end.dx, end.dy - bottomInset);
  }

  @override
  String toString() => 'ShellAwareFabLocation($bottomInset)';
}

/// Read viewport / fold / tablet layout from [BuildContext].
class Responsive {
  const Responsive._({
    required this.sizeClass,
    required this.width,
    required this.height,
    required this.shortestSide,
    required this.longestSide,
    required this.isLandscape,
    required this.isCompactHeight,
    required this.isFlipCover,
    required this.hingePadding,
    required this.useSideNavigation,
    required this.useExtendedSideNav,
    required this.contentMaxWidth,
    required this.horizontalGutter,
    required this.heroControlSize,
  });

  final AppSizeClass sizeClass;
  final double width;
  final double height;
  final double shortestSide;
  final double longestSide;
  final bool isLandscape;
  final bool isCompactHeight;
  final bool isFlipCover;
  final EdgeInsets hingePadding;
  final bool useSideNavigation;
  final bool useExtendedSideNav;
  final double contentMaxWidth;
  final double horizontalGutter;
  final double heroControlSize;

  static AppSizeClass sizeClassForWidth(double width) {
    if (width < 600) return AppSizeClass.compact;
    if (width < 840) return AppSizeClass.medium;
    return AppSizeClass.expanded;
  }

  static Responsive of(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = size.width;
    final height = size.height;
    final shortest = size.shortestSide;
    final longest = size.longestSide;
    final landscape = width > height;
    final sizeClass = sizeClassForWidth(width);
    final compactHeight = height < 680 || (shortest < 400 && height < 740);
    final flipCover = shortest < 360 && height < 620;

    final sideNav = sizeClass != AppSizeClass.compact &&
        (sizeClass == AppSizeClass.expanded ||
            landscape ||
            width / height > 0.62);
    final extendedSideNav =
        sizeClass == AppSizeClass.expanded || (width >= 720 && height >= 800);

    return Responsive._(
      sizeClass: sizeClass,
      width: width,
      height: height,
      shortestSide: shortest,
      longestSide: longest,
      isLandscape: landscape,
      isCompactHeight: compactHeight,
      isFlipCover: flipCover,
      hingePadding: _hingePadding(context, size),
      useSideNavigation: sideNav,
      useExtendedSideNav: extendedSideNav,
      contentMaxWidth:
          sizeClass == AppSizeClass.expanded ? 720 : double.infinity,
      horizontalGutter: switch (sizeClass) {
        AppSizeClass.compact => flipCover ? 14 : 20,
        AppSizeClass.medium => 24,
        AppSizeClass.expanded => 32,
      },
      heroControlSize:
          (shortest * (flipCover ? 0.48 : 0.55)).clamp(140.0, 220.0),
    );
  }

  static EdgeInsets _hingePadding(BuildContext context, Size size) {
    final features = MediaQuery.displayFeaturesOf(context);
    var left = 0.0;
    var right = 0.0;
    var top = 0.0;
    var bottom = 0.0;

    for (final feature in features) {
      if (feature.type != DisplayFeatureType.fold &&
          feature.type != DisplayFeatureType.hinge) {
        continue;
      }
      final rect = feature.bounds;
      if (rect.width <= 0 || rect.height <= 0) continue;

      final centerX = rect.center.dx;
      final centerY = rect.center.dy;
      if (centerX > size.width * 0.35 && centerX < size.width * 0.65) {
        left = left < 16 ? 16 : left;
        right = right < 16 ? 16 : right;
      }
      if (centerY > size.height * 0.35 && centerY < size.height * 0.65) {
        top = top < 16 ? 16 : top;
        bottom = bottom < 16 ? 16 : bottom;
      }
    }

    return EdgeInsets.fromLTRB(left, top, right, bottom);
  }
}

extension ResponsiveContext on BuildContext {
  Responsive get responsive => Responsive.of(this);

  EdgeInsets get shellScrollPadding => EdgeInsets.only(
        bottom: ShellMetrics.scrollBottomInset(this),
      );
}

/// Centers content on tablets / unfolded foldables and applies hinge padding.
class ResponsiveContent extends StatelessWidget {
  const ResponsiveContent({
    super.key,
    required this.child,
    this.padding,
    this.applyHingePadding = true,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool applyHingePadding;

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    final base =
        padding ?? EdgeInsets.symmetric(horizontal: r.horizontalGutter);
    final resolved = applyHingePadding ? base.add(r.hingePadding) : base;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: r.contentMaxWidth),
        child: Padding(padding: resolved, child: child),
      ),
    );
  }
}
