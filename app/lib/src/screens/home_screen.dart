import 'dart:async';

import 'package:book_guard_app/src/dav_client.dart';
import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/local_session.dart';
import 'package:book_guard_app/src/page_reader.dart';
import 'package:book_guard_app/src/screens/book_tab.dart';
import 'package:book_guard_app/src/screens/read_tab.dart';
import 'package:book_guard_app/src/screens/status_tab.dart';
import 'package:book_guard_app/src/summary_store.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Three tabs over one live snapshot: Status, Read, Book.
///
/// The snapshot is refetched every [refreshEvery] and after every action,
/// because the PC changes it on its own (a photo read, a check page named).
/// Each refresh first sends whatever the outbox holds. With the PC out of
/// reach the last snapshot stays on screen, overlaid with the photos taken
/// since, and the app keeps working.
class HomeScreen extends StatefulWidget {
  /// Creates the screen.
  const new({
    required this.api,
    required this.desktop,
    super.key,
    this.settingsPage,
    this.refreshEvery = const Duration(seconds: 10),
    this.reader,
  });

  /// On-device page reading; null on the desktop.
  final PageReader? reader;

  /// The PC, through the share.
  final GuardApi api;

  /// Whether this is the desktop build (file picker instead of camera).
  final bool desktop;

  /// Builds the connection settings page; null on the desktop.
  final Widget Function()? settingsPage;

  /// How often to refetch `state.json`.
  final Duration refreshEvery;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  GuardState? _state;
  Object? _error;
  int _tab = 0;
  Timer? _timer;
  List<JournalEntry> _journal = const [];
  int _waiting = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
    _timer = Timer.periodic(widget.refreshEvery, (_) => refresh());
  }

  /// Shows the last snapshot at once, then asks the PC.
  Future<void> _start() async {
    final cached = await widget.api.cachedState();
    final journal = await widget.api.journal.load();
    if (mounted && _state == null) {
      setState(() {
        _state = cached;
        _journal = journal;
      });
    }
    await refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Sends what waits, refetches the snapshot, picks up late answers;
  /// errors are shown, never thrown.
  Future<void> refresh() async {
    final api = widget.api;
    Object? error;
    GuardState? state;
    var answers = <LateAnswer>[];
    final waiting = await api.flush();
    try {
      state = await api.fetchState();
      answers = await api.collectAnswers();
    } on Exception catch (e) {
      error = e;
      state = _state ?? await api.cachedState();
    }
    for (final s in state?.sessions ?? const <SessionInfo>[]) {
      await api.settleGrading(s);
    }
    final journal = await api.journal.load();
    if (!mounted) return;
    setState(() {
      _state = state;
      _error = error == null ? null : _explain(error, state, waiting);
      _journal = journal;
      _waiting = waiting;
    });
    if (answers.isEmpty) return;
    // One message: a second snackbar would hide the first.
    final text = [for (final a in answers) '${a.what}: ${a.response.message}']
        .join('\n');
    answers.every((a) => a.response.ok && (a.response.passed ?? true))
        ? showToast(context, text)
        : showError(context, text);
  }

  /// An unreachable PC is a mode, not an error: say what still works.
  Object _explain(Object error, GuardState? state, int waiting) {
    if (error is! DavException || error.status != 0) return error;
    final at = state?.generatedAt?.toLocal();
    final when = at == null
        ? ''
        : ' Showing the state from ${at.day}.${at.month} '
              '${at.hour.toString().padLeft(2, '0')}:'
              '${at.minute.toString().padLeft(2, '0')}.';
    final queued = waiting == 0
        ? ''
        : ' $waiting item(s) wait on the phone and go up automatically.';
    return 'Working offline - the PC cannot be reached.$when$queued '
        'Photos, page numbers and summaries all work offline.';
  }

  Future<void> _copyDiagnostics() async {
    final text = await widget.api.errors.diagnostics();
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      showToast(context, 'Diagnostics copied - paste them to Claude.');
    }
  }

  void _openSettings() {
    final page = widget.settingsPage;
    if (page == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page()));
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final local = localView(state, _journal);
    final tabs = [
      StatusTab(
        state: state,
        error: _error,
        onRefresh: refresh,
        api: widget.api,
      ),
      ReadTab(
        api: widget.api,
        state: state,
        desktop: widget.desktop,
        onChanged: refresh,
        reader: widget.reader,
        local: local,
        journal: _journal,
      ),
      BookTab(
        api: widget.api,
        state: state,
        onChanged: refresh,
        desktop: widget.desktop,
      ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Book Guard'),
        actions: [
          IconButton(
            tooltip: 'Copy diagnostics',
            icon: Badge(
              isLabelVisible: _waiting > 0,
              label: Text('$_waiting'),
              child: const Icon(Icons.bug_report_outlined),
            ),
            onPressed: _copyDiagnostics,
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: refresh,
          ),
          if (widget.settingsPage != null)
            IconButton(
              tooltip: 'Connection',
              icon: const Icon(Icons.settings),
              onPressed: _openSettings,
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            // One readable column on a wide desktop, full width on a phone.
            constraints: const BoxConstraints(maxWidth: 640),
            child: tabs[_tab],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.insights),
            label: 'Status',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible:
                  (local?.needCheck ?? state?.needCheck ?? const []).length +
                      (local?.needSummary ?? state?.needSummary ?? const [])
                          .length >
                  0,
              child: const Icon(Icons.menu_book),
            ),
            label: 'Read',
          ),
          const NavigationDestination(
            icon: Icon(Icons.library_books),
            label: 'Book',
          ),
        ],
      ),
    );
  }
}
