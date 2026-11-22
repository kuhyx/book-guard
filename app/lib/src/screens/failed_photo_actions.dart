import 'dart:typed_data';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/page_reader.dart';
import 'package:book_guard_app/src/screens/failed_photo.dart';
import 'package:book_guard_app/src/screens/report_dialog.dart';
import 'package:book_guard_app/src/screens/type_page_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// Re-sends a late [failed] photo as a kept page photo, which the PC files
/// off every session: the keypad holds the number the phone read (or reads
/// now). False when the keypad was closed without a number.
Future<bool> keepLatePhoto(
  BuildContext context,
  GuardApi api,
  PageReader? reader,
  FailedPhoto failed,
  Uint8List bytes,
) async {
  final read =
      failed.entry.page ?? (await reader?.scan(bytes))?.hits.firstOrNull?.value;
  if (!context.mounted) return false;
  final page = await showDialog<int>(
    context: context,
    builder: (_) => TypePageDialog(initial: read),
  );
  if (page == null) return false;
  final kept = await api.queuePhoto(
    'kept',
    failed.entry.name,
    bytes,
    page: page,
    ocrPage: read,
  );
  await api.errors.event('photo', 'kept', {'photo': kept});
  return true;
}

/// "This should not fail": the photo, what both readers made of it and what
/// it really shows, queued for the PC. False when the dialog was cancelled.
Future<bool> reportFailedPhoto(
  BuildContext context,
  GuardApi api,
  FailedPhoto failed,
  Uint8List bytes,
) async {
  final answer = await showDialog<(int?, String)>(
    context: context,
    builder: (_) => ReportDialog(reason: failed.reason),
  );
  if (answer == null) return false;
  final (said, note) = answer;
  final entry = failed.entry;
  await api.reportPhoto(
    name: entry.name,
    bytes: bytes,
    detail: {
      'label': entry.label,
      'taken_at': entry.takenAt.toIso8601String(),
      'phone_page': entry.page,
      'pc_status': failed.pc?.status,
      'pc_reason': failed.pc?.reason,
      'failure': failed.reason,
      'actual_page': said,
      'comment': note,
    },
  );
  await api.flush();
  return true;
}
