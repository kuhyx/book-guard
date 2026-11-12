/// Hold-to-confirm: a deliberate action needs a press held until a ring
/// fills, instead of a dialog with words.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// An icon button that fires [onConfirmed] only after being held for
/// [hold]; letting go early resets the ring.
class HoldButton extends StatefulWidget {
  /// Creates the button.
  const new({
    required this.icon,
    required this.semanticLabel,
    required this.onConfirmed,
    this.hold = const Duration(milliseconds: 900),
    super.key,
  });

  /// The glyph inside the ring.
  final IconData icon;

  /// Spoken name; never painted.
  final String semanticLabel;

  /// Fired once the ring is full.
  final VoidCallback onConfirmed;

  /// How long the press must last.
  final Duration hold;

  @override
  State<HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<HoldButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ring =
      AnimationController(vsync: this, duration: widget.hold)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            unawaited(HapticFeedback.mediumImpact());
            widget.onConfirmed();
            _ring.reset();
          }
        });

  @override
  void dispose() {
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      // A screen reader cannot hold: a double-tap confirms at once.
      onTap: widget.onConfirmed,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTapDown: (_) => _ring.forward(),
          onTapUp: (_) => _ring.reverse(),
          onTapCancel: () => _ring.reverse(),
          child: SizedBox.square(
            dimension: 56,
            child: AnimatedBuilder(
              animation: _ring,
              builder: (context, _) => Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.square(
                    dimension: 52,
                    child: CircularProgressIndicator(
                      value: _ring.value,
                      strokeWidth: 4,
                      backgroundColor: scheme.outlineVariant,
                    ),
                  ),
                  Icon(widget.icon, color: scheme.primary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
