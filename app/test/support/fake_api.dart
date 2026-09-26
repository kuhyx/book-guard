import 'dart:typed_data';

import 'package:book_guard_app/src/dav_client.dart';
import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_share.dart';

/// One call to [FakeApi.send].
typedef SentRequest = ({String type, Map<String, Object?> body});

/// A [GuardApi] whose PC answers from fields, for widget tests.
class FakeApi extends GuardApi {
  /// Creates the fake; its own share is never touched.
  new({this.state}) : super(FakeShare().dav());

  /// What [fetchState] returns.
  GuardState? state;

  /// When set, [fetchState] throws it.
  Exception? fetchError;

  /// How many times the snapshot was fetched.
  int fetches = 0;

  /// Every request sent.
  final List<SentRequest> sent = [];

  /// The PC's answer; defaults to ok.
  Future<GuardResponse> Function(SentRequest request)? onSend;

  /// Uploaded photos by name.
  final Map<String, Uint8List> photos = {};

  /// Uploaded books by name.
  final Map<String, Uint8List> books = {};

  /// When set, uploads throw it.
  Exception? uploadError;

  @override
  Future<GuardState?> fetchState() async {
    fetches++;
    final error = fetchError;
    if (error != null) throw error;
    return state;
  }

  @override
  Future<GuardResponse> send(String type, Map<String, Object?> body) async {
    final request = (type: type, body: body);
    sent.add(request);
    final answer = onSend;
    if (answer == null) return GuardResponse(ok: true, message: 'done $type');
    return await answer(request);
  }

  @override
  Future<void> uploadPhoto(String name, Uint8List bytes) async {
    final error = uploadError;
    if (error != null) throw error;
    photos[name] = bytes;
  }

  @override
  Future<void> uploadBook(String name, Uint8List bytes) async {
    final error = uploadError;
    if (error != null) throw error;
    books[name] = bytes;
  }
}

/// A failure the tabs should show, not throw.
DavException shareDown() => const DavException('Reading/x', 500);

/// Hosts [child] the way the app does: themed, inside a Scaffold.
Future<void> pumpTab(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(body: child),
    ),
  );
  await tester.pump();
}

/// Scrolls [finder] into view, then taps it.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

/// Pumps a few frames so chained futures and setState land.
Future<void> settle(WidgetTester tester, [int frames = 5]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}
