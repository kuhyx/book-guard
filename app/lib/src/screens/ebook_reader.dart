import 'dart:async';

import 'package:book_guard_app/src/ebook_store.dart';
import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/screens/ebook_pages.dart';
import 'package:book_guard_app/src/screens/ebook_reader_bar.dart';
import 'package:flutter/material.dart';

export 'package:book_guard_app/src/screens/ebook_pages.dart' show screenStarts;

/// The book, read in the app: its text a screen at a time, the estimated
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
    this.screenChars = 2000,
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

  /// Characters per screen.
  final int screenChars;

  @override
  State<EbookReaderScreen> createState() => _EbookReaderScreenState();
}

class _EbookReaderScreenState extends State<EbookReaderScreen> {
  late final List<int> _starts = screenStarts(
    widget.ebook.text,
    widget.screenChars,
  );
  PageController? _pages;
  int _index = 0;
  double _font = EbookStore.defaultFontSize;
  ReadingStart? _start;

  EbookMap get _map => widget.ebook.map;
  String get _isbn => _map.isbn;
  int get _offset => _starts[_index];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _pages?.dispose();
    super.dispose();
  }

  int _screenOf(int offset) {
    var i = 0;
    while (i + 1 < _starts.length && _starts[i + 1] <= offset) {
      i++;
    }
    return i;
  }

  /// The reader's own place, unless the paper reading is further on.
  int _resume(int? saved) {
    final latest = widget.latestPage;
    if (latest != null && (saved == null || _map.pageAt(saved) < latest)) {
      final i = _starts.indexWhere((s) => _map.pageAt(s) >= latest);
      return i < 0 ? _starts.length - 1 : i;
    }
    return _screenOf(saved ?? _map.start);
  }

  Future<void> _load() async {
    final api = widget.api;
    final saved = await api.readingPosition(_isbn);
    final font = await api.fontSize();
    final start = await api.readingStart(_isbn);
    if (!mounted) return;
    final index = _resume(saved);
    setState(() {
      _index = index;
      _font = font;
      _start = start;
      _pages = PageController(initialPage: index);
    });
  }

  void _turned(int index) {
    setState(() => _index = index);
    unawaited(widget.api.savePosition(_isbn, _starts[index]));
  }

  Future<void> _go(int delta) async {
    final target = (_index + delta).clamp(0, _starts.length - 1);
    await _pages?.animateToPage(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
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
    final pages = _pages;
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
      body: pages == null
          ? const Center(child: CircularProgressIndicator())
          : PageView.builder(
              controller: pages,
              itemCount: _starts.length,
              onPageChanged: _turned,
              itemBuilder: (_, index) => EbookScreenText(
                text: widget.ebook.text,
                from: _starts[index],
                to: index + 1 < _starts.length
                    ? _starts[index + 1]
                    : widget.ebook.text.length,
                fontSize: _font,
              ),
            ),
      bottomNavigationBar: pages == null
          ? null
          : ReaderBar(
              map: _map,
              offset: _offset,
              start: _start,
              paperStart: widget.paperStart,
              onPrevious: _index > 0 ? () => _go(-1) : null,
              onNext: _index + 1 < _starts.length ? () => _go(1) : null,
              onStart: _begin,
              onStop: _stop,
            ),
    );
  }
}
