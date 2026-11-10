import 'package:flutter/material.dart';

/// A glyph that pulses (grows and fades) to say "act here", still when the
/// platform asks for no animation. Never takes touches: a drag beneath it
/// still draws a box.
class PulseGlyph extends StatefulWidget {
  /// Creates the glyph.
  const new(this.icon, {required this.color, this.size = 96, super.key});

  /// What to draw.
  final IconData icon;

  /// Its colour.
  final Color color;

  /// Its size.
  final double size;

  @override
  State<PulseGlyph> createState() => _PulseGlyphState();
}

class _PulseGlyphState extends State<PulseGlyph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _beat = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _beat
        ..stop()
        ..value = 1;
    } else if (!_beat.isAnimating) {
      _beat.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: _beat,
      builder: (context, child) => Opacity(
        opacity: 0.45 + 0.55 * _beat.value,
        child: Transform.scale(scale: 0.85 + 0.3 * _beat.value, child: child),
      ),
      child: Icon(
        widget.icon,
        size: widget.size,
        color: widget.color,
        semanticLabel: 'box the page number',
      ),
    ),
  );
}
