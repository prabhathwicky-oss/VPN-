import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme.dart';

/// The big power button. Pulses while connecting, glows when connected.
class ConnectButton extends StatefulWidget {
  const ConnectButton({super.key, required this.status, required this.onTap});
  final ConnStatus status;
  final VoidCallback onTap;

  @override
  State<ConnectButton> createState() => _ConnectButtonState();
}

class _ConnectButtonState extends State<ConnectButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Color get _color => switch (widget.status) {
        ConnStatus.connected => Palette.mint,
        ConnStatus.connecting || ConnStatus.reconnecting || ConnStatus.disconnecting => Palette.amber,
        ConnStatus.disconnected => Palette.muted,
      };

  bool get _busy =>
      widget.status == ConnStatus.connecting ||
      widget.status == ConnStatus.reconnecting ||
      widget.status == ConnStatus.disconnecting;

  @override
  Widget build(BuildContext context) {
    const size = 212.0;
    return Semantics(
      button: true,
      label: widget.status == ConnStatus.connected ? 'Disconnect' : 'Connect',
      child: GestureDetector(
        onTap: widget.status == ConnStatus.disconnecting ? null : widget.onTap,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value;
            return SizedBox(
              width: size + 60,
              height: size + 60,
              child: Stack(alignment: Alignment.center, children: [
                if (_busy || widget.status == ConnStatus.connected)
                  for (var i = 0; i < 2; i++)
                    _Ring(
                      size: size + 60 * ((t + i / 2) % 1.0),
                      opacity: (1 - ((t + i / 2) % 1.0)) * (_busy ? 0.35 : 0.18),
                      color: _color,
                    ),
                if (_busy)
                  Transform.rotate(
                    angle: t * 2 * math.pi,
                    child: SizedBox(
                      width: size + 8,
                      height: size + 8,
                      child: CircularProgressIndicator(
                        value: 0.22,
                        strokeWidth: 3,
                        color: _color,
                        backgroundColor: Colors.transparent,
                      ),
                    ),
                  ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [_color.withValues(alpha: 0.30), Palette.surface],
                      stops: const [0.0, 0.85],
                    ),
                    border: Border.all(color: _color.withValues(alpha: 0.9), width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: _color.withValues(alpha: widget.status == ConnStatus.connected ? 0.45 : 0.12),
                        blurRadius: 48,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Icon(Icons.power_settings_new_rounded, size: 84, color: _color),
                ),
              ]),
            );
          },
        ),
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.size, required this.opacity, required this.color});
  final double size;
  final double opacity;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: opacity.clamp(0.0, 1.0)), width: 2),
      ),
    );
  }
}
