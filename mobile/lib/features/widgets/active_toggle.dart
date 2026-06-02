import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/layout/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';

/// Blue-neon power control for the home screen.
///
/// When the app is inactive the button reads as physically "off" — a dim,
/// unlit disc. Tapping it ignites an electric-blue glow with an expanding
/// charge ring and a soft ignition bounce. Tapping again powers it back down.
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
    with TickerProviderStateMixin {
  /// 0 = powered off, 1 = powered on. Drives every color/glow transition.
  late final AnimationController _power;
  late final Animation<double> _ignite;

  /// One-shot ring that sweeps outward on the moment of ignition.
  late final AnimationController _charge;

  /// Continuous breathing glow + pulse rings while active.
  late final AnimationController _breathe;

  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _power = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
      value: widget.isActive ? 1 : 0,
    );
    _ignite = CurvedAnimation(parent: _power, curve: Curves.easeOutBack);
    _charge = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _breathe = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    if (widget.isActive) _breathe.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(ActiveToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _power.forward();
      _charge.forward(from: 0);
      _breathe.repeat(reverse: true);
    } else if (!widget.isActive && oldWidget.isActive) {
      _power.reverse();
      _breathe.stop();
    }
  }

  @override
  void dispose() {
    _power.dispose();
    _charge.dispose();
    _breathe.dispose();
    super.dispose();
  }

  void _handleTap() {
    widget.onToggle();
  }

  @override
  Widget build(BuildContext context) {
    final heroSize = context.responsive.heroControlSize;
    final discSize = heroSize * 0.74;
    final iconSize = heroSize * 0.26;

    return GestureDetector(
      onTap: _handleTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: SizedBox(
        width: heroSize,
        height: heroSize,
        child: AnimatedBuilder(
          animation: Listenable.merge([_power, _charge, _breathe]),
          builder: (context, child) {
            final t = _ignite.value.clamp(0.0, 1.0);
            final on = _power.value;
            final breathe = widget.isActive
                ? (math.sin(_breathe.value * math.pi * 2) + 1) / 2
                : 0.0;

            final iconColor = Color.lerp(
              const Color(0xFF5A6B8C),
              AppColors.neonCyan,
              on,
            )!;

            return Stack(
              alignment: Alignment.center,
              children: [
                // Expanding pulse halos while active.
                if (widget.isActive) ...[
                  _PulseRing(progress: _breathe.value, size: heroSize),
                  _PulseRing(
                    progress: (_breathe.value + 0.5) % 1,
                    size: heroSize,
                  ),
                ],

                // One-shot ignition charge ring.
                if (_charge.isAnimating)
                  _ChargeRing(progress: _charge.value, size: heroSize),

                // Outer neon halo (fades in with power).
                Container(
                  width: discSize,
                  height: discSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.neon.withValues(
                            alpha: 0.55 * on * (0.7 + breathe * 0.3)),
                        blurRadius: 48 + breathe * 18,
                        spreadRadius: 2 + breathe * 4,
                      ),
                      BoxShadow(
                        color: AppColors.neonCyan.withValues(alpha: 0.30 * on),
                        blurRadius: 110,
                        spreadRadius: 6,
                      ),
                    ],
                  ),
                ),

                // The physical disc.
                Transform.scale(
                  scale: (_pressed ? 0.95 : 1.0) * (0.9 + 0.1 * t),
                  child: Container(
                    width: discSize,
                    height: discSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: on > 0.02
                          ? LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color.lerp(
                                  const Color(0xFF0B1730),
                                  const Color(0xFF143A82),
                                  on,
                                )!,
                                Color.lerp(
                                  const Color(0xFF060E22),
                                  const Color(0xFF071A40),
                                  on,
                                )!,
                              ],
                            )
                          : AppColors.powerOffGradient,
                      border: Border.all(
                        color: Color.lerp(
                          AppColors.glassBorder,
                          AppColors.neonBright.withValues(alpha: 0.9),
                          on,
                        )!,
                        width: 1.5 + on,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          offset: const Offset(0, 16),
                          blurRadius: 30,
                          spreadRadius: -6,
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Inner glow gradient when lit.
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  AppColors.neon.withValues(alpha: 0.35 * on),
                                  AppColors.neon.withValues(alpha: 0),
                                ],
                                stops: const [0, 0.85],
                              ),
                            ),
                          ),
                        ),
                        // Top specular highlight for a glassy dome.
                        Positioned(
                          top: discSize * 0.12,
                          child: Container(
                            width: discSize * 0.6,
                            height: discSize * 0.32,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.white
                                      .withValues(alpha: 0.10 + 0.06 * on),
                                  Colors.white.withValues(alpha: 0),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Thin neon ring just inside the rim when lit.
                        Container(
                          width: discSize * 0.82,
                          height: discSize * 0.82,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.neonCyan.withValues(
                                  alpha: 0.5 * on * (0.6 + breathe * 0.4)),
                              width: 1.4,
                            ),
                          ),
                        ),
                        Icon(
                          AppIcons.power,
                          size: iconSize,
                          color: iconColor,
                          shadows: on > 0.05
                              ? [
                                  Shadow(
                                    color: AppColors.neonCyan
                                        .withValues(alpha: 0.9 * on),
                                    blurRadius: 18 + breathe * 8,
                                  ),
                                ]
                              : null,
                        ),
                      ],
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

/// Soft continuously-breathing halo ring shown while the control is active.
class _PulseRing extends StatelessWidget {
  const _PulseRing({required this.progress, required this.size});

  final double progress;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scale = 0.78 + progress * 0.5;
    final opacity = (1 - progress) * 0.35;
    return Transform.scale(
      scale: scale,
      child: Container(
        width: size * 0.74,
        height: size * 0.74,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: AppColors.neonCyan.withValues(alpha: opacity),
            width: 1.4,
          ),
        ),
      ),
    );
  }
}

/// One-shot bright ring that sweeps outward at the instant of ignition.
class _ChargeRing extends StatelessWidget {
  const _ChargeRing({required this.progress, required this.size});

  final double progress;
  final double size;

  @override
  Widget build(BuildContext context) {
    final eased = Curves.easeOutCubic.transform(progress);
    final scale = 0.7 + eased * 0.85;
    final opacity = (1 - eased) * 0.8;
    return Transform.scale(
      scale: scale,
      child: Container(
        width: size * 0.74,
        height: size * 0.74,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: AppColors.neonCyan.withValues(alpha: opacity),
            width: 2.4,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.neon.withValues(alpha: opacity * 0.6),
              blurRadius: 16,
            ),
          ],
        ),
      ),
    );
  }
}
