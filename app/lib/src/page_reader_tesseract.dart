import 'package:book_guard_app/src/page_number.dart';
import 'package:book_guard_app/src/page_prep.dart';
import 'package:book_guard_app/src/page_reader.dart';
import 'package:book_guard_app/src/pencil.dart' show loadPencilNetBytes;
import 'package:book_guard_app/src/pencil_scan.dart';
import 'package:book_guard_app/src/tesseract_lines.dart';
import 'package:book_guard_app/src/tesseract_reads.dart';
import 'package:flutter/services.dart';

/// Tesseract on the phone: no network, no PC, no Claude.
PageReader? createPageReader() => TesseractPageReader();

/// One scan's result and its pencil read, still running.
typedef _Scanned = ({PageScan scan, Future<int?>? pencil});

const _turns = [0, 90, 180, 270];
// This many sure, wide words is an upright page: the later turns' reads
// are dropped.
const _uprightEnough = 25;
// Hits re-read from a crop: a page seldom has more than a spread's two
// numbers.
const _recheckMax = 4;

int _notShorter(int page, int? crop) =>
    crop != null && '$crop'.length >= '$page'.length ? crop : page;

/// Tesseract4Android through the `book_guard/tesseract` channel. A scan
/// decodes the photo once, flattens it once, reads the likely turn (the other
/// three at once only when it is not upright) and re-reads each number from
/// a full-resolution crop (2026-11-22: 3.5-20 s a photo before).
class TesseractPageReader extends TesseractReads implements PageReader {
  /// Creates the reader; [channel] is for tests.
  new({MethodChannel channel = const MethodChannel('book_guard/tesseract')})
    : super(channel);

  // The turn the last photo read upright at: the phone is held the same way
  // all session, so it comes first (it wins a tie).
  var _lastTurn = 0;

  Uint8List? _net;

  @override
  Future<PageScan?> scan(
    Uint8List bytes, {
    PageContext context = const PageContext(),
  }) async {
    stages.clear();
    final watch = Stopwatch()..start();
    final PreparedPhoto photo;
    try {
      photo = await timed('prep', () => apart(preparePhoto, bytes));
    } on Exception {
      return null;
    }
    model = 'fast';
    final first = await _scan(photo, watch);
    if (_usable(first.scan, context)) return await _withPencil(first);
    // p. 611 of 2026-11-09: the fast model reads the bold corner number as
    // a word of letters. The full model is slower and reads other photos
    // worse (p. 502 as "2"), so it only gets a say where the fast one has
    // nothing usable -- on the turn the fast one found.
    model = 'full';
    try {
      final second = await _scan(photo, watch, turns: [first.scan.turn]);
      return await _withPencil(_usable(second.scan, context) ? second : first);
    } finally {
      model = 'fast';
    }
  }

  /// [scan] with a pencilled number kept: only a suggestion for the
  /// keypad, never a hit. It runs even where Tesseract found a number, which
  /// may be its misreading of the pencil ([PageScan.withPencil] drops a hit
  /// the pencil contradicts). It started alongside the crops' re-reads.
  Future<PageScan> _withPencil(_Scanned scanned) async {
    final pencil = scanned.pencil;
    if (pencil == null) return scanned.scan;
    return scanned.scan.withPencil(await timed('pencil', () => pencil));
  }

  /// The pencil net's answer for [body] on [preview]; any failure is no
  /// answer (the scan stays as it was).
  Future<int?> _pencil(Future<Uint8List> preview, PencilBody body) async {
    try {
      final net = _net ??= await loadPencilNetBytes();
      return await pencilFromPreview(net, await preview, body);
    } on Exception {
      return null;
    }
  }

  // `boxed` skips the "far from the last end" rule: that is the reader's
  // call, not a reason to read the photo again.
  bool _usable(PageScan scan, PageContext context) =>
      choosePage(scan.hits, context, boxed: true).hit != null;

  /// The turn whose read is the page: the likely turn is read alone (four
  /// engines at once each read three times slower, and most photos are
  /// upright on it); only when it is not sure are the other three read at
  /// once. The pick is the in-order one (the first with enough sure words,
  /// else the best, the earliest on a tie).
  Future<(int, int, List<SeenLine>)> _upright(Gray ink, List<int> order) async {
    final first = await readTurn(ink, order.first);
    final firstScore = wideWords(sureWords(first));
    if (firstScore >= _uprightEnough || order.length == 1) {
      return (firstScore, order.first, first);
    }
    final rest = order.skip(1).toList();
    final reads = await Future.wait([
      for (final turn in rest) readTurn(ink, turn),
    ]);
    var (best, bestTurn, bestLines) = (firstScore, order.first, first);
    for (final (i, turn) in rest.indexed) {
      final score = wideWords(sureWords(reads[i]));
      if (score > best) (best, bestTurn, bestLines) = (score, turn, reads[i]);
      if (score >= _uprightEnough) break;
    }
    return (best, bestTurn, bestLines);
  }

  Future<_Scanned> _scan(
    PreparedPhoto photo,
    Stopwatch watch, {
    List<int>? turns,
  }) async {
    final (prepared, ink, decoded) = photo;
    final small = prepared.small;
    final order = turns ?? [_lastTurn, ..._turns.where((t) => t != _lastTurn)];
    // The preview of the turn tried first is made while the turns are read.
    final likely = apart(previewFor, (small, order.first));
    final (best, bestTurn, bestLines) = await _upright(ink, order);
    _lastTurn = bestTurn;
    final preview = bestTurn == order.first
        ? likely
        : apart(previewFor, (small, bestTurn));
    final body = pencilBody(bestLines);
    final pencil = body == null ? null : _pencil(preview, body);
    final sideways = bestTurn == 90 || bestTurn == 270;
    Box toDecodedBox(Box box) =>
        unturn(box, bestTurn, prepared.width, prepared.height, prepared.scale);
    Box toStoredBox(Box box) => toStored(
      toDecodedBox(box),
      prepared.orientation,
      prepared.storedWidth,
      prepared.storedHeight,
    );
    final width = sideways ? prepared.height : prepared.width;
    final height = sideways ? prepared.width : prepared.height;
    var numbers = numberLines(bestLines, height);
    // No sure word on any turn (a black photo): no page, and its edge
    // strips cost seconds.
    if (numbers.isEmpty && best > 0) {
      numbers = numberLines(
        await timed('edge', () => edgeLines(decoded, bestTurn, width)),
        height,
      );
    }
    // The whole page is read at 1600 px, where a 151 can read as 161: each
    // number is read again from its own full-resolution crop. A crop fixes or
    // adds a digit ("2" for 502), never drops one ("12" for 612).
    final rechecked = numbers.take(_recheckMax).toList();
    final reread = await timed(
      'crops',
      () => readCrops(decoded, [
        for (final (_, line) in rechecked) toDecodedBox(line.box),
      ], bestTurn),
    );
    numbers = [
      for (final (i, (number, line)) in rechecked.indexed)
        (_notShorter(number, reread[i]), line),
    ];
    final scan = PageScan(
      turn: bestTurn,
      hits: [
        for (final (number, line) in numbers)
          NumberHit(number, toStoredBox(line.box)),
      ],
      previewHits: [for (final (_, line) in numbers) line.box],
      preview: await preview,
      previewWidth: width,
      previewHeight: height,
      toStoredBox: toStoredBox,
      toDecodedBox: toDecodedBox,
      millis: watch.elapsedMilliseconds,
      pencilBody: body,
    );
    if (preview != likely) likely.ignore();
    return (scan: scan, pencil: pencil);
  }

  @override
  Future<int?> readBox(Uint8List bytes, PageScan scan, Box previewBox) =>
      readCrop(bytes, scan.toDecodedBox(previewBox), scan.turn);
}
