import 'dart:async';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/local_session.dart';
import 'package:book_guard_app/src/page_reader.dart';
import 'package:book_guard_app/src/screens/failed_photos.dart';
import 'package:book_guard_app/src/screens/photo_gallery.dart';
import 'package:book_guard_app/src/screens/read_support.dart';
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

  @override
  State<ReadTab> createState() => _ReadTabState();
}

class _ReadTabState extends State<ReadTab> {
  final _summary = TextEditingController();
  bool _busy = false;
  String? _verdict;
  String? _photoNote;
  bool? _passed;

  @override
  void dispose() {
    _summary.dispose();
    super.dispose();
  }

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

  /// Reads the photo on the device, lets the reader confirm or box the
  /// number, then queues it; waits for the PC's verdict only if the PC
  /// is reachable -- a photo must never just vanish.
  Future<void> _photo(String label) => _run('photo', () async {
    final file = await widget.photoSource(camera: !widget.desktop);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    if (widget.reader != null) _note('Reading the page number...');
    final review = await reviewPhoto(
      context,
      reader: widget.reader,
      bytes: bytes,
      fileName: file.name,
      pageContext: pageContextFor(
        label,
        widget.state,
        widget.journal,
        _openStart,
      ),
      errors: widget.api.errors,
    );
    if (review == null) return _note('Photo discarded - take it again.');
    final name = await widget.api.queuePhoto(
      label,
      file.name,
      bytes,
      page: review.page,
      box: review.box,
    );
    final seen = review.page == null ? '' : ' (p. ${review.page})';
    if (await widget.api.flush() > 0) {
      return _note(
        'Saved on the phone$seen - it goes to the PC as soon as the PC is '
        'reachable.',
      );
    }
    _note('Uploaded$seen - waiting for the PC...');
    final read = await widget.api.waitForPhoto(name);
    if (!mounted) return;
    final note = photoVerdict(read);
    _note(note);
    if (read != null && read.accepted) {
      showToast(context, note);
    } else {
      if (read != null) {
        unawaited(
          widget.api.errors.log('photo', read.reason, {
            'photo': name,
            'phone_page': review.page,
          }),
        );
      }
      showError(context, note);
    }
  });

  void _note(String text) {
    if (mounted) setState(() => _photoNote = text);
  }

  Future<void> _submit(SessionInfo session) => _run('summary', () async {
    setState(() {
      _verdict = 'Grading - this takes up to a minute...';
      _passed = null;
    });
    final response = await widget.api.sendQueued('summary', {
      'session_id': session.id,
      'summary': _summary.text.trim(),
    }, 'Summary for p. ${session.startPage}-${session.endPage}');
    if (!mounted) return;
    setState(() {
      _verdict = response.message;
      _passed = response.passed;
    });
    // Passed, or queued on the phone: either way the text is safe.
    if (response.passed ?? response.ok) _summary.clear();
  });

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final (checks, quiz, reading, verdict) = (
      _checks,
      _quiz,
      _openStart,
      _verdict,
    );
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (_busy) const LinearProgressIndicator(),
        SessionPrompt(reading: reading, waiting: widget.local?.waiting ?? 0),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () => _photo(reading == null ? 'start' : 'stop'),
              icon: Icon(
                widget.desktop ? Icons.upload_file : Icons.photo_camera,
              ),
              label: Text(reading == null ? 'Start reading' : 'Stop reading'),
            ),
            for (final s in checks)
              FilledButton.tonalIcon(
                onPressed: _busy ? null : () => _photo('check${s.checkPage}'),
                icon: const Icon(Icons.fact_check),
                label: Text('Photograph page ${s.checkPage}'),
              ),
          ],
        ),
        if (_photoNote case final note?) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(note),
        ],
        if (quiz.isNotEmpty)
          SummarySection(
            session: quiz.first,
            controller: _summary,
            grader: graderNote(state),
            onSubmit: _busy ? null : () => _submit(quiz.first),
          ),
        if (verdict != null) VerdictText(verdict, passed: _passed),
        FailedPhotos(
          api: widget.api,
          state: state,
          journal: widget.journal,
          reader: widget.reader,
          onChanged: widget.onChanged,
        ),
        if (state != null && state.photos.isNotEmpty) ...[
          const SectionHeader('Your photos'),
          PhotoGallery(api: widget.api, photos: state.photos),
        ],
      ],
    );
  }
}
