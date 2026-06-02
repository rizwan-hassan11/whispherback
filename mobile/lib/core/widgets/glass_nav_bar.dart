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
          // Soft scrim fade above the bar — only in dark mode. In light mode
          // it read as a muddy grey band, so we omit it for a clean look.
          if (isDark)
            Positioned(
              left: 0,
              right: 0,
              bottom: 56,
              child: IgnorePointer(
                child: Container(
                  height: 40,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Color(0xB8020611),
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
                  boxShadow: isDark
                      ? AppDepth.shadows(
                          isDark: true,
                          elevated: true,
                          intensity: 1.1,
                        )
                      : [
                          BoxShadow(
                            color: AppColors.ink.withValues(alpha: 0.07),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
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
                                gradient: AppColors.neonGradient,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.28),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.neon.withValues(
                                        alpha: isDark ? 0.55 : 0.42),
                                    blurRadius: 22,
                                    offset: const Offset(0, 5),
                                  ),
                                  BoxShadow(
                                    color: AppColors.neonCyan
                                        .withValues(alpha: 0.28),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Row(
                            children: List.generate(count, (i) {
                              final d = destinations[i];
                              final selected = i == selectedIndex;
                              final showLabel = showAllLabels ||
                                  (selected && d.label.isNotEmpty);
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
    const activeColor = Colors.white;

    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          splashColor: AppColors.neon.withValues(alpha: 0.12),
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
                  scale: selected ? 1.08 : 1,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    selected ? destination.selectedIcon : destination.icon,
                    size: 22,
                    color: selected ? activeColor : inactiveColor,
                    shadows: selected
                        ? const [
                            Shadow(
                              color: Color(0xCCFFFFFF),
                              blurRadius: 10,
                            ),
                          ]
                        : null,
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
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
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
