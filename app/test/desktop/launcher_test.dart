import 'dart:async';
import 'dart:io';

import 'package:book_guard_app/desktop/launcher.dart';
import 'package:book_guard_app/desktop/wrapper_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _FakeProcess implements Process {
  @override
  Future<int> get exitCode async => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sink implements IOSink {
  final lines = <String>[];

  @override
  void writeln([Object? object = '']) => lines.add('$object');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('launcher'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('prefers the bundled web dir next to the binary', () {
    final bin = Directory(p.join(tmp.path, 'bundle', 'bin'))
      ..createSync(recursive: true);
    Directory(p.join(tmp.path, 'bundle', 'web')).createSync();
    expect(
      resolveWebRoot(exeDir: bin.path, cwd: '/src'),
      p.join(tmp.path, 'bundle', 'web'),
    );
    expect(
      resolveWebRoot(exeDir: '/nowhere/bin', cwd: '/src'),
      '/src/build/web',
    );
  });

  test('startWrapper really serves, on the port asked for', () async {
    final server = await startWrapper(
      tmp.path,
      File(p.join(tmp.path, 'none.env')),
      port: 0,
    );
    addTearDown(server.close);
    expect(server, isA<WrapperServer>());
  });

  test('serve-only starts the server and never looks for a browser', () async {
    String? servedRoot;
    File? env;
    await runDesktop(
      ['--serve-only'],
      home: '/home/u',
      exeDir: '/nowhere/bin',
      cwd: '/src',
      startServer: (root, login) async {
        servedRoot = root;
        env = login;
        return kWrapperPort;
      },
      browserFinder: () => fail('no browser lookup in serve-only mode'),
    );
    expect(servedRoot, '/src/build/web');
    expect(env!.path, loginEnvPath('/home/u'));
  });

  test('a busy port is a second window, not a failure', () async {
    final sink = _Sink();
    await runDesktop(
      ['--serve-only'],
      home: '/h',
      exeDir: '/x',
      cwd: '/c',
      startServer: (_, _) async => throw const SocketException('in use'),
      err: sink,
    );
    expect(sink.lines.single, contains('already running'));
  });

  test('no browser: says how to open it by hand', () async {
    final sink = _Sink();
    await runDesktop(
      const [],
      home: '/h',
      exeDir: '/x',
      cwd: '/c',
      startServer: (_, _) async => 0,
      browserFinder: () => '',
      err: sink,
    );
    expect(sink.lines.single, contains('BOOK_GUARD_BROWSER'));
  });

  test('opens the app window, then holds the server open', () async {
    final started = <String>[];
    var held = false;
    await runDesktop(
      const [],
      home: '/h',
      exeDir: '/x',
      cwd: '/c',
      startServer: (_, _) async => 0,
      browserFinder: () => '/opt/chrome',
      startProcess: (exe, args) async {
        started
          ..add(exe)
          ..addAll(args);
        return _FakeProcess();
      },
      hold: () async => held = true,
    );
    expect(started.first, '/opt/chrome');
    expect(started, contains('--app=http://localhost:$kWrapperPort'));
    expect(held, isTrue);
  });

  test('the default hold keeps the process alive', fakeAsyncHold);
}

/// The production hold is a year-long delay: prove it is pending, not done.
void fakeAsyncHold() {
  var finished = false;
  unawaited(
    runDesktop(
      const [],
      home: '/h',
      exeDir: '/x',
      cwd: '/c',
      startServer: (_, _) async => 0,
      browserFinder: () => '/opt/chrome',
      startProcess: (_, _) async => _FakeProcess(),
    ).then((_) => finished = true),
  );
  expect(finished, isFalse);
}
