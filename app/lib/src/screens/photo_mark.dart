/// What a photo is, as an icon and a number: the kind the PC read it as,
/// or the label (start, stop, check page) it was taken for.
library;

import 'package:book_guard_app/src/book_extras.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// The glyph and spoken name of a [PhotoKind].
(IconData, String) photoKindGlyph(PhotoKind kind) => switch (kind) {
  PhotoKind.page => (Icons.description, 'page'),
  PhotoKind.barcode => (Icons.qr_code_2, 'barcode'),
  PhotoKind.contents => (Icons.format_list_numbered, 'contents'),
  PhotoKind.other => (Icons.no_photography, 'not a page'),
};

/// The glyph, spoken name and number of a photo [label]: `start`, `stop`
/// or `check<N>`.
(IconData, String, int?) labelGlyph(String label) {
  if (label == 'start') return (Icons.play_arrow, 'start', null);
  if (label == 'stop') return (Icons.stop, 'stop', null);
  if (label.startsWith('check')) {
    return (Icons.fact_check, 'check page', int.tryParse(label.substring(5)));
  }
  return (Icons.photo_camera, 'photo', null);
}

/// A photo's kind icon and (for a page) its printed number.
class PhotoMark extends StatelessWidget {
  /// Creates the mark for the PC's reading of [photo].
  const new(this.photo, {super.key});

  /// What the PC made of the photo.
  final PhotoInfo photo;

  @override
  Widget build(BuildContext context) {
    final (icon, spoken) = photoKindGlyph(photo.what);
    final page = photo.page;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, semanticLabel: spoken),
        if (photo.what == PhotoKind.page) ...[
          const SizedBox(width: AppSpacing.xs),
          Text(page == null ? '?' : '$page'),
        ],
      ],
    );
  }
}

/// The icon (and number) of what a photo was taken for.
class LabelMark extends StatelessWidget {
  /// Creates the mark for [label].
  const new(this.label, {super.key});

  /// `start`, `stop` or `check<N>`.
  final String label;

  @override
  Widget build(BuildContext context) {
    final (icon, spoken, number) = labelGlyph(label);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, semanticLabel: spoken),
        if (number != null) ...[
          const SizedBox(width: AppSpacing.xs),
          Text('$number'),
        ],
      ],
    );
  }
}
