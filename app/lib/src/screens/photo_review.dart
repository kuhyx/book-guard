import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:book_guard_app/src/page_number.dart';
import 'package:book_guard_app/src/page_reader.dart';
import 'package:book_guard_app/src/screens/box_painter.dart';
import 'package:book_guard_app/src/screens/pulse_glyph.dart';
import 'package:book_guard_app/src/screens/reject_glyph.dart';
import 'package:book_guard_app/src/screens/review_buttons.dart';
import 'package:book_guard_app/src/ui/cues.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

export 'package:book_guard_app/src/screens/review_result.dart';

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
  int _misses = 0;

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
    _misses = 0;
  });

  Future<void> _readDrawn(Box previewBox) async {
    setState(() {
      _reading = true;
      _misses = 0;
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
        _misses++;
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
    // Why the reader needs a box (or that the drawn one held no number): a
    // glyph that buzzes once, never a sentence.
    final reason = _misses > 0 ? noNumberReason : _choice.reason;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        // A plain button: the stock BackButton carries a tooltip.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, semanticLabel: 'Back'),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (hit == null || _misses > 0)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: RejectBadge(
                  reason,
                  buzz: true,
                  size: 32,
                  key: ValueKey((reason, _misses)),
                ),
              ),
            if (_reading) const LinearProgressIndicator(),
            Expanded(child: LayoutBuilder(builder: _photo)),
            ReviewButtons(hit: hit, reading: _reading),
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
              if (_choice.hit case final hit?)
                Positioned(
                  top: AppSpacing.sm,
                  left: AppSpacing.sm,
                  // The tick and the number the reader settled on; nothing
                  // to tap.
                  child: IgnorePointer(
                    child: StatusCue(
                      const Cue(CueKind.ok, semanticLabel: 'page number read'),
                      key: ValueKey(hit.value),
                      badge: Text('${hit.value}'),
                    ),
                  ),
                )
              else
                Center(
                  child: PulseGlyph(Icons.crop_free, color: scheme.primary),
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
