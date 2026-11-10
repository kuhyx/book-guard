import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The framework's pickers paint "Select date", "Cancel" and "OK"; the app
/// uses `icon_pickers.dart` instead. A new call site fails here even before
/// it has a widget test of its own.
void main() {
  test('lib/ calls none of the framework pickers', () {
    final banned = RegExp(r'\bshow(Date|Time|DateRange)Picker\b');
    final lib = Directory('lib');
    expect(lib.existsSync(), isTrue, reason: 'run from the app root');
    final files = lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(files, isNotEmpty);
    final hits = [
      for (final f in files)
        for (final (i, line) in f.readAsLinesSync().indexed)
          if (banned.hasMatch(line)) '${f.path}:${i + 1}',
    ];
    expect(hits, isEmpty);
  });
}
