import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:book_guard_app/src/page_number.dart';
import 'package:book_guard_app/src/page_reader.dart';
import 'package:book_guard_app/src/screens/box_painter.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// What the review screen settled on for one photo.
class ReviewResult {
  /// Creates a result.
  const new({this.page, this.box});

  /// The page number the phone read (null: let the PC decide).
  final int? page;

  /// Where it is, in the stored file's pixels.
  final Box? box;
}

/// Shows the photo upright with the page number the phone found boxed.
///
/// Wrong or missing? Tap another boxed number, or drag a box around the
/// right one: that box is read again at full resolution -- the number
/// itself is never typed, so it is always what is printed on the page.
class PhotoReview extends StatefulWidget {
  /// Creates the screen for the photo [bytes].
  const new({
    required this.bytes,
    required this.scan,
    required this.reader,
    required this.context,
    super.key,
  });

  /// The photo as stored.
  final Uint8List bytes;

  /// What the phone read off it.
  final PageScan scan;

  /// Reads a drawn box.
  final PageReader reader;

  /// What the photo was taken for.
  final PageContext context;

  @override
  State<PhotoReview> createState() => _PhotoReviewState();
}

class _PhotoReviewState extends State<PhotoReview> {
  late PageChoice _choice;

  /// The chosen number's box on the preview, when known.
  Box? _shown;
  Offset? _dragFrom;
  Offset? _dragTo;
  bool _reading = false;
  String? _note;

  @override
  void initState() {
    super.initState();
    _choice = choosePage(widget.scan.hits, widget.context);
  }

  /// Preview pixels -> stored pixels for every hit, computed both ways.
  List<(NumberHit, Box)> get _hitBoxes => [
    for (final (i, hit) in widget.scan.hits.indexed)
      (hit, widget.scan.previewHits[i]),
  ];

  void _pick(NumberHit hit, Box previewBox) => setState(() {
    _choice = PageChoice(hit);
    _shown = previewBox;
    _note = null;
  });

  Future<void> _readDrawn(Box previewBox) async {
    setState(() {
      _reading = true;
      _note = null;
    });
    final page = await widget.reader.readBox(
      widget.bytes,
      widget.scan,
      previewBox,
    );
    if (!mounted) return;
    setState(() {
      _reading = false;
      if (page == null) {
        _note = 'No number legible in that box - draw it tighter.';
      } else {
        _choice = PageChoice(
          NumberHit(page, widget.scan.toStoredBox(previewBox)),
        );
        _shown = previewBox;
      }
    });
  }

  Box? _pixelBox(Offset a, Offset b, double factor) {
    final box = (
      left: (math.min(a.dx, b.dx) / factor).floor(),
      top: (math.min(a.dy, b.dy) / factor).floor(),
      right: (math.max(a.dx, b.dx) / factor).ceil(),
      bottom: (math.max(a.dy, b.dy) / factor).ceil(),
    );
    return box.right - box.left < 4 || box.bottom - box.top < 4 ? null : box;
  }

  @override
  Widget build(BuildContext context) {
    final hit = _choice.hit;
    final title = hit != null ? 'Page ${hit.value}?' : 'Box the page number';
    final explain = hit != null
        ? 'Wrong? Tap the right number, or drag a box around it.'
        : '${_choice.reason[0].toUpperCase()}${_choice.reason.substring(1)}. '
              'Drag a box around the printed page number.';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(_note ?? explain),
            ),
            if (_reading) const LinearProgressIndicator(),
            Expanded(child: LayoutBuilder(builder: _photo)),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Retake'),
                  ),
                  const Spacer(),
                  if (hit == null)
                    TextButton(
                      onPressed: () =>
                          Navigator.of(context).pop(const ReviewResult()),
                      child: const Text('Send anyway'),
                    ),
                  FilledButton(
                    onPressed: hit == null || _reading
                        ? null
                        : () => Navigator.of(context)
                              .pop(ReviewResult(page: hit.value, box: hit.box)),
                    child: Text(hit == null ? 'Send' : 'Send p. ${hit.value}'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photo(BuildContext context, BoxConstraints space) {
    final scan = widget.scan;
    final factor = math.min(
      space.maxWidth / scan.previewWidth,
      space.maxHeight / scan.previewHeight,
    );
    final size = Size(scan.previewWidth * factor, scan.previewHeight * factor);
    final scheme = Theme.of(context).colorScheme;
    final drag = (_dragFrom, _dragTo);
    return Center(
      child: SizedBox.fromSize(
        size: size,
        child: GestureDetector(
          // The box starts where the finger touched, not ~18 px later
          // where the drag is recognised.
          dragStartBehavior: DragStartBehavior.down,
          onTapUp: (d) {
            for (final (hit, box) in _hitBoxes) {
              final rect = _rect(box, factor).inflate(16);
              if (rect.contains(d.localPosition)) return _pick(hit, box);
            }
          },
          onPanStart: (d) => setState(() {
            _dragFrom = d.localPosition;
            _dragTo = d.localPosition;
          }),
          onPanUpdate: (d) => setState(() => _dragTo = d.localPosition),
          onPanEnd: (_) {
            // The fields, not the build's copy: the last move may not have
            // been drawn yet.
            final (from, to) = (_dragFrom, _dragTo);
            setState(() => _dragFrom = _dragTo = null);
            final box = from == null || to == null
                ? null
                : _pixelBox(from, to, factor);
            if (box != null) unawaited(_readDrawn(box));
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(scan.preview, fit: BoxFit.fill),
              CustomPaint(
                painter: ReviewBoxPainter(
                  others: [for (final (_, b) in _hitBoxes) _rect(b, factor)],
                  chosen: _chosenRect(factor),
                  drawing: from(drag),
                  chosenColor: scheme.primary,
                  otherColor: scheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Rect? from((Offset?, Offset?) drag) => drag.$1 == null || drag.$2 == null
      ? null
      : Rect.fromPoints(drag.$1!, drag.$2!);

  Rect? _chosenRect(double factor) {
    final shown = _shown;
    if (shown != null) return _rect(shown, factor);
    final hit = _choice.hit;
    if (hit == null) return null;
    for (final (h, box) in _hitBoxes) {
      if (identical(h, hit)) return _rect(box, factor);
    }
    return null;
  }

  Rect _rect(Box box, double factor) => Rect.fromLTRB(
    box.left * factor,
    box.top * factor,
    box.right * factor,
    box.bottom * factor,
  );
}
