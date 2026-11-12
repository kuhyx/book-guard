/// Shared fixtures for the zero-text guard over the Read tab and its photo
/// screens: the PC-written content a screen may show as it is, one journal
/// entry, every kind of filed photo and a state carrying a photo list.
library;

import 'dart:typed_data';

import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/local_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_api.dart';
import 'fake_reader.dart';
import 'library_api.dart';
import 'states.dart';

/// Text the PC or the reader wrote: shown as it is.
const readContent = [
  'the habit loop',
  'Kaladin',
  'Atomic Habits',
  'James Clear',
];

/// What the PC appends to a number reason.
const boxItSuffix = ' -- box the page number in the app, or retake the photo';

final Uint8List readBytes = previewPng;

JournalEntry journalEntry(String name, String label, int? page) => JournalEntry(
  name: name,
  label: label,
  sha: 'f' * 64,
  takenAt: DateTime.utc(2026, 10, 3, 12, 27),
  page: page,
);

/// Every kind of photo the PC can have filed, with every rejection reason.
List<PhotoInfo> filedPhotos() => [
  for (final reason in [
    'page number unclear (12 or 21)$boxItSuffix',
    'no page number found$boxItSuffix',
    'no page on the photo',
    'the PC could not read the photo',
    'no EXIF capture time',
    'overlaps another session',
  ])
    reading(
      name: 'r${reason.length}.jpg',
      kind: 'other',
      page: null,
      status: 'rejected',
      reason: reason,
    ),
  reading(),
  reading(kind: 'toc', page: null),
  reading(kind: 'isbn', page: null),
];

GuardState withPhotos(List<PhotoInfo> photos, [GuardState? base]) {
  final s = base ?? sampleState();
  return GuardState(
    locked: s.locked,
    reason: s.reason,
    book: s.book,
    pace: s.pace,
    todo: s.todo,
    sessions: s.sessions,
    openStart: s.openStart,
    generatedAt: s.generatedAt,
    photos: photos,
  );
}

/// Pumps [child] on the tall surface (scrolling, unless [scroll] is off),
/// settles, and tears the tree down when the test ends.
Future<void> showTab(
  WidgetTester tester,
  Widget child, {
  bool scroll = true,
}) async {
  tallSurface(tester);
  await pumpTab(tester, scroll ? SingleChildScrollView(child: child) : child);
  await settle(tester, 10);
  addTearDown(() => tester.pumpWidget(const SizedBox()));
}
