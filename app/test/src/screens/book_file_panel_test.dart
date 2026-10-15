import 'package:book_guard_app/src/book_formats.dart';
import 'package:book_guard_app/src/index_job.dart';
import 'package:book_guard_app/src/screens/book_file_panel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';

void main() {
  group('pickBookFile', () {
    const channel = MethodChannel('plugins.flutter.io/file_selector');
    late List<MethodCall> calls;

    setUp(() => calls = []);

    void mockPicker(WidgetTester tester) {
      final messenger = tester.binding.defaultBinaryMessenger
        ..setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    }

    testWidgets('Android gets no filter, so no format is greyed out', (
      tester,
    ) async {
      mockPicker(tester);
      expect(defaultTargetPlatform, TargetPlatform.android);
      expect(await pickBookFile(), isNull);
      expect('${calls.single.arguments}', contains('acceptedTypeGroups: []'));
    });

    testWidgets('elsewhere the picker filters to the readable formats', (
      tester,
    ) async {
      mockPicker(tester);
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        expect(await pickBookFile(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
      final args = '${calls.single.arguments}';
      expect(args, contains('Book files'));
      expect(args, contains('azw3'));
    });
  });

  group('showBookFormats', () {
    Future<void> open(WidgetTester tester, List<bool> answers) async {
      await pumpTab(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => answers.add(await showBookFormats(context)),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('lists every group with its extensions', (tester) async {
      await open(tester, []);
      expect(find.text('Attach book file'), findsOneWidget);
      expect(find.text('The PC can read these formats:'), findsOneWidget);
      for (final group in bookFormatGroups) {
        expect(find.text(group.label), findsOneWidget);
      }
      expect(find.text('.pdf'), findsOneWidget);
      expect(find.textContaining('.epub  .kepub'), findsOneWidget);
    });

    testWidgets('Choose file is true', (tester) async {
      final answers = <bool>[];
      await open(tester, answers);
      await tester.tap(find.text('Choose file'));
      await tester.pumpAndSettle();
      expect(answers, [true]);
    });

    testWidgets('Cancel and a tap outside are false', (tester) async {
      final answers = <bool>[];
      await open(tester, answers);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(answers, [false, false]);
    });
  });

  group('IndexJobCard', () {
    var retries = 0;

    Future<void> pump(
      WidgetTester tester,
      IndexJob job, {
      bool canRetry = true,
    }) async {
      retries = 0;
      await pumpTab(
        tester,
        IndexJobCard(job: job, onRetry: canRetry ? () => retries++ : null),
      );
    }

    testWidgets('a running job shows its progress and no Retry', (
      tester,
    ) async {
      await pump(
        tester,
        IndexJob(
          file: 'a.epub',
          stage: 'embedding',
          done: 1,
          total: 4,
          updatedAt: DateTime.now(),
        ),
      );
      expect(find.text('a.epub: indexing 1 / 4 passages...'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, 0.25);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('a finished job has neither bar nor Retry', (tester) async {
      await pump(
        tester,
        const IndexJob(file: 'a.epub', stage: 'done', total: 9),
      );
      expect(find.text('a.epub: indexed (9 passages).'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('a failed job shows the reason in red and a working Retry', (
      tester,
    ) async {
      await pump(
        tester,
        const IndexJob(
          file: 'a.mobi',
          stage: 'failed',
          error: 'a.mobi: no text',
        ),
      );
      final text = tester.widget<Text>(find.text('a.mobi: no text'));
      expect(text.style?.color, isNotNull);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.tap(find.text('Retry'));
      expect(retries, 1);
    });

    testWidgets('a job silent for 30 minutes offers Retry too', (tester) async {
      await pump(
        tester,
        IndexJob(
          file: 'a.epub',
          stage: 'embedding',
          updatedAt: DateTime.now().subtract(const Duration(hours: 1)),
        ),
      );
      expect(
        find.textContaining('no progress for over 30 minutes'),
        findsOneWidget,
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.tap(find.text('Retry'));
      expect(retries, 1);
    });

    testWidgets('Retry is disabled without a callback', (tester) async {
      await pump(
        tester,
        const IndexJob(file: 'a.epub', stage: 'failed'),
        canRetry: false,
      );
      await tester.tap(find.text('Retry'));
      expect(retries, 0);
    });
  });
}
