/// A glyph beside a number: the text-free shape of "20 pages" or "30 min".
library;

import 'package:material_ui/material_ui.dart';

/// Pages (credited, read, asked).
const IconData pagesGlyph = Icons.description_outlined;

/// A span of minutes.
const IconData minutesGlyph = Icons.schedule;

/// A target or a line to reach.
const IconData targetGlyph = Icons.flag;

/// The +1 hour the day's number earns.
const IconData bonusGlyph = Icons.more_time;

/// A sick day.
const IconData sickGlyph = Icons.healing;

/// A free day: nothing asked.
const IconData freeGlyph = Icons.event_available;

/// An icon with its number (or any content) beside it; the words, if any,
/// are only spoken.
class IconNum extends StatelessWidget {
  /// Creates the pair; [number] is painted as is.
  const new(
    this.icon,
    this.number, {
    this.tint,
    this.semanticLabel,
    this.style,
    super.key,
  });

  /// The glyph.
  final IconData icon;

  /// The number or numeral beside it.
  final String number;

  /// Tint for both; the ambient colour when null.
  final Color? tint;

  /// What a screen reader says for the glyph.
  final String? semanticLabel;

  /// Style of the number; the ambient one when null.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => FittedBox(
    // A big font or a narrow card shrinks the pair instead of clipping it.
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: tint, semanticLabel: semanticLabel),
        const SizedBox(width: 4),
        Text(number, style: (style ?? const TextStyle()).copyWith(color: tint)),
      ],
    ),
  );
}
