import 'dart:typed_data';

import 'package:book_guard_app/src/page_number.dart';
import 'package:book_guard_app/src/page_reader.dart';
import 'package:image/image.dart' as img;

/// A valid 40x60 PNG for [PageScan.preview].
final Uint8List previewPng = img.encodePng(img.Image(width: 40, height: 60));

/// Builds a scan whose preview is [previewPng] and whose hits sit at
/// [previewBoxes] (preview pixels) -- stored boxes are the same x10.
PageScan fakeScan(List<(int, Box)> previewBoxes) {
  Box scale(Box b) => (
    left: b.left * 10,
    top: b.top * 10,
    right: b.right * 10,
    bottom: b.bottom * 10,
  );
  return PageScan(
    turn: 0,
    hits: [for (final (v, b) in previewBoxes) NumberHit(v, scale(b))],
    previewHits: [for (final (_, b) in previewBoxes) b],
    preview: previewPng,
    previewWidth: 40,
    previewHeight: 60,
    toStoredBox: scale,
    toDecodedBox: scale,
    millis: 1,
  );
}

/// A [PageReader] that answers from fields.
class FakeReader implements PageReader {
  /// Creates a reader returning [result] from [scan].
  new(this.result, {this.boxed});

  /// What [scan] returns.
  PageScan? result;

  /// What [readBox] returns.
  int? boxed;

  /// Every preview box [readBox] was asked about.
  final List<Box> asked = [];

  @override
  Future<PageScan?> scan(Uint8List bytes) async => result;

  @override
  Future<int?> readBox(Uint8List bytes, PageScan scan, Box previewBox) async {
    asked.add(previewBox);
    return boxed;
  }
}
