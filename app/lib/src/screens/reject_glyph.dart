/// A rejected photo as one of a few fixed glyphs, each with its own tint,
/// instead of the reason sentence. The reason strings stay as data (the PC's
/// `Reading.reason`, the phone's `PageChoice.reason`); they are only mapped
/// here, never painted.
library;

import 'dart:async';

import 'package:book_guard_app/src/ui/cues.dart';
import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

/// What the phone says when it found no number on a photo the PC has not
/// read yet (the card for it is drawn before the PC answers).
const phoneFoundNone = 'the phone found no page number';

/// The reason of a box that held no number.
const noNumberReason = 'no page number found';

const Color _violet = Color(0xFF8E6BC9);
const Color _blue = Color(0xFF4F8FD6);
const Color _teal = Color(0xFF3AA6A0);

/// The glyphs a rejected photo can wear.
enum RejectGlyph {
  /// Several candidate numbers, or one too far from the last page.
  unclear(Icons.call_split, 'number unclear'),

  /// No page number (or not the expected one) on the photo.
  noNumber(Icons.search_off, 'no page number'),

  /// The photo is not a page, or the wrong kind of photo.
  notPage(Icons.no_photography, 'not a page'),

  /// The PC could not read the photo, or it is gone.
  pcUnreadable(Icons.desktop_access_disabled, 'the PC could not read it'),

  /// It overlaps another session.
  overlap(Icons.filter_none, 'overlaps another session'),

  /// A reason none of the above covers.
  unknown(Icons.warning_amber, 'rejected');

  new(this.icon, this.semanticLabel);

  /// The glyph.
  final IconData icon;

  /// Spoken only.
  final String semanticLabel;

  /// Each glyph has its own colour: shape and colour both say which. The
  /// shared palette has only three status hues, so the other two are fixed
  /// here (readable on the light and the dark theme).
  Color tint(BuildContext context) {
    final status = context.statusColors;
    return switch (this) {
      RejectGlyph.unclear => status.warning,
      RejectGlyph.noNumber => status.danger,
      RejectGlyph.notPage => _violet,
      RejectGlyph.pcUnreadable => _blue,
      RejectGlyph.overlap => _teal,
      RejectGlyph.unknown => Theme.of(context).colorScheme.onSurfaceVariant,
    };
  }
}

/// Which glyph a rejection [reason] gets. The PC appends a "box it or
/// retake" suffix to a number reason, so every branch matches a prefix or a
/// fragment, the most specific first; an empty reason is a photo the PC took
/// for something else than a page.
RejectGlyph rejectGlyph(String reason) {
  final text = reason.trim().toLowerCase();
  if (text.isEmpty || text.startsWith('no page on the photo')) {
    return RejectGlyph.notPage;
  }
  if (text.contains('unclear') || text.contains('is far from p.')) {
    return RejectGlyph.unclear;
  }
  if (text.contains('could not read')) return RejectGlyph.pcUnreadable;
  if (text.contains('overlap')) return RejectGlyph.overlap;
  if (text.contains('no page number') ||
      text.startsWith('no page after') ||
      text.contains('not found on the photo')) {
    return RejectGlyph.noNumber;
  }
  return RejectGlyph.unknown;
}

/// The glyph for a rejection [reason] in its own tint. [buzz] fires the
/// error haptic once when it appears: set it where the verdict arrives,
/// never for a card redrawn from a list.
class RejectBadge extends StatefulWidget {
  /// Creates the badge.
  const new(this.reason, {this.buzz = false, this.size = 24, super.key});

  /// The reason string, as the PC or the phone wrote it.
  final String reason;

  /// Whether to buzz once on appearing.
  final bool buzz;

  /// Icon size.
  final double size;

  @override
  State<RejectBadge> createState() => _RejectBadgeState();
}

class _RejectBadgeState extends State<RejectBadge> {
  @override
  void initState() {
    super.initState();
    if (widget.buzz) unawaited(CueKind.error.buzz());
  }

  @override
  Widget build(BuildContext context) {
    final glyph = rejectGlyph(widget.reason);
    final tint = glyph.tint(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: tint),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: Icon(
          glyph.icon,
          color: tint,
          size: widget.size,
          semanticLabel: glyph.semanticLabel,
        ),
      ),
    );
  }
}
