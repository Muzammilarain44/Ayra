import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Ayra's voice orb, rebuilt as a real 3D object — pure Flutter, no
/// assets, no paid packages. A layered glass sphere with a bright core,
/// two Saturn-style rings spinning on different planes, a breathing glow
/// while listening, and true perspective tilt: drag it and it leans
/// towards your finger in 3D, then springs back. This is the upgrade
/// over TZ Nova's flat orb.
class Orb3D extends StatefulWidget {
  const Orb3D({
    super.key,
    required this.listening,
    required this.onTap,
    this.size = 168,
  });

  final bool listening;
  final VoidCallback onTap;
  final double size;

  @override
  State<Orb3D> createState() => _Orb3DState();
}

class _Orb3DState extends State<Orb3D> with TickerProviderStateMixin {
  late final AnimationController _spin;
  late final AnimationController _breathe;
  late final AnimationController _spring;
  double _tiltX = 0;
  double _tiltY = 0;
  double _fromTiltX = 0;
  double _fromTiltY = 0;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
    _breathe = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _spring = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _spring.addListener(() {
      final t = 1 - _spring.value;
      setState(() {
        _tiltX = _fromTiltX * t;
        _tiltY = _fromTiltY * t;
      });
    });
  }

  @override
  void didUpdateWidget(Orb3D oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.listening && !_breathe.isAnimating) {
      _breathe.repeat(reverse: true);
    } else if (!widget.listening) {
      _breathe.stop();
      _breathe.value = 0.25;
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _breathe.dispose();
    _spring.dispose();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails details, double halfSize) {
    setState(() {
      _tiltX = (details.delta.dy / halfSize).clamp(-0.6, 0.6);
      _tiltY = (-details.delta.dx / halfSize).clamp(-0.6, 0.6);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    _fromTiltX = _tiltX;
    _fromTiltY = _tiltY;
    _spring.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final half = widget.size / 2;
    return GestureDetector(
      onTap: widget.onTap,
      onPanUpdate: (details) => _onPanUpdate(details, half),
      onPanEnd: _onPanEnd,
      child: AnimatedBuilder(
        animation: Listenable.merge([_spin, _breathe]),
        builder: (context, child) {
          final breathe =
              widget.listening ? 0.45 + 0.55 * _breathe.value : 0.22;
          final ringAngle = _spin.value * 2 * math.pi;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0022)
              ..rotateX(_tiltX)
              ..rotateY(_tiltY),
            child: SizedBox(
              width: widget.size + 48,
              height: widget.size + 48,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer glow.
                  Container(
                    width: widget.size + 44,
                    height: widget.size + 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF3B82F6)
                              .withValues(alpha: 0.30 * breathe + 0.10),
                          blurRadius: 46,
                          spreadRadius: 6,
                        ),
                        BoxShadow(
                          color: const Color(0xFF8B5CF6)
                              .withValues(alpha: 0.22 * breathe + 0.06),
                          blurRadius: 70,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                  // Back ring (tilted plane, slow spin).
                  Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..rotateX(1.15)
                      ..rotateZ(ringAngle),
                    child: Container(
                      width: widget.size + 30,
                      height: widget.size + 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF60A5FA)
                              .withValues(alpha: 0.55),
                          width: 1.6,
                        ),
                      ),
                    ),
                  ),
                  // Front ring (different plane, counter-spin).
                  Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..rotateX(1.35)
                      ..rotateZ(-ringAngle * 0.7 + 0.8),
                    child: Container(
                      width: widget.size + 14,
                      height: widget.size + 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFC4B5FD)
                              .withValues(alpha: 0.45),
                          width: 1.2,
                        ),
                      ),
                    ),
                  ),
                  // The sphere itself: layered radial gradients.
                  Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        center: Alignment(-0.35, -0.4),
                        radius: 1.05,
                        colors: [
                          Color(0xFFDBEAFE),
                          Color(0xFF60A5FA),
                          Color(0xFF3B82F6),
                          Color(0xFF6D28D9),
                          Color(0xFF1E1B4B),
                        ],
                        stops: [0.0, 0.25, 0.55, 0.82, 1.0],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x88000000),
                          blurRadius: 24,
                          offset: Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Gloss highlight, top-left.
                        Align(
                          alignment: const Alignment(-0.45, -0.5),
                          child: Container(
                            width: widget.size * 0.42,
                            height: widget.size * 0.30,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                widget.size * 0.21,
                              ),
                              gradient: RadialGradient(
                                colors: [
                                  Colors.white.withValues(alpha: 0.55),
                                  Colors.white.withValues(alpha: 0.0),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              widget.listening ? Icons.mic : Icons.mic_none,
                              size: 52,
                              color: Colors.white,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              widget.listening ? 'Listening…' : 'Tap to speak',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
