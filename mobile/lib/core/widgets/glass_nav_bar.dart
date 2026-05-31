import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'depth_surface.dart';

class GlassNavBar extends StatelessWidget {
  const GlassNavBar({
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        0,
        12,
        16 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 56,
            child: IgnorePointer(
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      (isDark ? AppColors.deep : AppColors.lightBg)
                          .withValues(alpha: isDark ? 0.72 : 0.85),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(28),
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
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.18)
                        : AppColors.ink.withValues(alpha: 0.14),
                  ),
                  boxShadow: AppDepth.shadows(
                    isDark: isDark,
                    elevated: true,
                    intensity: 1.1,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final count = destinations.length;
                      final itemWidth = constraints.maxWidth / count;

                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 340),
                            curve: const Cubic(0.34, 1.28, 0.64, 1),
                            left: selectedIndex * itemWidth,
                            top: 0,
                            bottom: 0,
                            width: itemWidth,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: isDark
                                      ? [AppColors.brand, const Color(0xEBF1F5F9)]
                                      : [AppColors.ink, const Color(0xFF0A2048)],
                                ),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: isDark
                                        ? AppColors.brandGlow
                                        : AppColors.lightBrandGlow,
                                    blurRadius: 18,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Row(
                            children: List.generate(count, (i) {
                              final d = destinations[i];
                              final selected = i == selectedIndex;
                              final showLabel =
                                  showAllLabels || (selected && d.label.isNotEmpty);
                              return Expanded(
                                child: _NavItem(
                                  destination: d,
                                  selected: selected,
                                  showLabel: showLabel,
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
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.showLabel,
    required this.onTap,
  });

  final GlassNavDestination destination;
  final bool selected;
  final bool showLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inactiveColor = isDark ? AppColors.muted : AppColors.lightMuted;
    final activeColor = isDark ? AppColors.deep : AppColors.lightBg;

    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          splashColor: Colors.white.withValues(alpha: 0.06),
          highlightColor: Colors.transparent,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.fromLTRB(4, 7, 4, showLabel ? 8 : 7),
            constraints: const BoxConstraints(minHeight: 50),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedScale(
                  scale: selected ? 1.06 : 1,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    selected ? destination.selectedIcon : destination.icon,
                    size: 22,
                    color: selected ? activeColor : inactiveColor,
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: showLabel
                      ? Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                              letterSpacing: 0.2,
                              color: selected ? activeColor : inactiveColor,
                            ),
                            child: Text(
                              destination.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class GlassNavDestination {
  const GlassNavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}
