import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// Soft ambient orbs, sound arcs, and dot field for the home screen.
class HomeAmbience extends StatelessWidget {
  const HomeAmbience({super.key, required this.isActive});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final isDark = whisperTheme(context).isDark;
    return IgnorePointer(
      child: CustomPaint(
        painter: _HomeAmbiencePainter(isActive: isActive, isDark: isDark),
        size: Size.infinite,
      ),
    );
  }
}

class _HomeAmbiencePainter extends CustomPainter {
  _HomeAmbiencePainter({required this.isActive, required this.isDark});

  final bool isActive;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    _drawOrbs(canvas, size);
    _drawArcRings(canvas, size);
    _drawDotField(canvas, size);
    if (isActive) _drawActiveGlow(canvas, size);
  }

  void _drawOrbs(Canvas canvas, Size size) {
    final orbs = isDark
        ? [
            (Offset(size.width * 0.85, size.height * 0.12), 90.0, AppColors.gold, 0.08),
            (Offset(size.width * 0.08, size.height * 0.22), 70.0, AppColors.brandLight, 0.10),
            (Offset(size.width * 0.92, size.height * 0.55), 120.0, AppColors.brandDark, 0.08),
            (Offset(size.width * 0.05, size.height * 0.72), 55.0, AppColors.gold, 0.06),
          ]
        : [
            (Offset(size.width * 0.88, size.height * 0.10), 100.0, AppColors.ink, 0.07),
            (Offset(size.width * 0.06, size.height * 0.20), 80.0, AppColors.lightMuted, 0.09),
            (Offset(size.width * 0.90, size.height * 0.52), 130.0, AppColors.success, 0.06),
            (Offset(size.width * 0.04, size.height * 0.70), 60.0, AppColors.ink, 0.05),
          ];

    for (final (center, radius, color, alpha) in orbs) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: alpha),
            color.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }
  }

  void _drawArcRings(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.46);
    final ringColor = isDark ? AppColors.brandLight : AppColors.ink;
    final radii = [118.0, 148.0, 178.0];
    for (var i = 0; i < radii.length; i++) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = ringColor.withValues(
          alpha: isDark ? (0.14 - i * 0.04) : (0.12 - i * 0.03),
        );
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radii[i]),
        math.pi * 0.72,
        math.pi * 0.56,
        false,
        paint,
      );
    }

    // Gold accent tick marks
    final tickPaint = Paint()
      ..color = (isDark ? AppColors.gold : AppColors.ink)
          .withValues(alpha: isDark ? 0.35 : 0.28)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 8; i++) {
      final angle = math.pi * 0.72 + (math.pi * 0.56 / 7) * i;
      final inner = center + Offset(math.cos(angle), math.sin(angle)) * 108;
      final outer = center + Offset(math.cos(angle), math.sin(angle)) * 114;
      canvas.drawLine(inner, outer, tickPaint);
    }
  }

  void _drawDotField(Canvas canvas, Size size) {
    final random = math.Random(42);
    final paint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < 28; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final r = 1.0 + random.nextDouble() * 1.5;
      paint.color = (isDark ? AppColors.soft : AppColors.muted)
          .withValues(alpha: 0.06 + random.nextDouble() * 0.08);
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  void _drawActiveGlow(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.46);
    final glowColor = isDark ? AppColors.brandLight : AppColors.ink;
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          glowColor.withValues(alpha: isDark ? 0.18 : 0.10),
          glowColor.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: 140));
    canvas.drawCircle(center, 140, paint);
  }

  @override
  bool shouldRepaint(covariant _HomeAmbiencePainter old) =>
      old.isActive != isActive || old.isDark != isDark;
}

/// Mini waveform bars for decorative use.
class HomeWaveBars extends StatelessWidget {
  const HomeWaveBars({super.key, required this.active, this.height = 32});

  final bool active;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = whisperTheme(context);
    return SizedBox(
      height: height,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(16, (i) {
          final h = active
              ? 6.0 + (math.sin(i * 0.9) + 1) * 10 + (i % 3) * 4
              : 4.0 + (i % 4) * 2;
          return AnimatedContainer(
            duration: Duration(milliseconds: 300 + i * 40),
            curve: Curves.easeOut,
            width: 3,
            height: h,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: active
                    ? [
                        theme.actionFill,
                        theme.isDark ? AppColors.brandLight : AppColors.inkSecondary,
                      ]
                    : [
                        theme.muted.withValues(alpha: 0.3),
                        theme.muted.withValues(alpha: 0.15),
                      ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
