import 'dart:convert';
import 'dart:typed_data';

import 'package:book_guard_app/src/guard_api.dart';

/// A stored photo put on the phone over adb: its label, when it was
/// taken, its file name and bytes.
typedef StagedCapture = ({
  String label,
  DateTime at,
  String name,
  Uint8List bytes,
});

/// Takes the photos staged over adb (each only once); null where nothing
/// can be staged (the desktop build).
typedef StagedCaptures = Future<List<StagedCapture>> Function();

/// The rows of a stage manifest: `[{file, label, taken_at}, ...]`.
List<({String file, String label, DateTime at})> parseStageManifest(
  String json,
) => [
  for (final row
      in (jsonDecode(json) as List<dynamic>).cast<Map<String, dynamic>>())
    (
      file: '${row['file']}',
      label: '${row['label']}',
      at: DateTime.parse('${row['taken_at']}'),
    ),
];

/// Live checks stage a stored photo of any age (the 26-day-old start photo
/// of 2026-10-27 hid the camera button): it is kept like a camera photo,
/// with the time it was staged with, and a pending camera launch is left
/// for the recovery to answer.
extension CaptureStaging on GuardApi {
  /// Keeps every photo [staged] hands over, logged as `staged`.
  Future<void> stageCaptures(StagedCaptures? staged) async {
    if (staged == null) return;
    for (final (i, photo) in (await staged()).indexed) {
      final id = 'staged-${photo.at.millisecondsSinceEpoch}-$i';
      await captures.add(
        id,
        photo.label,
        photo.name,
        photo.bytes,
        at: photo.at,
      );
      await errors.event('photo', 'staged', {
        'attempt': id,
        'label': photo.label,
      });
    }
  }
}
