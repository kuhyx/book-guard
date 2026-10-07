import 'dart:async';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/read_support.dart';
import 'package:book_guard_app/src/screens/session_times.dart';
import 'package:book_guard_app/src/summary_store.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// What [session] earns once its summary passes -- worked out here, so it
/// shows offline too. The PC signs the credit when it sees the summary.
String expectedCredit(SessionInfo session) =>
    'Passing credits ${session.pages} pages'
    '${session.bonusEligible ? ' and +1h gaming' : ''}. If the grader is '
    'unreachable for an hour, it is credited without grading.';

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
    this.grader,
  });

  /// The PC.
  final GuardApi api;

  /// The session waiting for its summary.
  final SessionInfo session;

  /// Refetch after grading.
  final Future<void> Function() onChanged;

  /// Why grading may wait (Claude down), if it may.
  final String? grader;

  @override
  State<SummaryPanel> createState() => _SummaryPanelState();
}

class _SummaryPanelState extends State<SummaryPanel> {
  final _text = TextEditingController();
  DateTime? _sentAt;
  String? _verdict;
  bool? _passed;

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
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
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final session = widget.session;
    await widget.api.markGrading(session.id);
    setState(() {
      _sentAt = DateTime.now();
      _verdict = 'Grading - this takes up to a minute...';
      _passed = null;
    });
    final GuardResponse response;
    try {
      response = await widget.api.sendQueued('summary', {
        'session_id': session.id,
        'summary': _text.text.trim(),
      }, 'Summary for p. ${session.startPage}-${session.endPage}');
    } on Exception catch (error) {
      unawaited(widget.api.errors.log('summary', '$error'));
      await widget.api.cancelGrading(session.id); // the draft stays
      unawaited(widget.onChanged());
      if (!mounted) return;
      setState(() {
        _sentAt = null;
        _verdict = '$error';
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
      _verdict = response.message;
      _passed = passed;
      if (failed) _sentAt = null;
    });
    if (response.passed ?? false) _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    final sentAt = _sentAt;
    final verdict = _verdict;
    final retry = widget.session.retry;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (retry != null && verdict == null) ...[
          VerdictText(retry.feedback, passed: false),
          if (retry.missing.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                'To be accepted, add:\n'
                '${retry.missing.map((m) => '- $m').join('\n')}',
              ),
            ),
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              'Add that and send it again - there is no limit on rewrites.',
            ),
          ),
        ],
        SummarySection(
          session: widget.session,
          controller: _text,
          enabled: sentAt == null,
          grader: widget.grader,
          times: SessionTimes(
            api: widget.api,
            session: widget.session,
            onChanged: widget.onChanged,
          ),
          onSubmit: sentAt == null ? _submit : null,
        ),
        if (sentAt != null && _passed == null && verdict != null)
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.sm),
            child: LinearProgressIndicator(),
          ),
        if (sentAt != null && verdict == null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              'Sent to the grader at ${hhmm(sentAt)} - the verdict appears '
              'here and as a message.',
            ),
          ),
        if (verdict != null) VerdictText(verdict, passed: _passed),
        // Still owed after a fail too: the rewrite earns the same.
        if (_passed != true)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(expectedCredit(widget.session)),
          ),
      ],
    );
  }
}
