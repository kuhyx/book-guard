import 'dart:async';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/grader_note.dart';
import 'package:book_guard_app/src/screens/session_times.dart';
import 'package:book_guard_app/src/screens/summary_section.dart';
import 'package:book_guard_app/src/screens/summary_verdict.dart';
import 'package:book_guard_app/src/summary_store.dart';
import 'package:book_guard_app/src/ui/cues.dart';
import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

/// The summary for [session]: typed text kept as a draft, locked while the
/// grader has it, and still "with the grader" after leaving the tab -- the
/// request is already queued, and the verdict arrives as a message.
///
/// A failure unlocks the box with the text kept and the grader's feedback
/// above it: rewrite and send again, as many times as it takes.
class SummaryPanel extends StatefulWidget {
  /// Creates the panel.
  const new({
    required this.api,
    required this.session,
    required this.onChanged,
    super.key,
    this.state,
    this.pace,
  });

  /// The PC.
  final GuardApi api;

  /// The session waiting for its summary.
  final SessionInfo session;

  /// Refetch after grading.
  final Future<void> Function() onChanged;

  /// The PC's last state: whether Claude is down, for the note beside a
  /// sent summary.
  final GuardState? state;

  /// The month's pace, for the bonus hint (today's requirement).
  final Pace? pace;

  @override
  State<SummaryPanel> createState() => _SummaryPanelState();
}

class _SummaryPanelState extends State<SummaryPanel> {
  final _text = TextEditingController();
  DateTime? _sentAt;
  GuardResponse? _reply;
  bool _busy = false;
  bool _failedSend = false;
  Timer? _expiry;
  DateTime? _lapsed;

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
    _arm();
    _text.addListener(
      () => unawaited(widget.api.saveDraft(widget.session.id, _text.text)),
    );
  }

  Future<void> _restore() async {
    final id = widget.session.id;
    final draft = await widget.api.loadDraft(id);
    final sent = await widget.api.gradingSince(id);
    if (!mounted) return;
    setState(() => _sentAt = sent);
    // The rewrite starts from the failed text when no draft survived.
    if (_text.text.isEmpty) {
      _text.text = draft.isEmpty ? widget.session.retry?.summary ?? '' : draft;
    }
  }

  @override
  void didUpdateWidget(SummaryPanel old) {
    super.didUpdateWidget(old);
    _arm();
    // A verdict that came in later (a queued summary, graded once the PC
    // was back) arrives as a new retry: re-read the marker the home screen
    // just settled, so the box unlocks for the rewrite.
    if (widget.session.retry?.gradedAt != old.session.retry?.gradedAt) {
      unawaited(_resettle());
    }
  }

  Future<void> _resettle() async {
    final sent = await widget.api.gradingSince(widget.session.id);
    if (!mounted) return;
    setState(() {
      _sentAt = sent;
      if (sent == null) _reply = null;
    });
  }

  /// Rebuilds the instant the outage's reset time comes, so the note goes
  /// then even if no fresher state.json arrives.
  void _arm() {
    _expiry?.cancel();
    final until = widget.state?.claudeDownUntil;
    if (until == null) return;
    _expiry = Timer(until.difference(DateTime.now()), () {
      if (mounted) setState(() => _lapsed = until);
    });
  }

  @override
  void dispose() {
    _expiry?.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final session = widget.session;
    await widget.api.markGrading(session.id);
    setState(() {
      _sentAt = DateTime.now();
      _busy = true;
      _failedSend = false;
      _reply = null;
    });
    final GuardResponse response;
    try {
      response = await widget.api.sendQueued('summary', {
        'session_id': session.id,
        'summary': _text.text.trim(),
      });
    } on Exception catch (error) {
      unawaited(widget.api.errors.log('summary', '$error'));
      await widget.api.cancelGrading(session.id); // the draft stays
      unawaited(widget.onChanged());
      if (!mounted) return;
      setState(() {
        _sentAt = null;
        _busy = false;
        _failedSend = true;
      });
      return;
    }
    final passed = response.passed;
    final failed = passed == false;
    if (failed) {
      await widget.api.cancelGrading(session.id); // the draft is the rewrite
    } else if (passed != null) {
      await widget.api.doneGrading(session.id);
    }
    // The home screen refreshes even if this tab is gone by now.
    unawaited(widget.onChanged());
    if (!mounted) return;
    setState(() {
      _reply = response;
      _busy = false;
      if (failed) _sentAt = null;
    });
    if (response.passed ?? false) _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    final sentAt = _sentAt;
    final reply = _reply;
    final retry = widget.session.retry;
    final submitted = _busy || reply != null || _failedSend;
    final waiting = sentAt != null && reply?.passed == null;
    final (now, lapsed) = (DateTime.now(), _lapsed);
    final grader = graderNote(
      widget.state,
      waiting: waiting,
      now: lapsed != null && lapsed.isAfter(now) ? lapsed : now,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A restored failure: the topics to add, never the grader's prose.
        if (retry != null && !submitted)
          SummaryVerdict(
            const Cue(
              CueKind.error,
              icon: Icons.cancel,
              semanticLabel: 'not accepted',
            ),
            missing: retry.missing,
            retry: true,
          ),
        SummarySection(
          session: widget.session,
          controller: _text,
          enabled: sentAt == null,
          grader: grader,
          bonus: widget.pace?.earnsBonus(widget.session.pages) ?? false,
          times: SessionTimes(
            api: widget.api,
            session: widget.session,
            onChanged: widget.onChanged,
          ),
          onSubmit: sentAt == null ? _submit : null,
        ),
        if (waiting && submitted)
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.sm),
            child: LinearProgressIndicator(),
          ),
        if (sentAt != null && waiting && !submitted)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Align(
              alignment: Alignment.centerLeft,
              child: StatusCue(
                const Cue(
                  CueKind.info,
                  icon: Icons.hourglass_top,
                  semanticLabel: 'with the grader',
                ),
                badge: Text(hhmm(sentAt)),
              ),
            ),
          ),
        if (reply != null)
          SummaryVerdict.reply(reply, pages: widget.session.pages),
        if (_failedSend)
          const SummaryVerdict(
            Cue(CueKind.error, semanticLabel: 'sending failed'),
          ),
      ],
    );
  }
}
