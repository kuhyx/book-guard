import 'dart:convert';
import 'dart:io';

import 'package:book_guard_app/src/capture_stage.dart';
import 'package:book_guard_app/src/page_number.dart';
import 'package:book_guard_app/src/page_reader.dart';
import 'package:book_guard_app/src/page_reader_tesseract.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

// phone-slot: not-shared-storage -- the path below is a doc example; the
// folder is getExternalStorageDirectory(), which is per package.

/// On-device check of the page reader against labelled photos, driven
/// over adb with no screen interaction:
///
///     adb push page_truth/ /sdcard/Android/data/<app>/files/page_truth/
///     adb shell touch .../files/page_truth/run   # then launch the app
///     adb pull .../files/page_truth/results.json
///
/// The rows are `scripts/page_truth.py`'s manifest; rows with a hand-drawn
/// `box` (that path is the review screen's) or a `pencil` key (the pencil
/// reader's, which needs the page's text box) are skipped.
Future<void> runSelfTestIfAsked(PageReader? reader) async {
  if (reader == null) return;
  // Android only: the folder adb can write into (host tests have none).
  if (!Platform.isAndroid) return;
  final base = await getExternalStorageDirectory();
  if (base == null) return;
  final dir = Directory('${base.path}/page_truth');
  final trigger = File('${dir.path}/run');
  if (!trigger.existsSync()) return;
  await trigger.delete();
  final rows = jsonDecode(
    await File('${dir.path}/manifest.json').readAsString(),
  ) as List<dynamic>;
  final results = <Map<String, Object?>>[];
  for (final row in rows.cast<Map<String, dynamic>>()) {
    if (row['box'] != null || row.containsKey('pencil')) continue;
    final given = row['context'] as Map<String, dynamic>? ?? const {};
    final context = PageContext(
      expected: given['expected'] as int?,
      after: given['after'] as int?,
      near: given['near'] as int?,
      lastPage: given['last_page'] as int?,
    );
    final watch = Stopwatch()..start();
    final scan = await reader.scan(
      await File('${dir.path}/${row['file']}').readAsBytes(),
      context: context,
    );
    final choice = scan == null
        ? const PageChoice(null, 'unreadable')
        : choosePage(scan.hits, context);
    final got = choice.hit?.value;
    final result = {
      'file': row['file'],
      'want': row['truth'] ?? row['page'],
      'got': got,
      'ok': got == (row['truth'] ?? row['page']),
      'reason': choice.reason,
      'turn': scan?.turn,
      'hits': [
        for (final h in scan?.hits ?? const <NumberHit>[])
          {
            'value': h.value,
            'box': [h.box.left, h.box.top, h.box.right, h.box.bottom],
          },
      ],
      'millis': scan?.millis,
      'total_ms': watch.elapsedMilliseconds,
      if (reader case final TesseractPageReader t) 'stages': {...t.stages},
    };
    debugPrint('page_truth ${jsonEncode(result)}');
    results.add(result);
  }
  await File('${dir.path}/results.json').writeAsString(jsonEncode(results));
}

/// Stored photos staged over adb for a live check, taken once:
///
///     adb push p473.jpg .../files/stage_capture/
///     adb push manifest.json .../files/stage_capture/  # [{file, label, taken_at}]
///
/// then launch the app. The folder is emptied as it is read.
Future<List<StagedCapture>> takeStagedCaptures() async {
  if (!Platform.isAndroid) return const [];
  final base = await getExternalStorageDirectory();
  if (base == null) return const [];
  final dir = Directory('${base.path}/stage_capture');
  final manifest = File('${dir.path}/manifest.json');
  if (!manifest.existsSync()) return const [];
  final rows = parseStageManifest(await manifest.readAsString());
  await manifest.delete();
  final staged = <StagedCapture>[];
  for (final row in rows) {
    final file = File('${dir.path}/${row.file}');
    staged.add((
      label: row.label,
      at: row.at,
      name: row.file,
      bytes: await file.readAsBytes(),
    ));
    await file.delete();
  }
  return staged;
}
