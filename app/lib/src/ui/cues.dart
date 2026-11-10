/// Text-free status cues: a tinted icon plus a haptic (and a shake on an
/// error) instead of a sentence. Every cue carries its meaning twice (shape
/// and colour); the words exist only as a spoken label, never painted.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// What a cue reports.
enum CueKind {
  /// Something worked.
  ok(Icons.check_circle),

  /// Neutral information, e.g. queued on the phone.
  info(Icons.info_outline),

  /// Caution: not done yet, nothing to do.
  warn(Icons.hourglass_empty),

  /// Something failed or the input was refused.
  error(Icons.error);

  new(this.icon);

  /// Default glyph for this kind.
  final IconData icon;

  /// Tint for this kind from the active theme.
  Color tint(BuildContext context) {
    final status = context.statusColors;
    return switch (this) {
      CueKind.ok => status.success,
      CueKind.info => Theme.of(context).colorScheme.onSurfaceVariant,
      CueKind.warn => status.warning,
      CueKind.error => status.danger,
    };
  }

  /// The second channel: a haptic per kind (none for plain information).
  Future<void> buzz() => switch (this) {
    CueKind.ok => HapticFeedback.lightImpact(),
    CueKind.info => Future<void>.value(),
    CueKind.warn => HapticFeedback.mediumImpact(),
    CueKind.error => HapticFeedback.heavyImpact(),
  };
}

/// One cue: its kind, a glyph and the words a screen reader speaks.
@immutable
class Cue {
  /// Creates a cue; [icon] overrides the kind's default glyph.
  const new(this.kind, {required this.semanticLabel, this.icon});

  /// Meaning.
  final CueKind kind;

  /// Spoken description; never painted.
  final String semanticLabel;

  /// Glyph overriding the kind's default.
  final IconData? icon;

  /// The glyph shown.
  IconData get glyph => icon ?? kind.icon;
}

/// A tinted icon chip that replaces a status sentence. An error shakes
/// (skipped when the platform asks for reduced motion); every kind buzzes
/// its haptic once when it appears.
class StatusCue extends StatefulWidget {
  /// Creates the chip for [cue]; [badge] (a number, say) sits beside it.
  const new(this.cue, {this.badge, super.key});

  /// What it shows.
  final Cue cue;

  /// Optional content next to the glyph (a page number, a count).
  final Widget? badge;

  @override
  State<StatusCue> createState() => _StatusCueState();
}

class _StatusCueState extends State<StatusCue>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  @override
  void initState() {
    super.initState();
    unawaited(_announce());
  }

  Future<void> _announce() async {
    await widget.cue.kind.buzz();
    if (widget.cue.kind == CueKind.error &&
        mounted &&
        !MediaQuery.disableAnimationsOf(context)) {
      await _shake.forward();
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tint = widget.cue.kind.tint(context);
    final badge = widget.badge;
    return Semantics(
      liveRegion: true,
      label: widget.cue.semanticLabel,
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _shake,
          builder: (context, child) => Transform.translate(
            offset: Offset(math.sin(_shake.value * 6 * math.pi) * 8, 0),
            child: child,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: tint),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.cue.glyph, color: tint),
                  if (badge != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    badge,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows [cue] as an icon-only snackbar (with its haptic); replaces the
/// last one rather than queueing behind it. Returns without a messenger.
void showCue(BuildContext context, Cue cue, {Widget? badge}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: cue.kind == CueKind.error
            ? const Duration(seconds: 5)
            : const Duration(seconds: 3),
        content: Align(
          alignment: Alignment.centerLeft,
          child: StatusCue(cue, badge: badge),
        ),
      ),
    );
}
