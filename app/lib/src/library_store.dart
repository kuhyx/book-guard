import 'dart:convert';
import 'dart:typed_data';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/library.dart';

export 'package:book_guard_app/src/library.dart';

/// The Library tab's data: `library.json` (kept on the device, like
/// `state.json`) and the notes written here, which stay on the device for
/// good so they show offline and before the PC has stored them.
extension LibraryStore on GuardApi {
  static const _file = 'library.json';
  static const _notes = 'notes/';

  // GuardApi's own `pending/` marker: `collectAnswers` then takes the PC's
  // answer (and deletes the response file) on a later refresh.
  static const _pending = 'pending/';

  /// The PC's library, kept on the device; the kept copy when the PC is
  /// out of reach; null before the PC ever wrote one.
  Future<Library?> loadLibrary() async {
    try {
      final text = await dav.getText('Reading/$_file');
      if (text != null) {
        await store.write(_file, Uint8List.fromList(utf8.encode(text)));
      }
    } on Exception {
      // Offline: fall through to the kept copy.
    }
    return await cachedLibrary();
  }

  /// The copy kept on the device, at once and with no network; null if
  /// there is none or it cannot be read.
  Future<Library?> cachedLibrary() async {
    final raw = await store.read(_file);
    if (raw == null) return null;
    try {
      final json = jsonDecode(utf8.decode(raw));
      return json is Map<String, dynamic> ? Library.fromJson(json) : null;
    } on FormatException {
      return null;
    }
  }

  /// [book]'s notes: the PC's copy merged with the device's, the newer
  /// edit of each winning; by page (unpaged last), then oldest first.
  Future<List<Note>> notesOf(LibraryBook book) async =>
      mergeNotes(book, await deviceNotes());

  /// Every note written on this device, for any book.
  Future<List<Note>> deviceNotes() async => [
    for (final name in await store.list(_notes))
      if (await store.read(name) case final raw?)
        Note.fromJson(jsonDecode(utf8.decode(raw)) as Map<String, dynamic>),
  ];

  /// Keeps [note] on the device and queues it for the PC (a `note`
  /// request through the outbox); sent now if the PC answers, else later.
  /// Never waits for the answer: it arrives with a later refresh.
  Future<void> saveNote(Note note) async {
    final body = Uint8List.fromList(utf8.encode(jsonEncode(note.toJson())));
    await store.write('$_notes${note.id}.json', body);
    final id = newId();
    final json = note.toJson();
    final request = {
      'id': id,
      'type': 'note',
      'note_id': json.remove('id'),
      ...json,
    };
    await outbox.put(
      'requests/$id.json',
      Uint8List.fromList(utf8.encode(jsonEncode(request))),
    );
    await store.write('$_pending$id', Uint8List.fromList(utf8.encode('Note')));
    await flush();
  }
}

/// [book]'s notes: its PC copy merged with the [device] notes (of any
/// book), the newer edit of each winning; by page (unpaged last), then
/// oldest first.
List<Note> mergeNotes(LibraryBook book, List<Note> device) {
  final byId = {for (final n in book.notes) n.id: n};
  for (final note in device) {
    if (note.isbn == book.isbn && queuedOnPhone(book, note)) {
      byId[note.id] = note;
    }
  }
  return byId.values.toList()..sort(_byPlace);
}

/// Whether [note] (as the device has it) is not in [book]'s PC copy yet:
/// the PC has no such note, or only an older edit of it. True until the
/// PC's `library.json` lists this edit.
bool queuedOnPhone(LibraryBook book, Note note) => !book.notes.any(
  (pc) => pc.id == note.id && !note.updatedAt.isAfter(pc.updatedAt),
);

int _byPlace(Note a, Note b) {
  final pa = a.page ?? 1 << 30;
  final pb = b.page ?? 1 << 30;
  return pa != pb ? pa.compareTo(pb) : a.createdAt.compareTo(b.createdAt);
}
