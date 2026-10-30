import 'dart:async';

import 'package:book_guard_app/src/ebook_paragraphs.dart';
import 'package:book_guard_app/src/ebook_store.dart';
import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/screens/ebook_reader_input.dart';
import 'package:book_guard_app/src/screens/ebook_scroll.dart';
import 'package:book_guard_app/src/screens/ebook_session.dart';
import 'package:book_guard_app/src/screens/ebook_words.dart';
import 'package:book_guard_app/src/screens/reading_style.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The book, read in the app: the whole screen is its text, scrolled like
/// a long web post (see [ReaderInput] for the invisible controls).
///
/// Opening it is starting to read: once the place has loaded, a session
/// starts there unless one from the last 6 h is still running (the app
/// was killed mid-read). Every way out -- the swipe, system back, Escape
/// -- stops it without a question and pops with the [AppSession] when the
/// PC will count it. The time counted is plain wall-clock from the start.
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

  /// The book's title (not shown: the screen is the text).
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
  /// Split once per book, however often the reader opens.
  static final _split = Expando<BookParagraphs>();

  final _scroll = GlobalKey<BookScrollState>();
  late final BookParagraphs _paragraphs = _split[widget.ebook] ??=
      BookParagraphs.split(_text);

  /// Where the reader opened; null until the position is loaded.
  int? _opened;

  /// The first visible character, as last settled.
  int _offset = 0;
  double _font = ReadingStyle.phoneFont;
  ReadingStart? _start;
  Future<void>? _starting;
  bool _exiting = false;

  EbookMap get _map => widget.ebook.map;
  String get _text => widget.ebook.text;
  String get _isbn => _map.isbn;

  @override
  void initState() {
    super.initState();
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
    unawaited(_starting = _load());
  }

  @override
  void dispose() {
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
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
    final font = await api.savedFontSize();
    var start = await api.readingStart(_isbn);
    if (!mounted || _exiting) return;
    final at = _resume(saved);
    setState(() {
      _opened = _offset = at;
      _font = ReadingStyle.sizeFor(font, MediaQuery.sizeOf(context).width);
    });
    final now = widget.clock();
    if (start != null && isStale(start, now)) {
      await api.cancelReading(_isbn);
      start = null;
    }
    if (start == null) {
      start = ReadingStart(
        id: api.newId(),
        isbn: _isbn,
        offset: at,
        startedAt: now,
        textSha: _map.textSha,
      );
      await api.startReading(start);
      final paper = widget.paperStart;
      if (paper != null && mounted) {
        showToast(
          context,
          'Reading here closed the open start photo of p. $paper: take a '
          'new start photo when you go back to paper.',
        );
      }
    }
    _start = start;
  }

  void _settled(int offset) {
    _offset = offset;
    unawaited(widget.api.savePosition(_isbn, offset));
  }

  /// The one way out: stop (or drop) the session, then pop.
  Future<void> _exit() async {
    if (_exiting) return;
    _exiting = true;
    await _starting;
    if (!mounted) return;
    final api = widget.api;
    final opened = _opened != null;
    final offset = _scroll.currentState?.firstVisibleOffset() ?? _offset;
    if (opened) await api.savePosition(_isbn, offset);
    final start = _start;
    final now = widget.clock();
    AppSession? done;
    switch (judgeExit(start, offset, _map, now)) {
      case ReaderExit.none:
        break;
      case ReaderExit.underAPage || ReaderExit.tooLong:
        await api.cancelReading(_isbn);
      case ReaderExit.tooFast:
        await api.cancelReading(_isbn);
        if (mounted) showToast(context, 'Too fast to count - not saved');
      case ReaderExit.stop:
        done = await api.stopReading(start!, offset, _map, now);
    }
    if (mounted) Navigator.of(context).pop(done);
  }

  void _page(int direction) => unawaited(_scroll.currentState?.page(direction));

  @override
  Widget build(BuildContext context) {
    final opened = _opened;
    return PopScope<AppSession>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_exit());
      },
      child: Scaffold(
        backgroundColor: ReadingStyle.paper,
        body: ReaderInput(
          onNext: () => _page(1),
          onPrevious: () => _page(-1),
          onExit: () => unawaited(_exit()),
          child: opened == null || _paragraphs.length == 0
              ? const SizedBox.expand()
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      top: ReadingStyle.topPadding,
                      bottom: ReadingStyle.bottomPadding,
                    ),
                    child: BookScroll(
                      key: _scroll,
                      text: _text,
                      paragraphs: _paragraphs,
                      fontSize: _font,
                      anchor: opened,
                      onSettled: _settled,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
