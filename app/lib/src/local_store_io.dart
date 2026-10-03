import 'dart:io';

import 'package:book_guard_app/src/local_store.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// The phone's store: files under the app's support folder, which an
/// app update (`adb install -r`) keeps.
Future<LocalStore> createLocalStore() async {
  try {
    final base = await getApplicationSupportDirectory();
    return FileStore(Directory('${base.path}/store'));
  } on Exception catch (error) {
    // No platform folder (a host test): keep working, in memory.
    debugPrint('book-guard: no app folder ($error); store kept in memory');
    return MemoryStore();
  }
}

/// A [LocalStore] over a folder; a name's `/` is a subfolder.
class FileStore implements LocalStore {
  /// Creates a store rooted at [root].
  new(this.root);

  /// Where everything lives.
  final Directory root;

  File _file(String name) => File('${root.path}/$name');

  @override
  Future<Uint8List?> read(String name) async {
    final file = _file(name);
    return file.existsSync() ? await file.readAsBytes() : null;
  }

  @override
  Future<void> write(String name, Uint8List bytes) async {
    final file = _file(name);
    await file.parent.create(recursive: true);
    // Write aside, then rename: a killed app never leaves half a file.
    final temp = File('${file.path}.part');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(file.path);
  }

  @override
  Future<void> delete(String name) async {
    final file = _file(name);
    if (file.existsSync()) await file.delete();
  }

  @override
  Future<List<String>> list(String prefix) async {
    if (!root.existsSync()) return [];
    final names = [
      for (final entity in root.listSync(recursive: true))
        if (entity is File && !entity.path.endsWith('.part'))
          entity.path.substring(root.path.length + 1),
    ];
    return [...names.where((n) => n.startsWith(prefix))]..sort();
  }
}
