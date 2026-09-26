/// The desktop launcher's logic, kept out of `bin/` so it is testable.
///
/// The server outlives the browser on purpose: Chrome exits at once when it
/// hands the URL to an instance that already owns the profile, so an early
/// exit is a handoff, not "the user closed the window".
library;

import 'dart:io';

import 'package:book_guard_app/desktop/browser.dart';
import 'package:book_guard_app/desktop/wrapper_server.dart';
import 'package:path/path.dart' as p;

/// Starts serving. Replaced in tests.
typedef ServerStarter = Future<Object> Function(String webRoot, File loginEnv);

/// Starts the browser process. Replaced in tests.
typedef ProcessStarter = Future<Process> Function(
  String executable,
  List<String> args,
);

/// The real starter: a [WrapperServer] on [port] (0 = any, for tests),
/// returned so a caller can close it.
Future<WrapperServer> startWrapper(
  String webRoot,
  File loginEnv, {
  int port = kWrapperPort,
}) async {
  final server = WrapperServer(webRoot: webRoot, loginEnv: loginEnv);
  await server.start(port: port);
  return server;
}

/// Where the web build is: next to the installed binary (`bundle/web`), or
/// `build/web` under [cwd] for a source run.
String resolveWebRoot({required String exeDir, required String cwd}) {
  final bundled = p.normalize(p.join(exeDir, '..', 'web'));
  return Directory(bundled).existsSync()
      ? bundled
      : p.join(cwd, 'build', 'web');
}

/// Runs the desktop app: serve, then open the app window and stay alive.
///
/// Returns once the window's process exits and [hold] completes (forever in
/// production -- the wrapper keeps serving for a handed-off window).
Future<void> runDesktop(
  List<String> args, {
  required String home,
  required String exeDir,
  required String cwd,
  ServerStarter startServer = startWrapper,
  String Function() browserFinder = findBrowser,
  ProcessStarter startProcess = Process.start,
  Future<void> Function()? hold,
  IOSink? err,
}) async {
  final log = err ?? stderr;
  final webRoot = resolveWebRoot(exeDir: exeDir, cwd: cwd);
  try {
    await startServer(webRoot, File(loginEnvPath(home)));
  } on SocketException {
    // Already serving: just open another window onto it.
    log.writeln('book-guard desktop: already running on :$kWrapperPort');
  }
  if (args.contains('--serve-only')) return;
  final browser = browserFinder();
  if (browser.isEmpty) {
    log.writeln(
      'book-guard desktop: no Chrome-family browser found; '
      'open http://localhost:$kWrapperPort or set BOOK_GUARD_BROWSER',
    );
    return;
  }
  final process = await startProcess(browser, browserArgs(home));
  await process.exitCode;
  await (hold ?? () => Future<void>.delayed(const Duration(days: 365)))();
}
