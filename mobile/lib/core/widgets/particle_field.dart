import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Lightweight ambient particle field that drifts slowly behind content.
///
/// Uses a single ticker and ~[count] particles, so it stays cheap enough to
/// run full-screen on low-end phones. Wrapped in a [RepaintBoundary] by the
/// caller's stack to avoid repainting siblings.
class ParticleField extends StatefulWidget {
  const ParticleField({
    super.key,
    this.count = 26,
    this.active = false,
  });

  /// Number of drifting particles.
  final int count;

  /// When true (app active), particles glow brighter and move a little faster.
  final bool active;

  @override
  State<ParticleField> createState() => _ParticleFieldState();
}

class _ParticleFieldState extends State<ParticleField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Particle> _particles;
  final _random = math.Random(7);

  @override
  void initState() {
    super.initState();
    _particles = List.generate(widget.count, (_) => _spawn());
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
  }

  _Particle _spawn() {
    return _Particle(
      position: Offset(_random.nextDouble(), _random.nextDouble()),
      velocity: Offset(
        (_random.nextDouble() - 0.5) * 0.018,
        (_random.nextDouble() - 0.5) * 0.018,
      ),
      radius: 1.2 + _random.nextDouble() * 2.4,
      phase: _random.nextDouble() * math.pi * 2,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              size: Size.infinite,
              painter: _ParticlePainter(
                particles: _particles,
                t: _controller.value,
                isDark: isDark,
                active: widget.active,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Particle {
  _Particle({
    required this.position,
    required this.velocity,
    required this.radius,
    required this.phase,
  });

  /// Normalized 0..1 coordinates.
  Offset position;
  final Offset velocity;
  final double radius;
  final double phase;
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter({
    required this.particles,
    required this.t,
    required this.isDark,
    required this.active,
  });

  final List<_Particle> particles;
  final double t;
  final bool isDark;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final speed = active ? 1.6 : 1.0;
    final baseAlpha = isDark ? 0.5 : 0.32;

    // Advance and resolve wrapped positions for this frame.
    final points = <Offset>[];
    for (final p in particles) {
      var x = (p.position.dx + p.velocity.dx * t * 60 * speed) % 1.0;
      var y = (p.position.dy + p.velocity.dy * t * 60 * speed) % 1.0;
      if (x < 0) x += 1.0;
      if (y < 0) y += 1.0;
      points.add(Offset(x * size.width, y * size.height));
    }

    // Connecting lines between nearby particles for a constellation feel.
    final linePaint = Paint()
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    const maxDist = 120.0;
    for (var i = 0; i < points.length; i++) {
      for (var j = i + 1; j < points.length; j++) {
        final d = (points[i] - points[j]).distance;
        if (d > maxDist) continue;
        final a = (1 - d / maxDist) * (active ? 0.28 : 0.16);
        linePaint.color = AppColors.neon.withValues(alpha: a);
        canvas.drawLine(points[i], points[j], linePaint);
      }
    }

    // Glowing dots with a gentle twinkle.
    for (var i = 0; i < particles.length; i++) {
      final p = particles[i];
      final twinkle =
          (math.sin(t * math.pi * 2 + p.phase) + 1) / 2 * 0.5 + 0.5;
      final color = active
          ? Color.lerp(AppColors.neon, AppColors.neonCyan, twinkle)!
          : AppColors.neon;
      final paint = Paint()
        ..color = color.withValues(alpha: baseAlpha * twinkle)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
      canvas.drawCircle(points[i], p.radius * (active ? 1.2 : 1.0), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter old) => true;
}
