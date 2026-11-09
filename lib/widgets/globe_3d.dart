import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A rotating 3D particle globe, drawn with pure Flutter — no assets,
/// no paid packages. Hundreds of dots sit on a sphere; the sphere spins
/// around its vertical axis while tilted slightly, so dots on the near
/// side glow bright and dots on the far side fade away. It is the
/// centrepiece behind Ayra's voice orb: TZ Nova had a globe too, but
/// this one is sharper, deeper and fully alive.
class Globe3D extends StatefulWidget {
  const Globe3D({super.key, this.size = 240, this.speed = 1.0});

  /// Diameter in logical pixels.
  final double size;

  /// Rotation speed multiplier (1.0 = one turn every ~24 seconds).
  final double speed;

  @override
  State<Globe3D> createState() => _Globe3DState();
}

class _Globe3DState extends State<Globe3D>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: Size.square(widget.size),
          painter: _GlobePainter(
            angle: _controller.value * 2 * math.pi * widget.speed,
          ),
        );
      },
    );
  }
}

class _GlobePainter extends CustomPainter {
  _GlobePainter({required this.angle});

  final double angle;

  /// Sphere points: latitude rings with evenly spaced dots.
  static final List<(double lat, double lon)> _points = _buildPoints();

  static List<(double, double)> _buildPoints() {
    final points = <(double, double)>[];
    for (var lat = -75; lat <= 75; lat += 12) {
      final count = (24 * math.cos(lat * math.pi / 180)).round().clamp(6, 24);
      for (var i = 0; i < count; i++) {
        points.add((lat.toDouble(), i * 360 / count));
      }
    }
    return points;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 * 0.92;

    // Deep-space glow behind the globe.
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF3B82F6).withValues(alpha: 0.35),
          const Color(0xFF8B5CF6).withValues(alpha: 0.12),
          Colors.transparent,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 1.25));
    canvas.drawCircle(center, radius * 1.25, glowPaint);

    // Faint sphere shell.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFF3B82F6).withValues(alpha: 0.10)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFF60A5FA).withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // The sphere is tilted slightly towards the viewer.
    const tiltX = 0.42;
    final cosTilt = math.cos(tiltX);
    final sinTilt = math.sin(tiltX);
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);

    final dotPaint = Paint()..style = PaintingStyle.fill;
    for (final (latDeg, lonDeg) in _points) {
      final lat = latDeg * math.pi / 180;
      final lon = lonDeg * math.pi / 180;
      // Point on the unit sphere.
      var x = math.cos(lat) * math.sin(lon);
      var y = math.sin(lat);
      var z = math.cos(lat) * math.cos(lon);
      // Spin around the Y axis.
      final x1 = x * cosA + z * sinA;
      final z1 = -x * sinA + z * cosA;
      x = x1;
      z = z1;
      // Tilt around the X axis.
      final y1 = y * cosTilt - z * sinTilt;
      final z2 = y * sinTilt + z * cosTilt;
      y = y1;
      z = z2;
      // Depth: 0 (far side) .. 1 (near side). Far dots fade out.
      final depth = (z + 1) / 2;
      if (depth < 0.12) continue;
      final dotSize = 1.1 + depth * 2.1;
      final color = Color.lerp(
        const Color(0xFF1E3A8A),
        const Color(0xFF93C5FD),
        depth,
      )!;
      dotPaint.color = color.withValues(alpha: 0.25 + depth * 0.75);
      canvas.drawCircle(
        Offset(center.dx + x * radius, center.dy - y * radius),
        dotSize,
        dotPaint,
      );
    }

    // A bright arc sweeping over the top, for depth.
    final arcPaint = Paint()
      ..color = const Color(0xFFBFDBFE).withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.98),
      -2.4,
      1.1,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_GlobePainter oldDelegate) =>
      oldDelegate.angle != angle;
}
