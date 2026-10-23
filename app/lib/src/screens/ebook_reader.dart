import 'dart:async';

import 'package:book_guard_app/src/ebook_store.dart';
import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/screens/ebook_fit.dart';
import 'package:book_guard_app/src/screens/ebook_pages.dart';
import 'package:book_guard_app/src/screens/ebook_reader_bar.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// The book, read in the app: its text a screen at a time (measured: the
/// next screen starts on the first line that did not fit), the estimated
/// paper page ("≈ p. N"), and Start/Stop for a session the PC credits in
/// paper pages. The Start tap is kept on the device at once; the time
/// counted is plain wall-clock from that tap to Stop, whatever the app did
/// in between. Pops with the [AppSession] when one was stopped.
class EbookReaderScreen extends StatefulWidget {
  /// Creates the reader.
  const new({
    required this.api,
    required this.ebook,
    required this.title,
    super.key,
    this.latestPage,
    this.paperStart,
    this.clock = DateTime.now,
  });

  /// The device store and the outbox.
  final GuardApi api;

  /// The downloaded book.
  final Ebook ebook;

  /// The book's title.
  final String title;

  /// The newest page read (on paper or here): where to open when the
  /// reader's own position is behind it.
  final int? latestPage;

  /// The page of a paper start photo still waiting for its stop photo.
  /// Starting here closes it on the PC: the next photo is a new start.
  final int? paperStart;

  /// Now; replaced in tests.
  final DateTime Function() clock;

  @override
  State<EbookReaderScreen> createState() => _EbookReaderScreenState();
}

class _EbookReaderScreenState extends State<EbookReaderScreen> {
  /// The first visible character; null until the position is loaded.
  int? _at;

  /// The screen starts paged forward from, to go back through exactly.
  final List<int> _history = [];
  final Map<int, int> _ends = {};
  ScreenFit? _fit;
  bool _atEnd = false;
  double _font = EbookStore.defaultFontSize;
  ReadingStart? _start;

  EbookMap get _map => widget.ebook.map;
  String get _text => widget.ebook.text;
  String get _isbn => _map.isbn;
  int get _offset => _at ?? 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// The reader's own place, unless the paper reading is further on.
  int _resume(int? saved) {
    final latest = widget.latestPage;
    final paper =
        latest != null && (saved == null || _map.pageAt(saved) < latest);
    return wordAfter(_text, paper ? _map.startOf(latest) : saved ?? _map.start);
  }

  Future<void> _load() async {
    final api = widget.api;
    final saved = await api.readingPosition(_isbn);
    final font = await api.fontSize();
    final start = await api.readingStart(_isbn);
    if (!mounted) return;
    setState(() {
      _at = _resume(saved);
      _font = font;
      _start = start;
    });
  }

  int _endOf(ScreenFit fit, int from) => _ends[from] ??= fit.endOf(_text, from);

  void _go(int delta) {
    final fit = _fit;
    if (fit == null) return;
    final int to;
    if (delta > 0) {
      to = _endOf(fit, _offset);
      if (to >= _text.length) return;
      _history.add(_offset);
    } else {
      if (_offset <= firstVisible(_text, 0)) return;
      to = _history.isNotEmpty
          ? _history.removeLast()
          : fit.startBefore(_text, _offset);
    }
    setState(() => _at = to);
    unawaited(widget.api.savePosition(_isbn, to));
  }

  /// The screen at the current offset, measured for [box]. A new font,
  /// screen size or bar height re-fits from the same first character.
  Widget _screen(BuildContext context, BoxConstraints box) {
    final fit = ScreenFit.of(context, box, _font, AppSpacing.md);
    if (fit != _fit) {
      _fit = fit;
      _history.clear();
      _ends.clear();
    }
    if (_offset >= _text.length && _text.isNotEmpty) {
      _at = fit.startBefore(_text, _text.length); // opened past the end
    }
    final end = _endOf(fit, _offset);
    final atEnd = end >= _text.length;
    if (atEnd != _atEnd) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _atEnd = atEnd);
      });
    }
    return GestureDetector(
      onHorizontalDragEnd: (drag) {
        final v = drag.primaryVelocity ?? 0;
        if (v != 0) _go(v < 0 ? 1 : -1);
      },
      child: EbookScreenText(text: _text, from: _offset, to: end, fit: fit),
    );
  }

  Future<void> _resize(double delta) async {
    final size = (_font + delta).clamp(12.0, 40.0);
    setState(() => _font = size);
    await widget.api.saveFontSize(size);
  }

  Future<void> _begin() async {
    final start = ReadingStart(
      id: widget.api.newId(),
      isbn: _isbn,
      offset: _offset,
      startedAt: widget.clock(),
      textSha: _map.textSha,
    );
    await widget.api.startReading(start);
    if (mounted) setState(() => _start = start);
  }

  Future<void> _discard() async {
    await widget.api.cancelReading(_isbn);
    if (mounted) setState(() => _start = null);
  }

  Future<void> _stop() async {
    final start = _start;
    if (start == null) return;
    final now = widget.clock();
    final elapsed = now.difference(start.startedAt);
    final pages = _map.pageAt(_offset) - _map.pageAt(start.offset);
    if (elapsed > maxSession) {
      final discard = await askYesNo(
        context,
        'You started more than 6 h ago: that session cannot count. '
            'Discard it and start again here?',
        'Discard',
        'Not now',
      );
      if (discard ?? false) await _discard();
      return;
    }
    if (pages <= 0) {
      final discard = await askYesNo(
        context,
        'Less than a page since Start - nothing to credit yet.',
        'Discard',
        'Keep reading',
      );
      if (discard ?? false) await _discard();
      return;
    }
    if (elapsed.inSeconds < pages * minSecondsPerPage) {
      final stop = await askYesNo(
        context,
        'That is under 50 s a page: the PC will not count it.',
        'Stop anyway',
        'Keep reading',
      );
      if (!(stop ?? false)) return;
    }
    final done = await widget.api.stopReading(start, _offset, _map, now);
    if (mounted) Navigator.of(context).pop(done);
  }

  @override
  Widget build(BuildContext context) {
    final loading = _at == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Smaller text',
            icon: const Icon(Icons.text_decrease),
            onPressed: () => _resize(-2),
          ),
          IconButton(
            tooltip: 'Larger text',
            icon: const Icon(Icons.text_increase),
            onPressed: () => _resize(2),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(builder: _screen),
      bottomNavigationBar: loading
          ? null
          : ReaderBar(
              map: _map,
              offset: _offset,
              start: _start,
              paperStart: widget.paperStart,
              onPrevious: _offset > firstVisible(_text, 0)
                  ? () => _go(-1)
                  : null,
              onNext: _atEnd ? null : () => _go(1),
              onStart: _begin,
              onStop: _stop,
            ),
    );
  }
}
