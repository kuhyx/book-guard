import 'dart:convert';
import 'dart:typed_data';

import 'package:book_guard_app/src/guard_api.dart';

/// Photos kept on the device for review and bug reports (~2 MB each).
const keptPhotos = 40;

/// The device's copies of its photos, and "this should not fail" reports.
extension PhotoReports on GuardApi {
  /// Keeps only the newest [keptPhotos] photos on the device.
  Future<void> prunePhotos() async {
    final recent = (await journal.load()).reversed
        .take(keptPhotos)
        .map((e) => 'photos/${e.name}')
        .toSet();
    for (final name in await store.list('photos/')) {
      if (!recent.contains(name)) await store.delete(name);
    }
  }

  /// [name] reduced to what the share and the PC accept.
  String safeName(String name) {
    final base = name.split(RegExp(r'[\\/]')).last;
    final cleaned = base.replaceAll(RegExp('[^A-Za-z0-9._-]'), '_');
    return cleaned.isEmpty ? '${newId()}.bin' : cleaned;
  }

  /// The device's copy of a photo taken here, or null.
  Future<Uint8List?> localPhoto(String name) => store.read('photos/$name');

  /// Files a "this should not have failed" report: the photo, what the
  /// phone and the PC made of it, and what the reader says it shows.
  Future<void> reportPhoto({
    required String name,
    required Uint8List bytes,
    required Map<String, Object?> detail,
  }) async {
    final id = newId();
    await outbox.put('logs/reports/$id.jpg', bytes);
    await outbox.put(
      'logs/reports/$id.json',
      Uint8List.fromList(
        utf8.encode(jsonEncode({'photo': name, 'image': '$id.jpg', ...detail})),
      ),
    );
    await store.write('reported/$name', Uint8List(0));
  }

  /// Whether [name] was already reported.
  Future<bool> reported(String name) async =>
      await store.read('reported/$name') != null;
}
