import 'package:book_guard_app/src/book_formats.dart';
import 'package:book_guard_app/src/index_job.dart';
import 'package:book_guard_app/src/screens/book_file_panel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import '../../support/finders_book.dart';

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

    testWidgets('lists every extension, a divider between the groups', (
      tester,
    ) async {
      await open(tester, []);
      // No heading or sentence: the chips and two icon buttons.
      expect(iconLabeled('Choose file'), findsOneWidget);
      expect(iconLabeled('Cancel'), findsOneWidget);
      // Each extension is its own widget, so none breaks mid-name.
      for (final e in bookFormatGroups.expand((g) => g.extensions)) {
        expect(find.text('.$e'), findsOneWidget);
      }
      expect(find.byType(Wrap), findsNWidgets(bookFormatGroups.length));
      expect(find.byType(Divider), findsNWidgets(bookFormatGroups.length - 1));
    });

    testWidgets('the folder icon answers true', (tester) async {
      final answers = <bool>[];
      await open(tester, answers);
      await tester.tap(iconLabeled('Choose file'));
      await tester.pumpAndSettle();
      expect(answers, [true]);
    });

    testWidgets('the close icon and a tap outside are false', (tester) async {
      final answers = <bool>[];
      await open(tester, answers);
      await tester.tap(iconLabeled('Cancel'));
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

    testWidgets('a running job shows its progress and no retry icon', (
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
      expect(find.text('a.epub'), findsOneWidget);
      expect(find.text('1/4'), findsOneWidget);
      expect(
        tester.widget<Icon>(iconLabeled('embedding')).icon,
        Icons.scatter_plot,
      );
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, 0.25);
      expect(iconLabeled('Retry'), findsNothing);
    });

    testWidgets('a finished job is a green check, no bar, no retry', (
      tester,
    ) async {
      await pump(
        tester,
        const IndexJob(file: 'a.epub', stage: 'done', total: 9),
      );
      expect(find.text('9'), findsOneWidget);
      expect(tester.widget<Icon>(iconLabeled('done')).icon, Icons.check_circle);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(iconLabeled('Retry'), findsNothing);
    });

    testWidgets('a failed job is a red error icon and a working retry', (
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
      final icon = tester.widget<Icon>(iconLabeled('failed'));
      expect(icon.icon, Icons.error);
      expect(icon.color, isNotNull);
      // The reason is never painted (it goes to the error log).
      expect(find.textContaining('no text'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.tap(iconLabeled('Retry'));
      expect(retries, 1);
    });

    testWidgets('a job silent for 30 minutes offers retry too', (tester) async {
      await pump(
        tester,
        IndexJob(
          file: 'a.epub',
          stage: 'embedding',
          updatedAt: DateTime.now().subtract(const Duration(hours: 1)),
        ),
      );
      expect(
        tester.widget<Icon>(iconLabeled('embedding')).icon,
        Icons.timer_off,
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.tap(iconLabeled('Retry'));
      expect(retries, 1);
    });

    testWidgets('retry is disabled without a callback', (tester) async {
      await pump(
        tester,
        const IndexJob(file: 'a.epub', stage: 'failed'),
        canRetry: false,
      );
      expect(pressable(tester, 'Retry'), isFalse);
      await tester.tap(iconLabeled('Retry'));
      expect(retries, 0);
    });
  });
}
