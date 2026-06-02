import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../layout/responsive.dart';
import '../theme/app_colors.dart';
import 'depth_surface.dart';
import 'glass_nav_bar.dart';

/// Premium vertical navigation for fold-open and tablet layouts.
class GlassSideNav extends StatelessWidget {
  const GlassSideNav({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.destinations,
    this.extended = false,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<GlassNavDestination> destinations;
  final bool extended;

  static const _compactWidth = 88.0;
  static const _extendedWidth = 220.0;
  static const _itemHeight = 52.0;

  double get width => extended ? _extendedWidth : _compactWidth;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      width: width,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark
                    ? [
                        const Color(0xF7102650),
                        const Color(0xF2040B1E),
                      ]
                    : [
                        Colors.white.withValues(alpha: 0.98),
                        const Color(0xF0F1F5F9),
                      ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.18)
                    : AppColors.ink.withValues(alpha: 0.12),
              ),
              boxShadow: AppDepth.shadows(
                isDark: isDark,
                elevated: true,
                intensity: 0.9,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      extended ? 18 : 12, 18, extended ? 18 : 12, 12),
                  child: extended
                      ? Text(
                          'WhisperBack',
                          style: GoogleFonts.fraunces(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.35,
                            color:
                                isDark ? AppColors.soft : AppColors.lightSoft,
                          ),
                        )
                      : Center(
                          child: Text(
                            'W',
                            style: GoogleFonts.fraunces(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color:
                                  isDark ? AppColors.brandLight : AppColors.ink,
                            ),
                          ),
                        ),
                ),
                Divider(
                  height: 1,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : AppColors.ink.withValues(alpha: 0.08),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            AnimatedPositioned(
                              duration: const Duration(milliseconds: 340),
                              curve: const Cubic(0.34, 1.28, 0.64, 1),
                              top: selectedIndex * _itemHeight,
                              left: 0,
                              right: 0,
                              height: _itemHeight,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: AppColors.neonGradient,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.28),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.neon.withValues(
                                          alpha: isDark ? 0.5 : 0.38),
                                      blurRadius: 18,
                                      offset: const Offset(0, 4),
                                    ),
                                    BoxShadow(
                                      color: AppColors.neonCyan
                                          .withValues(alpha: 0.22),
                                      blurRadius: 10,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Column(
                              children: List.generate(destinations.length, (i) {
                                final d = destinations[i];
                                final selected = i == selectedIndex;
                                return SizedBox(
                                  height: _itemHeight,
                                  child: _RailNavItem(
                                    destination: d,
                                    selected: selected,
                                    extended: extended,
                                    onTap: () => onSelected(i),
                                  ),
                                );
                              }),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RailNavItem extends StatelessWidget {
  const _RailNavItem({
    required this.destination,
    required this.selected,
    required this.extended,
    required this.onTap,
  });

  final GlassNavDestination destination;
  final bool selected;
  final bool extended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inactiveColor = isDark ? AppColors.muted : AppColors.lightMuted;
    const activeColor = Colors.white;

    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          splashColor: Colors.white.withValues(alpha: 0.06),
          highlightColor: Colors.transparent,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: extended ? 14 : 4),
            child: extended
                ? Row(
                    children: [
                      Icon(
                        selected ? destination.selectedIcon : destination.icon,
                        size: 22,
                        color: selected ? activeColor : inactiveColor,
                        shadows: selected
                            ? const [
                                Shadow(
                                    color: Color(0xCCFFFFFF), blurRadius: 10),
                              ]
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          destination.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                            color: selected ? activeColor : inactiveColor,
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        selected ? destination.selectedIcon : destination.icon,
                        size: 22,
                        color: selected ? activeColor : inactiveColor,
                        shadows: selected
                            ? const [
                                Shadow(
                                    color: Color(0xCCFFFFFF), blurRadius: 10),
                              ]
                            : null,
                      ),
                      if (selected) ...[
                        const SizedBox(height: 3),
                        Text(
                          destination.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.15,
                            color: activeColor,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Side rail width for shell layout calculations.
double glassSideNavWidth(BuildContext context) {
  final r = Responsive.of(context);
  if (!r.useSideNavigation) return 0;
  return r.useExtendedSideNav
      ? GlassSideNav._extendedWidth
      : GlassSideNav._compactWidth;
}
