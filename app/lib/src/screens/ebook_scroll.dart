import 'dart:async';

import 'package:book_guard_app/src/ebook_paragraphs.dart';
import 'package:book_guard_app/src/screens/ebook_paragraph_view.dart';
import 'package:book_guard_app/src/screens/reading_style.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The book as one continuous scroll, like a long web post.
///
/// Opening at `anchor` needs no measuring of what comes before it: the
/// paragraph holding it is the scroll view's `center`, the ones before it
/// grow upward in their own sliver, and one jump puts the anchor's line at
/// the top. Where the reader is (`firstVisibleOffset`) is read back from
/// the layout: the first line wholly on screen.
class BookScroll extends StatefulWidget {
  /// Creates the scroll of [text] at [anchor].
  const new({
    required this.text,
    required this.paragraphs,
    required this.fontSize,
    required this.anchor,
    required this.onSettled,
    super.key,
  });

  /// The whole book.
  final String text;

  /// [text], split.
  final BookParagraphs paragraphs;

  /// The font size.
  final double fontSize;

  /// The book offset to open on.
  final int anchor;

  /// Called with [BookScrollState.firstVisibleOffset] whenever a scroll
  /// comes to rest (and once after opening).
  final void Function(int offset) onSettled;

  @override
  State<BookScroll> createState() => BookScrollState();
}

/// [BookScroll]'s state: paging and where the reader is.
class BookScrollState extends State<BookScroll> {
  static const Key _centerKey = ValueKey('center');

  final Map<int, GlobalKey> _keys = {};
  ScrollController _controller = ScrollController();
  late int _anchor = widget.anchor;
  late int _center = widget.paragraphs.indexOf(_anchor);
  double? _width;
  int _generation = 0;
  int? _reported;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToAnchor());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _line => ReadingStyle.lineOf(widget.fontSize);

  /// The height text scrolls through.
  double get viewportHeight => _controller.position.viewportDimension;

  /// The laid-out paragraphs, top to bottom.
  List<(int, ParagraphGeometry)> _laidOut() {
    final out = <(int, ParagraphGeometry)>[];
    final gone = <int>[];
    for (final MapEntry(:key, :value) in _keys.entries) {
      final box = value.currentContext?.findRenderObject();
      if (box is RenderParagraph && box.attached && box.hasSize) {
        out.add((key, ParagraphGeometry(widget.paragraphs.all[key], box)));
      } else if (value.currentContext == null) {
        gone.add(key);
      }
    }
    gone.forEach(_keys.remove);
    return out..sort((a, b) => a.$1.compareTo(b.$1));
  }

  /// The book offset of the line at [y] below the viewport's top: the
  /// start of the first line reaching below [y].
  int? offsetAt(double y) {
    final viewport = context.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return null;
    for (final (i, geometry) in _laidOut()) {
      final box = geometry.box;
      final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
      if (top + box.size.height <= y + 0.5) continue;
      if (top >= y - 0.5) return widget.paragraphs.all[i].start;
      return geometry.offsetAt(widget.text, y - top);
    }
    return null;
  }

  /// The first character of the first line wholly on screen.
  int? firstVisibleOffset() {
    final viewport = context.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return null;
    for (final (i, geometry) in _laidOut()) {
      final box = geometry.box;
      final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
      if (top + box.size.height <= ParagraphGeometry.slack) continue;
      if (top >= -ParagraphGeometry.slack) {
        return widget.paragraphs.all[i].start;
      }
      final whole = geometry.firstWholeLine(widget.text, -top);
      if (whole != null) return whole;
    }
    return null;
  }

  /// Scrolls a screenful on ([direction] 1) or back (-1), less one line so
  /// the line cut at the edge is read whole and nothing is skipped.
  Future<void> page(int direction) async {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final step = position.viewportDimension - _line;
    final to = (position.pixels + direction * step).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (to == position.pixels) return;
    await _controller.animateTo(
      to,
      duration: ReadingStyle.pageTurn,
      curve: Curves.easeOut,
    );
  }

  /// Puts the anchor's line at the top (the center paragraph sits there).
  void _jumpToAnchor() {
    if (!mounted || !_controller.hasClients) return;
    final key = _keys[_center];
    final box = key?.currentContext?.findRenderObject();
    final viewport = context.findRenderObject();
    if (box is RenderParagraph && viewport is RenderBox) {
      final geometry = ParagraphGeometry(widget.paragraphs.all[_center], box);
      final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
      final y = top + geometry.lineTop(_anchor);
      if (y.abs() > 0.5) {
        _controller.jumpTo(_controller.offset + y);
        return; // the jump's end reports
      }
    }
    _scheduleReport();
  }

  void _scheduleReport() {
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (!mounted) return;
        final at = firstVisibleOffset();
        if (at == null || at == _reported) return;
        _reported = at;
        widget.onSettled(at);
      })
      ..ensureVisualUpdate();
  }

  /// A new width re-wraps every line: open again from where the reader is.
  void _rewrap(double width) {
    if (_width != null && _width != width) {
      _anchor = _reported ?? _anchor;
      _center = widget.paragraphs.indexOf(_anchor);
      _keys.clear();
      _generation++;
      final old = _controller;
      _controller = ScrollController();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        old.dispose();
        _jumpToAnchor();
      });
    }
    _width = width;
  }

  Widget _paragraph(int i) => ParagraphView(
    text: widget.text,
    paragraph: widget.paragraphs.all[i],
    fontSize: widget.fontSize,
    textKey: _keys.putIfAbsent(i, GlobalKey.new),
  );

  @override
  Widget build(BuildContext context) {
    final count = widget.paragraphs.length;
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context)
          .copyWith(scrollbars: false, overscroll: false),
      child: NotificationListener<ScrollEndNotification>(
        onNotification: (_) {
          _scheduleReport();
          return false;
        },
        child: LayoutBuilder(
          builder: (context, box) {
            _rewrap(box.maxWidth);
            return CustomScrollView(
              key: ValueKey(_generation),
              controller: _controller,
              center: _centerKey,
              slivers: [
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, k) => _paragraph(_center - 1 - k),
                    childCount: _center,
                  ),
                ),
                SliverList(
                  key: _centerKey,
                  delegate: SliverChildBuilderDelegate(
                    (_, k) => _paragraph(_center + k),
                    childCount: count - _center,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
