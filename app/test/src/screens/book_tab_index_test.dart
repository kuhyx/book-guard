import 'dart:async';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/book_tab.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import '../../support/states.dart';

final _epub = Uint8List.fromList([0x50, 0x4b]);

/// [minutes] from the real clock: the panel judges staleness on `now`.
String _at(int minutes) =>
    DateTime.now().toUtc().add(Duration(minutes: minutes)).toIso8601String();

Map<String, dynamic> _job(
  String stage, {
  String file = 'a.epub',
  int done = 0,
  int total = 0,
  String error = '',
  String? updatedAt,
}) => {
  'index_job': {
    'file': file,
    'stage': stage,
    'done': done,
    'total': total,
    'error': error,
    'updated_at': updatedAt ?? _at(0),
  },
};

/// Walks the book through the stages the test hands it, one at a time.
class _FollowApi extends FakeApi {
  new(this.steps, this.gate);

  final List<GuardState> steps;
  final Completer<void> gate;

  @override
  Future<GuardState?> waitFor(bool Function(GuardState state) test) async {
    for (final step in steps) {
      if (test(step)) return step;
      await gate.future;
    }
    return null;
  }
}

void main() {
  late FakeApi api;

  setUp(() => api = FakeApi());

  Future<void> pump(
    WidgetTester tester, {
    GuardState? state,
    XFile? file,
    FakeApi? using,
  }) => pumpTab(
    tester,
    BookTab(
      api: using ?? api,
      state: state ?? sampleState(),
      onChanged: () async {},
      bookSource: () async => file,
    ),
  );

  Future<void> attach(WidgetTester tester) async {
    await tapVisible(tester, find.text('Attach book file'));
    await settle(tester);
    await tester.tap(find.text('Choose file'));
    await settle(tester);
  }

  testWidgets('the formats dialog comes first; Cancel stops there', (
    tester,
  ) async {
    await pump(tester, file: XFile.fromData(_epub, path: '/b/a.epub'));
    await tapVisible(tester, find.text('Attach book file'));
    await settle(tester);
    expect(find.text('The PC can read these formats:'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(api.books, isEmpty);
  });

  testWidgets('a format the PC cannot read is refused before uploading', (
    tester,
  ) async {
    await pump(tester, file: XFile.fromData(_epub, path: '/b/movie.mkv'));
    await attach(tester);
    expect(
      find.text('movie.mkv: the PC cannot read this format.'),
      findsOneWidget,
    );
    expect(api.books, isEmpty);
  });

  testWidgets('the last job shows on the tab', (tester) async {
    await pump(
      tester,
      state: sampleState(_job('embedding', done: 2, total: 8)),
    );
    expect(find.text('a.epub: indexing 2 / 8 passages...'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('a failed job shows its reason and Retry queues retry_book', (
    tester,
  ) async {
    await pump(
      tester,
      state: sampleState(_job('failed', error: 'a.epub: no text layer')),
    );
    expect(find.text('a.epub: no text layer'), findsOneWidget);
    await tapVisible(tester, find.text('Retry'));
    await settle(tester);
    expect(api.sent.single.type, 'retry_book');
    expect(api.sent.single.body, {'file': 'a.epub'});
    expect(find.text('done retry_book'), findsOneWidget);
  });

  testWidgets('Retry queues offline too, and says so', (tester) async {
    api.offline = true;
    await pump(tester, state: sampleState(_job('failed')));
    await tapVisible(tester, find.text('Retry'));
    await settle(tester);
    expect(api.sent.single.type, 'retry_book');
    expect(find.text('Saved on the phone'), findsOneWidget);
  });

  testWidgets('a retry the PC refuses is shown as an error', (tester) async {
    api.onSend = (_) async =>
        const GuardResponse(ok: false, message: 'No such file');
    await pump(tester, state: sampleState(_job('failed')));
    await tapVisible(tester, find.text('Retry'));
    await settle(tester);
    expect(find.text('No such file'), findsOneWidget);
  });

  testWidgets('a stalled job offers Retry', (tester) async {
    await pump(
      tester,
      state: sampleState(_job('embedding', updatedAt: '2026-01-01T00:00:00Z')),
    );
    expect(
      find.textContaining('no progress for over 30 minutes'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('a retry whose tab closed is dropped quietly', (tester) async {
    final gate = Completer<void>();
    final slow = _SlowSendApi(gate.future);
    await pump(tester, state: sampleState(_job('failed')), using: slow);
    await tapVisible(tester, find.text('Retry'));
    await tester.pumpWidget(const SizedBox());
    gate.complete();
    await settle(tester);
    expect(slow.sent, isNotEmpty);
  });

  group('following an upload', () {
    testWidgets('shows each stage, then reports the file attached', (
      tester,
    ) async {
      final gate = Completer<void>();
      final follow = _FollowApi([
        sampleState(_job('embedding', done: 3, total: 10, updatedAt: _at(1))),
        sampleState(_job('done', total: 10, updatedAt: _at(2))),
      ], gate);
      await pump(
        tester,
        file: XFile.fromData(_epub, path: '/b/a.epub'),
        using: follow,
      );
      await attach(tester);
      expect(find.text('a.epub: indexing 3 / 10 passages...'), findsOneWidget);
      gate.complete();
      await settle(tester);
      expect(find.text('Book file attached.'), findsOneWidget);
      expect(find.text('a.epub: indexing 3 / 10 passages...'), findsNothing);
    });

    testWidgets('the job of an earlier upload does not count', (tester) async {
      final stale = _job('done', total: 4, updatedAt: _at(-24 * 60));
      api.awaited = sampleState(stale);
      await pump(
        tester,
        state: sampleState(stale),
        file: XFile.fromData(_epub, path: '/b/a.epub'),
      );
      await attach(tester);
      expect(
        find.text('Still indexing - progress keeps showing here.'),
        findsOneWidget,
      );
    });

    testWidgets('a job for another file does not count', (tester) async {
      api.awaited = sampleState(_job('done', file: 'other.epub'));
      await pump(tester, file: XFile.fromData(_epub, path: '/b/a.epub'));
      await attach(tester);
      expect(
        find.text('Still indexing - progress keeps showing here.'),
        findsOneWidget,
      );
    });

    testWidgets('a failed job ends the wait without a toast', (tester) async {
      api.awaited = sampleState(_job('failed', error: 'a.epub: no text'));
      await pump(tester, file: XFile.fromData(_epub, path: '/b/a.epub'));
      await attach(tester);
      expect(find.text('Book file attached.'), findsNothing);
      expect(
        find.text('Still indexing - progress keeps showing here.'),
        findsNothing,
      );
      expect(find.text('a.epub: no text'), findsNothing);
    });
  });
}

/// A PC that answers sends only when the test opens the gate.
class _SlowSendApi extends FakeApi {
  new(this._gate);

  final Future<void> _gate;

  @override
  Future<GuardResponse> sendQueued(
    String type,
    Map<String, Object?> body,
    String what,
  ) async {
    await _gate;
    return await super.sendQueued(type, body, what);
  }
}
