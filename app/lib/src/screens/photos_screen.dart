import 'dart:async';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/journal.dart';
import 'package:book_guard_app/src/page_reader.dart';
import 'package:book_guard_app/src/screens/failed_photos.dart';
import 'package:book_guard_app/src/screens/photo_history.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// What the photos screen shows; the Read tab keeps it current.
typedef PhotoFeed = ({GuardState? state, List<JournalEntry> journal});

/// The photos glyph on the Read tab: opens [PhotosScreen], kept current as
/// the snapshot refreshes, and carries a dot while a failed photo is still
/// shown there (dismissed ones excluded, as the failed strip hides them).
class PhotosButton extends StatefulWidget {
  /// Creates the button.
  const new({
    required this.api,
    required this.state,
    required this.journal,
    required this.onChanged,
    super.key,
    this.reader,
  });

  /// The PC.
  final GuardApi api;

  /// The latest snapshot (possibly the cached one).
  final GuardState? state;

  /// Every photo taken on this device.
  final List<JournalEntry> journal;

  /// On-device page reading; null on the desktop.
  final PageReader? reader;

  /// Refetch the snapshot after an action.
  final Future<void> Function() onChanged;

  @override
  State<PhotosButton> createState() => _PhotosButtonState();
}

class _PhotosButtonState extends State<PhotosButton> {
  Set<String> _dismissed = const {};
  late final _feed = ValueNotifier<PhotoFeed>(_now);

  PhotoFeed get _now => (state: widget.state, journal: widget.journal);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(PhotosButton old) {
    super.didUpdateWidget(old);
    // The open screen listens; it must not be marked dirty mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _feed.value = _now;
    });
  }

  @override
  void dispose() {
    _feed.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final dismissed = await widget.api.dismissedPhotos();
    if (mounted) setState(() => _dismissed = dismissed);
  }

  Future<void> _open() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhotosScreen(
          api: widget.api,
          feed: _feed,
          reader: widget.reader,
          onChanged: widget.onChanged,
        ),
      ),
    );
    // Back: a card may have been dismissed there.
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    const photos = Icon(Icons.photo_library_outlined, semanticLabel: 'photos');
    final dot = failedPhotos(
      widget.state,
      widget.journal,
    ).any((f) => !_dismissed.contains(f.entry.name));
    return IconButton(
      key: const ValueKey('read-photos'),
      icon: dot ? const Badge(child: photos) : photos,
      onPressed: () => unawaited(_open()),
    );
  }
}

/// Every photo on its own screen: the failed strip, then the paged grid.
class PhotosScreen extends StatelessWidget {
  /// Creates the screen.
  const new({
    required this.api,
    required this.feed,
    required this.onChanged,
    super.key,
    this.reader,
  });

  /// The PC.
  final GuardApi api;

  /// The snapshot and journal, refreshed while the screen is open.
  final ValueListenable<PhotoFeed> feed;

  /// On-device page reading; null on the desktop.
  final PageReader? reader;

  /// Refetch the snapshot after an action.
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) => Scaffold(
    // A glyph without the stock "Back" tooltip: nothing here is a word.
    appBar: AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, semanticLabel: 'back'),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
    ),
    body: SafeArea(
      child: ValueListenableBuilder<PhotoFeed>(
        valueListenable: feed,
        builder: (context, now, _) => PhotoHistory(
          api: api,
          state: now.state,
          journal: now.journal,
          reader: reader,
          onChanged: onChanged,
        ),
      ),
    ),
  );
}
