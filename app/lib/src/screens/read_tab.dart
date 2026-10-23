import 'dart:async';
import 'dart:typed_data';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/local_session.dart';
import 'package:book_guard_app/src/page_reader.dart';
import 'package:book_guard_app/src/screens/ebook_entry.dart';
import 'package:book_guard_app/src/screens/photo_delivery.dart';
import 'package:book_guard_app/src/screens/photo_history.dart';
import 'package:book_guard_app/src/screens/read_support.dart';
import 'package:book_guard_app/src/screens/session_buttons.dart';
import 'package:book_guard_app/src/screens/summary_panel.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

export 'package:book_guard_app/src/screens/read_support.dart'
    show PhotoSource, pickPhoto;

/// The reading session itself: start / stop / check photos, then the summary.
///
/// Works with the PC off: the phone reads the page number itself, keeps
/// the photo, names the check page as the PC will, and queues everything.
class ReadTab extends StatefulWidget {
  /// Creates the tab.
  const new({
    required this.api,
    required this.state,
    required this.desktop,
    required this.onChanged,
    super.key,
    this.photoSource = pickPhoto,
    this.reader,
    this.local,
    this.journal = const [],
    this.captures = const [],
  });

  /// The PC.
  final GuardApi api;

  /// The latest snapshot (possibly the cached one).
  final GuardState? state;

  /// Desktop: pick photo files instead of opening a camera.
  final bool desktop;

  /// Refetch the snapshot after an action.
  final Future<void> Function() onChanged;

  /// Where photos come from; replaced in tests.
  final PhotoSource photoSource;

  /// On-device page reading; null on the desktop.
  final PageReader? reader;

  /// What the phone knows that the snapshot does not show yet.
  final LocalView? local;

  /// Every photo taken on this device.
  final List<JournalEntry> journal;

  /// Photos back from the camera that were never sent.
  final List<Capture> captures;

  @override
  State<ReadTab> createState() => _ReadTabState();
}

class _ReadTabState extends State<ReadTab> {
  bool _busy = false;
  String? _photoNote;

  int? get _openStart {
    final local = widget.local;
    return local != null ? local.openStart : widget.state?.openStart;
  }

  List<SessionInfo> get _checks =>
      widget.local?.needCheck ?? widget.state?.needCheck ?? const [];

  List<SessionInfo> get _quiz =>
      widget.local?.needSummary ?? widget.state?.needSummary ?? const [];

  Future<void> _run(String stage, Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on Exception catch (error) {
      unawaited(widget.api.errors.log(stage, '$error'));
      if (mounted) showError(context, '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
      unawaited(widget.onChanged());
    }
  }

  /// Takes a photo, stores it on the device at once, then reads it, lets
  /// the reader confirm or box the number and queues it; waits for the
  /// PC's verdict only if the PC is reachable -- a photo must never just
  /// vanish. Every step is a lifecycle event for the PC's log.
  Future<void> _photo(String label) => _run('photo', () async {
    final api = widget.api;
    final id = api.newId();
    await api.captures.launching(id, label);
    await api.errors.event('photo', 'camera', {'attempt': id, 'label': label});
    final file = await widget.photoSource(camera: !widget.desktop);
    if (file == null) {
      await api.captures.landed();
      await api.errors.event('photo', 'no-photo', {'attempt': id});
      return;
    }
    final bytes = await file.readAsBytes();
    final capture = await api.captures.keep(id, label, file.name, bytes);
    await api.errors.event('photo', 'captured', {
      'attempt': id,
      'file': file.name,
      'bytes': bytes.length,
    });
    await _send(capture, bytes);
  });

  /// Finishes a photo stored earlier and never sent.
  Future<void> _resume(Capture capture) => _run('photo', () async {
    final bytes = await widget.api.captures.bytes(capture);
    if (bytes == null) return; // sent meanwhile
    await widget.api.errors.event('photo', 'resumed', {'attempt': capture.id});
    await _send(capture, bytes);
  });

  Future<void> _send(Capture capture, Uint8List bytes) async {
    final api = widget.api;
    final attempt = {'attempt': capture.id};
    if (!mounted) return;
    if (widget.reader != null) _note('Reading the page number...');
    final review = await reviewPhoto(
      context,
      reader: widget.reader,
      bytes: bytes,
      fileName: capture.fileName,
      pageContext: pageContextFor(
        capture.label,
        widget.state,
        widget.journal,
        _openStart,
      ),
      errors: api.errors,
      attempt: capture.id,
    );
    if (review == null) {
      // Back, or the screen went away: the photo stays on the phone.
      await api.errors.event('photo', 'review-left', attempt);
      return _note(
        'Photo kept on the phone - finish it with the button above.',
      );
    }
    if (review.retake) {
      await api.captures.drop(capture);
      await api.errors.event('photo', 'discarded', attempt);
      return _note('Photo discarded - take it again.');
    }
    await api.errors.event('photo', 'reviewed', {
      ...attempt,
      'page': review.page,
      'boxed': review.box != null,
    });
    final name = await api.queuePhoto(
      capture.label,
      capture.fileName,
      bytes,
      page: review.page,
      box: review.box,
    );
    await api.captures.drop(capture);
    await api.errors.event('photo', 'queued', {...attempt, 'photo': name});
    final sent = await deliverPhoto(
      api,
      name: name,
      attempt: capture.id,
      page: review.page,
      onSent: _note,
    );
    if (!mounted) return;
    _note(sent.note);
    switch (sent.good) {
      case true:
        showToast(context, sent.note);
      case false:
        showError(context, sent.note);
      case null:
        break;
    }
  }

  void _note(String text) {
    if (mounted) setState(() => _photoNote = text);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final (checks, quiz, reading) = (_checks, _quiz, _openStart);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (_busy) const LinearProgressIndicator(),
        SessionPrompt(reading: reading, waiting: widget.local?.waiting ?? 0),
        const SizedBox(height: AppSpacing.md),
        SessionButtons(
          reading: reading,
          desktop: widget.desktop,
          captures: widget.captures,
          checks: checks,
          onPhoto: _busy ? null : _photo,
          onResume: _busy ? null : _resume,
        ),
        EbookEntry(
          api: widget.api,
          state: state,
          paperStart: reading,
          onChanged: widget.onChanged,
        ),
        if (_photoNote case final note?) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(note),
        ],
        if (quiz.isNotEmpty)
          SummaryPanel(
            key: ValueKey(quiz.first.id),
            api: widget.api,
            session: quiz.first,
            state: state,
            pace: state?.pace,
            onChanged: widget.onChanged,
          ),
        PhotoHistory(
          api: widget.api,
          state: state,
          journal: widget.journal,
          reader: widget.reader,
          onChanged: widget.onChanged,
        ),
      ],
    );
  }
}
