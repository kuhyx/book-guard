import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/session_times.dart';

/// Why a sent summary waits, while the PC's Claude is down -- null unless a
/// summary is [waiting] for its verdict and the outage still holds at [now].
///
/// The PC re-casts every vote on its local model whenever Claude fails, and
/// a local grade clears the outage -- so a note still showing may well mean
/// the local model failed too: "tries", never "grades". If neither answers,
/// the summary is credited ungraded after 5 minutes (`expectedCredit`).
String? graderNote(
  GuardState? state, {
  required bool waiting,
  required DateTime now,
}) {
  final since = state?.claudeDownSince;
  final until = state?.claudeDownUntil;
  if (!waiting || since == null) return null;
  if (until != null && !until.isAfter(now)) return null;
  final end = until == null ? '' : ', until ${_when(until, now)}';
  return 'Claude (the grader on the PC) is unavailable since '
      '${_when(since, now)}$end - the PC tries its local model on your '
      'summary instead. Nothing is lost.';
}

/// `16:25`, `yesterday 16:25`, `tomorrow 16:25` or `15.10 16:25`.
String _when(DateTime moment, DateTime now) {
  final local = moment.toLocal();
  final days = _day(local).difference(_day(now.toLocal())).inDays;
  final day = switch (days) {
    0 => '',
    -1 => 'yesterday ',
    1 => 'tomorrow ',
    _ =>
      '${local.day.toString().padLeft(2, '0')}.'
          '${local.month.toString().padLeft(2, '0')} ',
  };
  return '$day${hhmm(local)}';
}

/// Midnight UTC of [moment]'s calendar date: whole days apart, DST or not.
DateTime _day(DateTime moment) =>
    DateTime.utc(moment.year, moment.month, moment.day);
