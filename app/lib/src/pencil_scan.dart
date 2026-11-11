/// The phone's use of the pencil reader: where the page's text sits (from
/// what Tesseract read) and the upright preview decoded to gray, read off the
/// UI thread. Port of `book_guard/_pencil.py` `column_body`.
library;

import 'dart:isolate';
import 'dart:typed_data';

import 'package:book_guard_app/src/page_number.dart';
import 'package:book_guard_app/src/pencil.dart';
import 'package:image/image.dart' as img;

export 'package:book_guard_app/src/pencil.dart' show PencilBody;

// This many sure words is an upright page (`book_guard/_sparse.py`).
const _uprightWords = 10;
const _sureConfidence = 0.8;
const _sureLength = 3;
// Text columns this many lines apart are different pages.
const _columnGap = 1.0;

typedef _Word = (String, Box);

/// The box and line height of the text column with the most sure words in
/// [lines] (the facing page's text is another column), or null when fewer
/// than ten words are sure -- the turn is unknown and a 6 is a 9 upside down.
PencilBody? pencilBody(List<SeenLine> lines) {
  final sure = <_Word>[
    for (final line in lines)
      for (final (i, word) in line.words.indexed)
        if ((line.confidence.elementAtOrNull(i) ?? 0) >= _sureConfidence &&
            word.$1.length >= _sureLength &&
            RegExp(r'^\p{L}+$', unicode: true).hasMatch(word.$1))
          word,
  ];
  if (sure.length < _uprightWords) return null;
  final heights = [for (final (_, b) in sure) b.bottom - b.top]..sort();
  final mid = heights.length ~/ 2;
  final line = heights.length.isOdd
      ? heights[mid] + 0.0
      : (heights[mid - 1] + heights[mid]) / 2;
  sure.sort((a, b) => a.$2.left.compareTo(b.$2.left));
  final columns = <List<_Word>>[];
  var reach = 0;
  for (final word in sure) {
    if (columns.isNotEmpty && word.$2.left <= reach + _columnGap * line) {
      columns.last.add(word);
      if (word.$2.right > reach) reach = word.$2.right;
    } else {
      columns.add([word]);
      reach = word.$2.right;
    }
  }
  var main = columns.first;
  for (final column in columns) {
    if (column.length > main.length) main = column;
  }
  int least(int Function(Box) f) =>
      main.map((w) => f(w.$2)).reduce((a, b) => a < b ? a : b);
  int most(int Function(Box) f) =>
      main.map((w) => f(w.$2)).reduce((a, b) => a > b ? a : b);
  return (
    left: least((b) => b.left),
    top: least((b) => b.top),
    right: most((b) => b.right),
    bottom: most((b) => b.bottom),
    line: line,
  );
}

/// The pencilled page number in the margin of the upright [previewJpeg]
/// (whose text sits at [body]), or null. [netBytes] is the weights file;
/// decoding and reading run in a separate isolate. Never throws: an image
/// that cannot be decoded is null.
Future<int?> pencilFromPreview(
  Uint8List netBytes,
  Uint8List previewJpeg,
  PencilBody body,
) => Isolate.run(() {
  final img.Image? image;
  try {
    image = img.decodeJpg(previewJpeg);
  } on img.ImageException {
    return null;
  }
  if (image == null) return null;
  final gray = Uint8List(image.width * image.height);
  var at = 0;
  for (final p in image) {
    gray[at++] = p.luminance.round().clamp(0, 255);
  }
  return readPencilPage(
    PencilNet.parse(netBytes),
    gray,
    image.width,
    image.height,
    body: body,
  );
});
