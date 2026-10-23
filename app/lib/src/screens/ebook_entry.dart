import 'dart:async';

import 'package:book_guard_app/src/ebook_store.dart';
import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/ebook_reader.dart';
import 'package:book_guard_app/src/screens/session_times.dart' show hhmm;
import 'package:book_guard_app/src/screens/summary_panel.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// The Read tab's way into in-app reading: "Read in app (≈ p. N)" for the
/// current book once the PC has a page map for it, and the summary box of
/// a session stopped here that the PC does not list yet (offline, or not
/// processed): it can be written at once and goes up through the outbox.
///
/// The book's text and map are downloaded once and kept on the device, so
/// the reader opens with the PC and the network both gone.
class EbookEntry extends StatefulWidget {
  /// Creates the entry.
  const new({
    required this.api,
    required this.state,
    required this.onChanged,
    super.key,
    this.paperStart,
    this.clock = DateTime.now,
  });

  /// The PC and the device store.
  final GuardApi api;

  /// The latest snapshot (possibly the cached one).
  final GuardState? state;

  /// Refetch after a session was stopped.
  final Future<void> Function() onChanged;

  /// The page of a paper start photo still open, if any.
  final int? paperStart;

  /// Now; replaced in tests.
  final DateTime Function() clock;

  @override
  State<EbookEntry> createState() => _EbookEntryState();
}

class _EbookEntryState extends State<EbookEntry> {
  Ebook? _ebook;
  ReadingStart? _running;
  int? _position;
  List<AppSession> _stopped = const [];
  bool _tried = false;
  String _synced = '';

  BookInfo? get _book => widget.state?.book;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(EbookEntry old) {
    super.didUpdateWidget(old);
    // Every refresh squares the stopped sessions with the PC's list (a few
    // small files); the 1 MB text is only re-read when the book or its map
    // changed.
    if (_key(widget.state) != _key(old.state)) {
      unawaited(_load());
    } else if (widget.state != old.state) {
      unawaited(_load(book: false));
    }
  }

  String _key(GuardState? state) =>
      '${state?.book?.isbn}|${state?.book?.ebook?.generatedAt}';

  /// The kept copy at once, then the PC's newer one if there is one (only
  /// with [book]); and the stopped sessions the PC now lists (or refused)
  /// are forgotten.
  Future<void> _load({bool book = true}) async {
    final api = widget.api;
    final info = _book;
    final listed = {
      for (final s in widget.state?.sessions ?? const <SessionInfo>[]) s.id,
    };
    final stopped = <AppSession>[];
    for (final s in await api.appSessions()) {
      if (listed.contains(s.sessionId) || await api.refused(s)) {
        await api.forgetAppSession(s.key);
      } else {
        stopped.add(s);
      }
    }
    final isbn = info?.isbn ?? '';
    var ebook = !book
        ? _ebook
        : isbn.isEmpty
        ? null
        : await api.cachedEbook(isbn);
    final running = isbn.isEmpty ? null : await api.readingStart(isbn);
    final position = isbn.isEmpty ? null : await api.readingPosition(isbn);
    final ref = info?.ebook;
    final key = _key(widget.state);
    if (ref != null && key != _synced) {
      ebook = await api.syncEbook(isbn, ref) ?? ebook;
      _synced = key;
    }
    if (!mounted) return;
    setState(() {
      _ebook = ebook;
      _running = running;
      _position = position;
      _stopped = stopped;
      _tried = true;
    });
  }

  Future<void> _open(Ebook ebook) async {
    final book = _book;
    final done = await Navigator.of(context).push<AppSession>(
      MaterialPageRoute(
        builder: (_) => EbookReaderScreen(
          api: widget.api,
          ebook: ebook,
          title: book?.title ?? '',
          latestPage: book?.latestPage,
          paperStart: widget.paperStart,
          clock: widget.clock,
        ),
      ),
    );
    await _load();
    unawaited(widget.onChanged());
    if (done != null && mounted) {
      showToast(
        context,
        'In-app reading ${done.info.span} saved - write its summary below.',
      );
    }
  }

  /// The page the reader opens on: its own place, or the paper's if later.
  int _openingPage(EbookMap map) {
    final latest = _book?.latestPage;
    final here = map.shownPage(_position ?? map.start);
    return latest != null && latest > here ? latest : here;
  }

  @override
  Widget build(BuildContext context) {
    final book = _book;
    final ebook = _ebook;
    final listed = {
      for (final s in widget.state?.sessions ?? const <SessionInfo>[]) s.id,
    };
    final stopped = [
      for (final s in _stopped)
        if (!listed.contains(s.sessionId)) s,
    ];
    final running = _running;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ebook != null && book != null && ebook.map.isbn == book.isbn)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: FilledButton.tonalIcon(
              onPressed: () => _open(ebook),
              icon: const Icon(Icons.chrome_reader_mode),
              label: Text(
                running == null
                    ? 'Read in app (≈ p. ${_openingPage(ebook.map)})'
                    : 'Continue reading in app (since '
                          '${hhmm(running.startedAt)})',
              ),
            ),
          )
        else if (book?.ebook != null && _tried)
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              'The book for in-app reading downloads when the PC is '
              'reachable.',
            ),
          ),
        for (final s in stopped)
          SummaryPanel(
            key: ValueKey(s.sessionId),
            api: widget.api,
            session: s.info,
            state: widget.state,
            pace: widget.state?.pace,
            onChanged: widget.onChanged,
          ),
      ],
    );
  }
}
