import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:book_guard_app/src/dav_client.dart';
import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/local_store.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fake_share.dart';

/// A real [GuardApi] over an in-memory share, for the Library screens.
GuardApi libraryApi(FakeShare share) =>
    GuardApi(share.dav(), random: Random(1), pollEvery: Duration.zero);

/// A [GuardApi] whose share never answers until [release] is called.
class HungShare {
  final _gate = Completer<void>();

  /// The API; every request waits on the gate, then reports "not found".
  late final GuardApi api = apiWith(null);

  /// The same hung share over an existing device [store].
  GuardApi apiWith(LocalStore? store) => GuardApi(
    DavClient(
      baseUrl: fakeShareUrl,
      client: MockClient((request) async {
        await _gate.future;
        return http.Response('', 404);
      }),
    ),
    random: Random(1),
    store: store,
  );

  /// Lets the waiting requests through.
  void release() => _gate.complete();
}

/// A valid 1x1 PNG, so Image.memory has something to decode.
final Uint8List tinyPng = Uint8List.fromList([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00, //
  0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8, 0xcf, 0xc0, 0xf0, //
  0x1f, 0x00, 0x05, 0x00, 0x01, 0xff, 0x89, 0x99, 0x3d, 0x1d, 0x00, 0x00, //
  0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]);

/// Puts [library] on the share the way the PC does.
void putLibrary(FakeShare share, Map<String, dynamic> library) =>
    share.putText('Reading/library.json', jsonEncode(library));

/// Makes the test surface tall enough to build a whole list.
void tallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 3000);
  addTearDown(tester.view.reset);
}
