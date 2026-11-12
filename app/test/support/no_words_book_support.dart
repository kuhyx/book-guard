/// Shared pieces of the zero-text guard over group C (the Book tab, the
/// library, a session, the settings and the in-app reader): what a screen
/// may show as it is, and the pump and check helpers.
library;

import 'package:book_guard_app/src/book_formats.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_api.dart';
import 'library_api.dart';
import 'no_words.dart';

/// Text the reader or the book wrote, file names and format identifiers:
/// shown as they are.
final bookContent = <String>[
  'Atomic Habits', 'James Clear', 'Cesarz', 'Wstęp', 'Wstep', 'Jeden', //
  'Done Book', 'Next Book', 'Dune', 'Frank Herbert', 'Dune Notes', //
  'Czerwony cesarz', 'Zbrodnia i kara', 'Sheridan', 'Herbert F.', //
  'a.epub', 'a.mobi', 'Atomic.epub', 'movie.mkv', 'from the PC', //
  'first try', 'second try', 'mention the habit loop', 'good', 'mine', //
  'KRÓTKI PRZEWODNIK', 'Xi was born in 1953.', 'Specific and consistent.', //
  'Michael S.', 'Rozdział 1', 'bookguard', 'https://old.host', //
  'Paragraph', 'word', //
  for (final e in bookExtensions) '.$e',
];

/// Pumps [home] in the light theme on the tall surface and settles.
Future<void> pumpScreen(WidgetTester tester, Widget home) async {
  tallSurface(tester);
  await tester.pumpWidget(MaterialApp(theme: buildLightTheme(), home: home));
  await settle(tester);
}

/// Fails when anything on screen holds a word that is not [bookContent].
void expectBookClean(WidgetTester tester) =>
    expectNoWords(tester, content: bookContent);
