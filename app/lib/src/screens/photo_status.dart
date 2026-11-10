/// How a photo's trip to the PC stands, as one tinted glyph (and the page
/// number) instead of a sentence.
library;

import 'package:book_guard_app/src/book_extras.dart';
import 'package:book_guard_app/src/screens/reject_glyph.dart';
import 'package:book_guard_app/src/ui/cues.dart';
import 'package:flutter/material.dart';

/// One state of a photo: a [cue], the page number it concerns, and (for a
/// rejection) the reason that picks its own glyph.
@immutable
class PhotoStatus {
  /// Creates a status.
  const new(this.cue, {this.page, this.reject, this.good});

  /// What the PC made of [photo]; null means it has not read it yet.
  factory of(PhotoInfo? photo) {
    if (photo == null) return const PhotoStatus(_notYet);
    if (!photo.accepted) {
      return PhotoStatus(_rejected, reject: photo.reason, good: false);
    }
    return switch (photo.what) {
      PhotoKind.page => PhotoStatus(_read, page: photo.page, good: true),
      PhotoKind.contents => const PhotoStatus(_contents, good: true),
      _ => const PhotoStatus(_barcode, good: true),
    };
  }

  /// Queued on the phone, to go up when the PC is reachable.
  factory saved(int? page) => PhotoStatus(_queued, page: page);

  /// Uploaded; the PC has not answered yet.
  factory uploaded(int? page) => PhotoStatus(_uploaded, page: page);

  /// The photo stays on the phone: the review was left.
  static const kept = PhotoStatus(
    Cue(CueKind.info, icon: Icons.save_alt, semanticLabel: 'photo kept'),
  );

  /// The photo was thrown away to be taken again.
  static const discarded = PhotoStatus(
    Cue(CueKind.info, icon: Icons.delete_outline, semanticLabel: 'discarded'),
  );

  /// The phone is reading the page number.
  static const reading = PhotoStatus(
    Cue(CueKind.info, icon: Icons.crop_free, semanticLabel: 'reading'),
  );

  /// Meaning and glyph.
  final Cue cue;

  /// The page number it concerns, if known.
  final int? page;

  /// The rejection reason, when the PC rejected the photo.
  final String? reject;

  /// Whether the PC took the photo (null: undecided or still on the phone).
  final bool? good;
}

const _notYet = Cue(
  CueKind.warn,
  icon: Icons.hourglass_empty,
  semanticLabel: 'the PC has not read it yet',
);
const _rejected = Cue(CueKind.error, semanticLabel: 'not accepted');
const _read = Cue(CueKind.ok, semanticLabel: 'read');
const _contents = Cue(
  CueKind.ok,
  icon: Icons.format_list_numbered,
  semanticLabel: 'contents read',
);
const _barcode = Cue(
  CueKind.ok,
  icon: Icons.qr_code_2,
  semanticLabel: 'barcode read',
);
const _queued = Cue(
  CueKind.info,
  icon: Icons.outbox,
  semanticLabel: 'saved on the phone',
);
const _uploaded = Cue(
  CueKind.info,
  icon: Icons.cloud_upload,
  semanticLabel: 'uploaded',
);

/// The chip for [status]: a rejection wears its own glyph and buzzes
/// once, every other state is a [StatusCue] (ok buzzes light).
class PhotoStatusChip extends StatelessWidget {
  /// Creates the chip.
  const new(this.status, {super.key});

  /// What to draw.
  final PhotoStatus status;

  @override
  Widget build(BuildContext context) {
    final reason = status.reject;
    if (reason != null) return RejectBadge(reason, buzz: true, size: 32);
    final page = status.page;
    return StatusCue(status.cue, badge: page == null ? null : Text('$page'));
  }
}

/// A snackbar holding [status], replacing the one showing.
void showPhotoStatus(BuildContext context, PhotoStatus status) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Align(
          alignment: Alignment.centerLeft,
          child: PhotoStatusChip(status),
        ),
      ),
    );
}
