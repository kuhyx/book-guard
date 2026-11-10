import 'package:book_guard_app/src/screens/reject_glyph.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';

/// What the PC appends to a number reason (`_ASK_FOR_BOX`).
const _suffix = ' -- box the page number in the app, or retake the photo';

void main() {
  group('rejectGlyph', () {
    final cases = <String, RejectGlyph>{
      // The ambiguous or untrusted number.
      'page number unclear (12 or 21)$_suffix': RejectGlyph.unclear,
      'page number unclear (7 or 9)': RejectGlyph.unclear,
      'page 99 is far from p. 12, the last one$_suffix': RejectGlyph.unclear,
      // No (matching) number on the photo.
      'no page number found$_suffix': RejectGlyph.noNumber,
      'no page after 40 found on the photo$_suffix': RejectGlyph.noNumber,
      'page 12 not found on the photo$_suffix': RejectGlyph.noNumber,
      phoneFoundNone: RejectGlyph.noNumber,
      noNumberReason: RejectGlyph.noNumber,
      // Not a page.
      'no page on the photo': RejectGlyph.notPage,
      '': RejectGlyph.notPage,
      // The PC could not read it.
      'the PC could not read the photo': RejectGlyph.pcUnreadable,
      // Overlap.
      'overlaps another session': RejectGlyph.overlap,
      // Reasons no glyph covers: neutral warning.
      'no EXIF capture time': RejectGlyph.unknown,
      'uploaded more than 7 days after it was taken': RejectGlyph.unknown,
      'something new': RejectGlyph.unknown,
    };
    for (final MapEntry(key: reason, value: glyph) in cases.entries) {
      test('"$reason" -> ${glyph.name}', () {
        expect(rejectGlyph(reason), glyph);
      });
    }

    test('every glyph has its own icon and its own tint', () {
      expect({for (final g in RejectGlyph.values) g.icon}.length, 6);
    });
  });

  testWidgets('each glyph has its own colour', (tester) async {
    final tints = <RejectGlyph, Color>{};
    await pumpTab(
      tester,
      Builder(
        builder: (context) {
          for (final g in RejectGlyph.values) {
            tints[g] = g.tint(context);
          }
          return const SizedBox();
        },
      ),
    );
    expect(tints.values.toSet().length, RejectGlyph.values.length);
  });

  testWidgets('a badge buzzes once only when asked to', (tester) async {
    final buzzes = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          buzzes.add('${call.arguments}');
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpTab(
      tester,
      RejectBadge('no page number found', key: UniqueKey()),
    );
    expect(buzzes, isEmpty);
    await pumpTab(
      tester,
      RejectBadge('no page number found', buzz: true, key: UniqueKey()),
    );
    expect(buzzes, ['HapticFeedbackType.heavyImpact']);
    expect(find.byIcon(RejectGlyph.noNumber.icon), findsOneWidget);
  });
}
