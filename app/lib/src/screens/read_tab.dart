import 'dart:async';
import 'dart:typed_data';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/local_session.dart';
import 'package:book_guard_app/src/next_step.dart';
import 'package:book_guard_app/src/page_reader.dart';
import 'package:book_guard_app/src/screens/photo_status.dart';
import 'package:book_guard_app/src/screens/photos_screen.dart';
import 'package:book_guard_app/src/screens/read_pages.dart';
import 'package:book_guard_app/src/screens/read_support.dart';
import 'package:book_guard_app/src/screens/send_capture.dart';
import 'package:book_guard_app/src/screens/session_buttons.dart';
import 'package:book_guard_app/src/ui/cues.dart';
import 'package:material_ui/material_ui.dart';

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
    this.grading = const {},
    this.clock = DateTime.now,
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

  /// Sessions whose summary is out with the grader: a sent summary is done
  /// for "one session at a time", so the next start is offered meanwhile.
  final Set<String> grading;

  /// Now; replaced in tests.
  final DateTime Function() clock;

  @override
  State<ReadTab> createState() => _ReadTabState();
}

class _ReadTabState extends State<ReadTab> {
  bool _busy = false;
  PhotoStatus? _photoStatus;

  int? get _openStart {
    final local = widget.local;
    return local != null ? local.openStart : widget.state?.openStart;
  }

  List<SessionInfo> get _quiz => [
    for (final s
        in widget.local?.needSummary ??
            widget.state?.needSummary ??
            const <SessionInfo>[])
      if (!widget.grading.contains(s.id)) s,
  ];

  Future<void> _run(String stage, Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on Exception catch (error) {
      unawaited(widget.api.errors.log(stage, '$error'));
      if (mounted) {
        showCue(
          context,
          const Cue(CueKind.error, semanticLabel: 'photo step failed'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      unawaited(widget.onChanged());
    }
  }

  /// Takes a photo, stores it on the device at once, then reviews and
  /// queues it ([sendCapture]) -- a photo must never just vanish.
  Future<void> _photo(String label) => _run('photo', () async {
    // Before any await: the review goes on the root navigator even when
    // this tab is gone by the time the photo is read.
    final navigator = Navigator.of(context, rootNavigator: true);
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
    await _send(navigator, capture, bytes);
  });

  /// Finishes a photo stored earlier and never sent.
  Future<void> _resume(Capture capture) => _run('photo', () async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final bytes = await widget.api.captures.bytes(capture);
    if (bytes == null) return; // sent meanwhile
    await widget.api.errors.event('photo', 'resumed', {'attempt': capture.id});
    await _send(navigator, capture, bytes);
  });

  Future<void> _send(
    NavigatorState navigator,
    Capture capture,
    Uint8List bytes,
  ) => sendCapture(
    api: widget.api,
    navigator: navigator,
    capture: capture,
    bytes: bytes,
    reader: widget.reader,
    pageContext: pageContextFor(
      capture.label,
      widget.state,
      widget.journal,
      _openStart,
    ),
    isbn: widget.state?.book?.isbn,
    show: _show,
    onDelivered: widget.onChanged,
  );

  void _show(PhotoStatus status) {
    if (mounted) setState(() => _photoStatus = status);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: PhotosButton(
            api: widget.api,
            state: widget.state,
            journal: widget.journal,
            reader: widget.reader,
            onChanged: widget.onChanged,
          ),
        ),
        Expanded(child: _session(context)),
      ],
    );
  }

  Widget _session(BuildContext context) {
    // One session at a time: the oldest unfinished session's one step.
    final step = nextStep(
      openStart: _openStart,
      quiz: _quiz,
      captures: widget.captures,
      now: widget.clock(),
    );
    return ReadSessionPage(
      api: widget.api,
      state: widget.state,
      waiting: widget.local?.waiting ?? 0,
      reading: _openStart,
      quiz: [if (step.kind == StepKind.summary) ?step.session],
      ebook: step.kind == StepKind.start,
      status: _photoStatus,
      onChanged: widget.onChanged,
      buttons: SessionButtons(
        step: step,
        busy: _busy,
        reading: _openStart,
        desktop: widget.desktop,
        onPhoto: _photo,
        onResume: _resume,
      ),
    );
  }
}
