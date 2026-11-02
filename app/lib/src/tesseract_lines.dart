/// What the Tesseract channel returns, as the reader's own types.
library;

import 'dart:math' as math;

import 'package:book_guard_app/src/page_number.dart';

/// Tesseract's lines from the platform channel: a list of lines, each a
/// list of word maps `{text, left, top, right, bottom, conf}` in the pixels
/// of the image it was handed (confidence 0-1). Words below [minConfidence]
/// are left out, and a line with none left is dropped.
///
/// Tesseract does not turn lines to read them, so [SeenLine.angle] stays
/// null: the reader turns the whole page upright before it reads.
List<SeenLine> linesFromChannel(Object? raw, {double minConfidence = 0}) {
  final lines = <SeenLine>[];
  for (final line in (raw as List<Object?>? ?? const [])) {
    final words = [
      for (final word in (line! as List<Object?>).cast<Map<Object?, Object?>>())
        if ((word['conf']! as num) >= minConfidence)
          (
            text: word['text']! as String,
            box: (
              left: word['left']! as int,
              top: word['top']! as int,
              right: word['right']! as int,
              bottom: word['bottom']! as int,
            ),
            conf: (word['conf']! as num).toDouble(),
          ),
    ];
    if (words.isEmpty) continue;
    lines.add(
      SeenLine(
        words.map((w) => w.text).join(' '),
        (
          left: words.map((w) => w.box.left).reduce(math.min),
          top: words.map((w) => w.box.top).reduce(math.min),
          right: words.map((w) => w.box.right).reduce(math.max),
          bottom: words.map((w) => w.box.bottom).reduce(math.max),
        ),
        words: [for (final w in words) (w.text, w.box)],
        confidence: [for (final w in words) w.conf],
      ),
    );
  }
  return lines;
}

/// [line] moved from a window cut at ([left], [top]) and read at [ratio]
/// times the page's size into the page's own pixels.
SeenLine placeLine(SeenLine line, int left, int top, double ratio) {
  Box place(Box b) => (
    left: ((b.left + left) * ratio).floor(),
    top: ((b.top + top) * ratio).floor(),
    right: ((b.right + left) * ratio).ceil(),
    bottom: ((b.bottom + top) * ratio).ceil(),
  );
  return SeenLine(
    line.text,
    place(line.box),
    words: [for (final (text, box) in line.words) (text, place(box))],
    confidence: line.confidence,
    angle: line.angle,
  );
}

/// [lines] without a later line that repeats an earlier one's text on top
/// of it -- overlapping windows read the same number twice.
List<SeenLine> withoutRepeats(List<SeenLine> lines) {
  final kept = <SeenLine>[];
  for (final line in lines) {
    final repeat = kept.any(
      (k) =>
          k.text == line.text &&
          (k.box.left - line.box.left).abs() <= (k.box.right - k.box.left) &&
          (k.box.top - line.box.top).abs() <= (k.box.bottom - k.box.top),
    );
    if (!repeat) kept.add(line);
  }
  return kept;
}

/// [lines] reduced to their words Tesseract is sure of: the upright-ness
/// score counts only those, because a page read upside down still yields
/// plenty of word-shaped garbage -- at low confidence.
List<SeenLine> sureWords(List<SeenLine> lines, {double floor = 0.6}) => [
  for (final line in lines)
    SeenLine(
      line.text,
      line.box,
      words: [
        for (final (i, word) in line.words.indexed)
          if ((line.confidence[i] ?? 0) >= floor) word,
      ],
    ),
];
