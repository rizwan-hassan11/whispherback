import 'package:flutter/material.dart';

import '../layout/responsive.dart';
import '../theme/app_theme.dart';
import 'glass_nav_bar.dart';
import 'glass_side_nav.dart';

/// Bottom bar on phones; glass side rail on unfolded foldables / tablets.
class AdaptiveShellNav extends StatelessWidget {
  const AdaptiveShellNav({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.destinations,
    this.showAllLabels = false,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<GlassNavDestination> destinations;
  final bool showAllLabels;

  @override
  Widget build(BuildContext context) {
    final useSide = context.responsive.useSideNavigation;

    if (!useSide) {
      return GlassNavBar(
        showAllLabels: showAllLabels,
        selectedIndex: selectedIndex,
        onSelected: onSelected,
        destinations: destinations,
      );
    }

    return GlassSideNav(
      extended: context.responsive.useExtendedSideNav,
      selectedIndex: selectedIndex,
      onSelected: onSelected,
      destinations: destinations,
    );
  }
}
