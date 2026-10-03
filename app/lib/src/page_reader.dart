import 'dart:typed_data';

import 'package:book_guard_app/src/page_number.dart';
import 'package:book_guard_app/src/page_reader_none.dart'
    if (dart.library.io) 'package:book_guard_app/src/page_reader_mlkit.dart'
    as platform;

/// What the phone read off one photo, before anything is uploaded.
class PageScan {
  /// Creates a scan.
  const new({
    required this.turn,
    required this.hits,
    required this.previewHits,
    required this.preview,
    required this.previewWidth,
    required this.previewHeight,
    required this.toStoredBox,
    required this.toDecodedBox,
    required this.millis,
  });

  /// Degrees clockwise the decoded photo was turned to read upright.
  final int turn;

  /// Lone numbers near the top or bottom edge, boxes in stored pixels.
  final List<NumberHit> hits;

  /// The same hits' boxes on [preview], index for index.
  final List<Box> previewHits;

  /// The upright, downscaled page as JPEG, for the review screen.
  final Uint8List preview;

  /// [preview]'s width in pixels.
  final int previewWidth;

  /// [preview]'s height in pixels.
  final int previewHeight;

  /// A box drawn on [preview] -> the same box in the stored file's pixels.
  final Box Function(Box previewBox) toStoredBox;

  /// A box drawn on [preview] -> the decoded (EXIF-applied) photo's pixels.
  final Box Function(Box previewBox) toDecodedBox;

  /// How long reading took, for the log.
  final int millis;
}

/// Reads page numbers on the device. Null where there is no on-device OCR
/// (the desktop web build: its photos go straight to the PC).
abstract interface class PageReader {
  /// Reads the photo [bytes] (a JPEG as stored); null if unreadable.
  Future<PageScan?> scan(Uint8List bytes);

  /// The number inside [previewBox] of [scan]'s preview, read at full
  /// resolution; null if none is legible there.
  Future<int?> readBox(Uint8List bytes, PageScan scan, Box previewBox);
}

/// The reader for this platform, or null.
PageReader? createPageReader() => platform.createPageReader();
