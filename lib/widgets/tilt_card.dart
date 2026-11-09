import 'package:flutter/material.dart';

/// A card that leans in 3D towards the finger while it is pressed and
/// springs back on release — pure Flutter perspective, no assets.
/// The shadow shifts against the tilt so the card feels like it floats
/// above the background.
class TiltCard extends StatefulWidget {
  const TiltCard({super.key, required this.child, this.maxTilt = 0.16});

  final Widget child;

  /// Maximum tilt in radians (0.16 is subtle-premium, not wobbly).
  final double maxTilt;

  @override
  State<TiltCard> createState() => _TiltCardState();
}

class _TiltCardState extends State<TiltCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spring;
  double _tiltX = 0;
  double _tiltY = 0;
  double _fromTiltX = 0;
  double _fromTiltY = 0;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _spring = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
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
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  void _onDown(TapDownDetails details, Size size) {
    final local = details.localPosition;
    final nx = (local.dx / size.width - 0.5) * 2;
    final ny = (local.dy / size.height - 0.5) * 2;
    setState(() {
      _pressed = true;
      _tiltX = (ny * widget.maxTilt).clamp(-widget.maxTilt, widget.maxTilt);
      _tiltY = (-nx * widget.maxTilt).clamp(-widget.maxTilt, widget.maxTilt);
    });
  }

  void _onUp() {
    _fromTiltX = _tiltX;
    _fromTiltY = _tiltY;
    setState(() => _pressed = false);
    _spring.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, 400);
        return GestureDetector(
          onTapDown: (details) => _onDown(details, size),
          onTapUp: (_) => _onUp(),
          onTapCancel: _onUp,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF3B82F6).withValues(
                    alpha: _pressed ? 0.28 : 0.10,
                  ),
                  blurRadius: _pressed ? 28 : 16,
                  offset: Offset(-_tiltY * 40, 10 + _tiltX * 40),
                ),
              ],
            ),
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0016)
                ..rotateX(_tiltX)
                ..rotateY(_tiltY),
              child: widget.child,
            ),
          ),
        );
      },
    );
  }
}
