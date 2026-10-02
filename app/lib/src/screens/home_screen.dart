import 'dart:async';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/book_tab.dart';
import 'package:book_guard_app/src/screens/read_tab.dart';
import 'package:book_guard_app/src/screens/status_tab.dart';
import 'package:flutter/material.dart';

/// Three tabs over one live snapshot: Status, Read, Book.
///
/// The snapshot is refetched every [refreshEvery] and after every action,
/// because the PC changes it on its own (a photo read, a check page named).
class HomeScreen extends StatefulWidget {
  /// Creates the screen.
  const new({
    required this.api,
    required this.desktop,
    super.key,
    this.settingsPage,
    this.refreshEvery = const Duration(seconds: 10),
  });

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

  @override
  void initState() {
    super.initState();
    unawaited(refresh());
    _timer = Timer.periodic(widget.refreshEvery, (_) => refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Refetches the snapshot; errors are shown, never thrown.
  Future<void> refresh() async {
    try {
      final state = await widget.api.fetchState();
      if (mounted) {
        setState(() {
          _state = state;
          _error = null;
        });
      }
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error);
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
                  (state?.needCheck.length ?? 0) +
                      (state?.needSummary.length ?? 0) >
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
