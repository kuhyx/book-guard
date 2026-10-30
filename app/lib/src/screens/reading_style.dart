import 'package:flutter/painting.dart';

/// Every typographic choice of the in-app reader, in one place.
///
/// The reading surface deliberately leaves the app's dark design system:
/// pure black on pure white, a bundled book face (Literata, SIL OFL, in
/// `assets/fonts/`), a measure of about 34 em, ragged right and indented
/// paragraphs with no gap between them -- the conventions of a printed
/// novel, which is what the reader stands in for.
abstract final class ReadingStyle {
  /// The text colour.
  static const ink = Color(0xFF000000);

  /// The page colour.
  static const paper = Color(0xFFFFFFFF);

  /// The bundled variable serif (`pubspec.yaml` declares it).
  static const fontFamily = 'Literata';

  /// Line height, as a multiple of the font size.
  static const lineHeight = 1.5;

  /// The first line takes no extra leading above it, so a paragraph's top
  /// is its first line's top.
  static const TextHeightBehavior heightBehavior = TextHeightBehavior(
    applyHeightToFirstAscent: false,
  );

  /// The slider is the size: the system font scale is never stacked on it.
  static const TextScaler scaler = TextScaler.noScaling;

  /// Left and right margin on a phone.
  static const sideMargin = 20.0;

  /// Space above the text, inside the safe area.
  static const topPadding = 24.0;

  /// Space below the text, inside the safe area.
  static const bottomPadding = 48.0;

  /// The text column's widest measure, in ems.
  static const measureEm = 34.0;

  /// A paragraph's first-line indent, in ems.
  static const indentEm = 1.5;

  /// The smallest size the settings offer.
  static const minFont = 14.0;

  /// The largest size the settings offer.
  static const maxFont = 32.0;

  /// The default size on a phone.
  static const phoneFont = 18.0;

  /// The default size on a wide window.
  static const wideFont = 20.0;

  /// From this window width on, [wideFont] is the default.
  static const wideWindow = 900.0;

  /// How long a tap's screenful scroll takes.
  static const pageTurn = Duration(milliseconds: 180);

  /// The size to read at: [saved] (clamped to the slider's whole steps),
  /// else the default for a window [width] wide.
  static double sizeFor(double? saved, double width) => saved == null
      ? (width >= wideWindow ? wideFont : phoneFont)
      : saved.roundToDouble().clamp(minFont, maxFont);

  /// The text column's widest measure at [size].
  static double measure(double size) => measureEm * size;

  /// One line's height at [size].
  static double lineOf(double size) => lineHeight * size;

  /// The body text at [size], complete (it inherits nothing from the app).
  static TextStyle text(double size) => TextStyle(
    inherit: false,
    color: ink,
    fontFamily: fontFamily,
    fontSize: size,
    height: lineHeight,
    letterSpacing: 0,
    wordSpacing: 0,
    fontWeight: FontWeight.w400,
    fontStyle: FontStyle.normal,
    textBaseline: TextBaseline.alphabetic,
    leadingDistribution: TextLeadingDistribution.even,
    decoration: TextDecoration.none,
    fontVariations: [
      const FontVariation('wght', 400),
      FontVariation('opsz', size),
    ],
  );
}
