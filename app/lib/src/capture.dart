import 'dart:convert';
import 'dart:typed_data';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/local_store.dart';

/// A photo the camera returned that is not queued for the PC yet: it waits
/// for its page number to be confirmed on the review screen.
class Capture {
  /// Creates one.
  const new({
    required this.id,
    required this.label,
    required this.fileName,
    required this.takenAt,
  });

  /// Parses the stored form.
  factory fromJson(Map<String, dynamic> json) => Capture(
    id: '${json['id']}',
    label: '${json['label']}',
    fileName: '${json['file_name']}',
    takenAt: DateTime.parse('${json['taken_at']}'),
  );

  /// The attempt id every lifecycle event of this photo carries.
  final String id;

  /// `start`, `stop` or `check<N>`.
  final String label;

  /// The camera's file name.
  final String fileName;

  /// When the camera returned it.
  final DateTime takenAt;

  /// The stored form.
  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'file_name': fileName,
    'taken_at': takenAt.toIso8601String(),
  };
}

/// Photos between the camera and the outbox, on the device's disk.
///
/// 2026-10-23: a start photo was read as p. 252 on the review screen and
/// never sent -- its bytes lived only in memory until "Send", and the app
/// left that screen. Now the photo is stored the moment the camera returns
/// and only a deliberate Retake or the queueing removes it; anything else
/// leaves it here to be finished later. It is not put in the outbox before
/// the review: the PC reads a photo the moment it lands and trusts the
/// page number sent ahead of it, so an unreviewed photo would be read
/// without one.
class Captures {
  /// Creates the store's view.
  new(this.store);

  /// Where they live.
  final LocalStore store;

  static const _dir = 'capture/';
  static const _camera = 'camera.json';

  /// Notes that the camera is opening for [label] as attempt [id] -- what
  /// a restart needs to name a photo Android kept for the app.
  Future<void> launching(String id, String label) =>
      store.write(_camera, _bytes(jsonEncode({'id': id, 'label': label})));

  /// The camera opened and not yet answered, if any.
  Future<({String id, String label})?> launched() async {
    final raw = await store.read(_camera);
    if (raw == null) return null;
    final json = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
    return (id: '${json['id']}', label: '${json['label']}');
  }

  /// The camera answered (or never will).
  Future<void> landed() => store.delete(_camera);

  /// Stores the camera's photo; the launch is answered.
  Future<Capture> keep(
    String id,
    String label,
    String fileName,
    Uint8List bytes, {
    DateTime? at,
  }) async {
    final capture = Capture(
      id: id,
      label: label,
      fileName: fileName,
      takenAt: at ?? DateTime.now(),
    );
    await store.write('$_dir$id.bin', bytes);
    // The note goes last: a capture only exists once both parts do.
    await store.write('$_dir$id.json', _bytes(jsonEncode(capture.toJson())));
    await landed();
    return capture;
  }

  /// Every photo still waiting, oldest attempt first.
  Future<List<Capture>> pending() async {
    final found = <Capture>[];
    for (final name in await store.list(_dir)) {
      if (!name.endsWith('.json')) continue;
      final raw = await store.read(name);
      if (raw == null) continue;
      found.add(
        Capture.fromJson(jsonDecode(utf8.decode(raw)) as Map<String, dynamic>),
      );
    }
    return found..sort((a, b) => a.takenAt.compareTo(b.takenAt));
  }

  /// The photo's bytes, or null once it is gone.
  Future<Uint8List?> bytes(Capture capture) =>
      store.read('$_dir${capture.id}.bin');

  /// Forgets it: queued, or deliberately discarded.
  Future<void> drop(Capture capture) async {
    await store.delete('$_dir${capture.id}.json');
    await store.delete('$_dir${capture.id}.bin');
  }

  static Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));
}

/// A photo the platform kept while the app was gone, as (file name, bytes).
typedef LostPhoto = Future<(String, Uint8List)?> Function();

/// Picks up after a restart that cut the camera off.
extension CameraRecovery on GuardApi {
  /// If a camera was open when the app last stopped, keeps the photo
  /// Android saved for it ([lost]; null where there is none) under the
  /// label it was opened for -- or logs that it never came back.
  Future<void> recoverCamera(LostPhoto? lost) async {
    final launch = await captures.launched();
    if (launch == null) return;
    final found = lost == null ? null : await lost();
    final detail = {'attempt': launch.id, 'label': launch.label};
    if (found == null) {
      await captures.landed();
      await errors.event('photo', 'camera-lost', detail);
      return;
    }
    final (name, bytes) = found;
    await captures.keep(launch.id, launch.label, name, bytes);
    await errors.event('photo', 'recovered', {...detail, 'file': name});
  }
}
