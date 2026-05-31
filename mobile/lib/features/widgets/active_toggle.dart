import 'package:flutter/material.dart';

import '../../core/layout/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/depth_surface.dart';
import '../../core/theme/app_icons.dart';

class ActiveToggle extends StatefulWidget {
  const ActiveToggle({
    super.key,
    required this.isActive,
    required this.onToggle,
  });

  final bool isActive;
  final VoidCallback onToggle;

  @override
  State<ActiveToggle> createState() => _ActiveToggleState();
}

class _ActiveToggleState extends State<ActiveToggle>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    if (widget.isActive) _controller.value = 1;
  }

  @override
  void didUpdateWidget(ActiveToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _controller.forward(from: 0);
    } else if (!widget.isActive && oldWidget.isActive) {
      _controller.reverse(from: 1);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final heroSize = context.responsive.heroControlSize;
    final innerSize = heroSize * 0.764;
    final iconSize = heroSize * 0.236;
    final pulseOuter = heroSize * 0.945;
    final pulseMid = heroSize * 1.091;
    final pulseInner = heroSize * 1.236;

    return GestureDetector(
      onTap: widget.onToggle,
      child: SizedBox(
        width: heroSize,
        height: heroSize,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return Stack(
              alignment: Alignment.center,
              children: [
                if (widget.isActive) ...[
                  _PulseRing(size: pulseOuter, opacity: 0.15),
                  _PulseRing(size: pulseMid, opacity: 0.08),
                  _PulseRing(size: pulseInner, opacity: 0.04),
                ],
                Transform.rotate(
                  angle: _controller.value * 0.35,
                  child: Container(
                    width: innerSize,
                    height: innerSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: widget.isActive
                          ? AppColors.brandGradient
                          : LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppColors.card,
                                AppColors.deep2,
                              ],
                            ),
                      border: Border.all(
                        color: widget.isActive
                            ? Colors.white.withValues(alpha: 0.2)
                            : AppColors.glassBorder,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
                          offset: const Offset(0, 14),
                          blurRadius: 28,
                          spreadRadius: -4,
                        ),
                        BoxShadow(
                          color: AppColors.brand.withValues(alpha: isDark ? 0.08 : 0.04),
                          offset: const Offset(0, -2),
                          blurRadius: 0,
                        ),
                        if (widget.isActive)
                          BoxShadow(
                            color: AppColors.brandGlow,
                            blurRadius: 60,
                            spreadRadius: 4,
                          ),
                        if (widget.isActive)
                          BoxShadow(
                            color: AppColors.brand.withValues(alpha: 0.2),
                            blurRadius: 120,
                          ),
                      ],
                    ),
                    child: Transform.rotate(
                      angle: -_controller.value * 0.35,
                      child: Icon(
                        AppIcons.power,
                        size: iconSize,
                        color: widget.isActive ? AppColors.deep : AppColors.muted,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PulseRing extends StatefulWidget {
  const _PulseRing({required this.size, required this.opacity});

  final double size;
  final double opacity;

  @override
  State<_PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<_PulseRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        return Transform.scale(
          scale: 1 + _pulse.value * 0.04,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.brandLight.withValues(alpha: widget.opacity),
              ),
            ),
          ),
        );
      },
    );
  }
}
