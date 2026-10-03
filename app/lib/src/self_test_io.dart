import 'dart:convert';
import 'dart:io';

import 'package:book_guard_app/src/page_number.dart';
import 'package:book_guard_app/src/page_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// On-device check of the page reader against labelled photos, driven
/// over adb with no screen interaction:
///
///     adb push page_truth/ /sdcard/Android/data/<app>/files/page_truth/
///     adb shell touch .../files/page_truth/run   # then launch the app
///     adb pull .../files/page_truth/results.json
///
/// The rows are `scripts/page_truth.py`'s manifest; rows with a hand-drawn
/// `box` are skipped (that path is the review screen's).
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
    if (row['box'] != null) continue;
    final scan = await reader.scan(
      await File('${dir.path}/${row['file']}').readAsBytes(),
    );
    final context = row['context'] as Map<String, dynamic>? ?? const {};
    final choice = scan == null
        ? const PageChoice(null, 'unreadable')
        : choosePage(
            scan.hits,
            PageContext(
              expected: context['expected'] as int?,
              after: context['after'] as int?,
              near: context['near'] as int?,
              lastPage: context['last_page'] as int?,
            ),
          );
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
    };
    debugPrint('page_truth ${jsonEncode(result)}');
    results.add(result);
  }
  await File('${dir.path}/results.json').writeAsString(jsonEncode(results));
}
