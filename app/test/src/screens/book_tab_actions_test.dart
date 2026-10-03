import 'dart:async';

import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/screens/book_tab.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import '../../support/states.dart';

final _epub = Uint8List.fromList([0x50, 0x4b]);

void main() {
  late FakeApi api;
  late int changed;
  late List<bool> cameras;

  setUp(() {
    api = FakeApi();
    changed = 0;
    cameras = [];
  });

  Future<void> pump(
    WidgetTester tester, {
    GuardState? state,
    XFile? file,
    XFile? photo,
    bool desktop = false,
  }) => pumpTab(
    tester,
    BookTab(
      api: api,
      state: state ?? sampleState(),
      onChanged: () async => changed++,
      bookSource: () async => file,
      desktop: desktop,
      photoSource: ({required camera}) async {
        cameras.add(camera);
        return photo;
      },
    ),
  );

  testWidgets('attaching waits until the PC has indexed the file', (
    tester,
  ) async {
    api.awaited = sampleState();
    await pump(tester, file: XFile.fromData(_epub, path: '/b/Atomic.epub'));
    await tapVisible(tester, find.byIcon(Icons.attach_file));
    await settle(tester);
    expect(api.books, {'Atomic.epub': _epub});
    expect(find.text('Ebook attached.'), findsNWidgets(2));
    expect(changed, 1);
  });

  testWidgets('a PC that has not indexed the file yet says so', (tester) async {
    await pump(tester, file: XFile.fromData(_epub, path: '/b/a.epub'));
    await tapVisible(tester, find.byIcon(Icons.attach_file));
    await settle(tester);
    expect(
      find.text('The PC has not indexed it yet - it will when it is on.'),
      findsNWidgets(2),
    );
  });

  testWidgets('a contents photo reports the chapters it gave', (tester) async {
    api
      ..readings['toc-c.jpg'] = reading(name: 'toc-c.jpg', kind: 'toc')
      ..state = sampleState({
        'book': {
          'title': 'Cesarz',
          'chapters': [
            {'start': 9, 'title': 'Wstęp'},
            {'start': 25, 'title': 'Jeden'},
          ],
        },
      });
    await pump(tester, photo: XFile.fromData(_epub, path: '/DCIM/c.jpg'));
    await tapVisible(tester, find.text('Photograph contents'));
    await settle(tester);
    expect(cameras, [true]);
    expect(api.photos.keys, ['toc-c.jpg']);
    expect(
      find.text('Contents read - the book has 2 chapters.'),
      findsNWidgets(2),
    );
  });

  testWidgets('an unread or rejected contents photo says so', (tester) async {
    await pump(
      tester,
      desktop: true,
      photo: XFile.fromData(_epub, path: '/DCIM/c.jpg'),
    );
    expect(find.byIcon(Icons.upload_file), findsOneWidget);
    await tapVisible(tester, find.text('Photograph contents'));
    await settle(tester);
    expect(cameras, [false]);
    expect(
      find.text('The PC has not read it yet - it will when it is on.'),
      findsNWidgets(2),
    );
  });

  testWidgets('offline, a contents photo waits on the phone', (tester) async {
    api.offline = true;
    await pump(tester, photo: XFile.fromData(_epub, path: '/DCIM/c.jpg'));
    await tapVisible(tester, find.text('Photograph contents'));
    await settle(tester);
    expect(
      find.text(
        'Saved on the phone - the PC reads the contents once it is '
        'reachable.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a cancelled contents pick uploads nothing', (tester) async {
    await pump(tester);
    await tapVisible(tester, find.text('Photograph contents'));
    await settle(tester);
    expect(api.photos, isEmpty);
  });

  testWidgets('results arriving after the tab closed are dropped', (
    tester,
  ) async {
    final gate = Completer<void>();
    final slow = _GatedApi(gate.future)
      ..awaited = sampleState()
      ..readings['toc-c.jpg'] = reading(name: 'toc-c.jpg', kind: 'toc');
    for (final label in ['Photograph contents', 'Attach ebook file']) {
      await pumpTab(
        tester,
        BookTab(
          api: slow,
          state: sampleState(),
          onChanged: () async {},
          bookSource: () async => XFile.fromData(_epub, path: '/b/a.epub'),
          photoSource: ({required camera}) async =>
              XFile.fromData(_epub, path: '/DCIM/c.jpg'),
        ),
      );
      await tapVisible(tester, find.text(label));
      await settle(tester);
      await tester.pumpWidget(const SizedBox());
    }
    gate.complete();
    await settle(tester);
    expect(find.textContaining('read'), findsNothing);
  });

  testWidgets('a cancelled pick uploads nothing', (tester) async {
    await pump(tester);
    await tapVisible(tester, find.byIcon(Icons.attach_file));
    await settle(tester);
    expect(api.books, isEmpty);
    expect(find.textContaining('Uploaded'), findsNothing);
  });

  testWidgets('an upload failure is shown', (tester) async {
    api.uploadError = shareDown();
    await pump(tester, file: XFile.fromData(_epub, path: '/b/a.pdf'));
    await tapVisible(tester, find.byIcon(Icons.attach_file));
    await settle(tester);
    expect(find.text('dufs Reading/x failed (500)'), findsOneWidget);
  });
}

/// Holds every wait until the test opens the gate.
class _GatedApi extends FakeApi {
  new(this._gate);

  final Future<void> _gate;

  @override
  Future<GuardState?> waitFor(bool Function(GuardState state) test) async {
    await _gate;
    return await super.waitFor(test);
  }

  @override
  Future<PhotoInfo?> waitForPhoto(String name) async {
    await _gate;
    return await super.waitForPhoto(name);
  }
}
