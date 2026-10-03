import 'dart:typed_data';

import 'package:book_guard_app/src/dav_client.dart';
import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';
import 'package:book_guard_app/src/page_number.dart';
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

  /// Files [fetchBytes] serves, by `Reading/`-relative path.
  final Map<String, Uint8List> files = {};

  /// Every path [fetchBytes] was asked for.
  final List<String> fetched = [];

  /// What [waitFor] finds (if its test holds); null = the PC never answers.
  GuardState? awaited;

  /// What [waitForPhoto] returns per uploaded name; absent = not read yet.
  final Map<String, PhotoInfo> readings = {};

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
  Future<(String, bool)> uploadPhoto(String name, Uint8List bytes) async {
    final error = uploadError;
    if (error != null) throw error;
    photos[name] = bytes;
    return (name, !offline);
  }

  /// When true, the outbox cannot reach the PC.
  bool offline = false;

  /// What the next [collectAnswers] returns (then it is emptied).
  List<LateAnswer> answers = [];

  @override
  Future<List<LateAnswer>> collectAnswers() async {
    final found = answers;
    answers = [];
    return found;
  }

  /// What each queued photo's sidecar said, by name.
  final Map<String, ({int? page, Box? box})> notes = {};

  @override
  Future<int> flush() async => offline ? 1 : 0;

  @override
  Future<String> queuePhoto(
    String label,
    String fileName,
    Uint8List bytes, {
    int? page,
    Box? box,
    DateTime? takenAt,
  }) async {
    final error = uploadError;
    if (error != null) throw error;
    final name = safeName('${label}_$fileName');
    photos[name] = bytes;
    notes[name] = (page: page, box: box);
    return name;
  }

  @override
  Future<GuardResponse> sendQueued(
    String type,
    Map<String, Object?> body,
    String what,
  ) async {
    if (offline) {
      sent.add((type: type, body: body));
      return const GuardResponse(ok: true, message: 'Saved on the phone');
    }
    return await send(type, body);
  }

  @override
  Future<Uint8List?> fetchBytes(String path) async {
    fetched.add(path);
    return files[path];
  }

  @override
  Future<GuardState?> waitFor(bool Function(GuardState state) test) async {
    final found = awaited;
    return found != null && test(found) ? found : null;
  }

  @override
  Future<PhotoInfo?> waitForPhoto(String name) async => readings[name];

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

/// A photo reading the way the PC reports it.
PhotoInfo reading({
  String name = 'x.jpg',
  String kind = 'page',
  int? page = 19,
  String status = 'ok',
  String reason = '',
}) => PhotoInfo(
  name: name,
  file: 'processed/abc-$name',
  thumb: 'thumbs/abc.jpg',
  kind: kind,
  page: page,
  status: status,
  reason: reason,
  takenAt: DateTime.utc(2026, 10, 2, 18, 14),
);
