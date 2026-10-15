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
  Uri? dufs,
}) async {
  final server = WrapperServer(
    webRoot: webRoot,
    loginEnv: loginEnv,
    dufs: dufs,
  );
  await server.start(port: port);
  return server;
}

/// Sandbox-preview overrides, never set in production: another wrapper
/// port, dufs and login file, so a preview never touches the live ones.
/// Returns (port, dufs or null for the live one, login env path).
(int, Uri?, String) previewOverrides(Map<String, String> env, String home) {
  final dufs = Uri.tryParse(env['BOOK_GUARD_DUFS_URL'] ?? '');
  return (
    int.tryParse(env['BOOK_GUARD_WRAPPER_PORT'] ?? '') ?? kWrapperPort,
    dufs != null && dufs.hasAuthority ? dufs : null,
    env['BOOK_GUARD_LOGIN_ENV'] ?? loginEnvPath(home),
  );
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
  ServerStarter? startServer,
  Map<String, String>? environment,
  String Function() browserFinder = findBrowser,
  ProcessStarter startProcess = Process.start,
  Future<void> Function()? hold,
  IOSink? err,
}) async {
  final log = err ?? stderr;
  final webRoot = resolveWebRoot(exeDir: exeDir, cwd: cwd);
  final (port, dufs, login) = previewOverrides(
    environment ?? Platform.environment,
    home,
  );
  final start =
      startServer ??
      (root, loginEnv) => startWrapper(root, loginEnv, port: port, dufs: dufs);
  try {
    await start(webRoot, File(login));
  } on SocketException {
    // Already serving: just open another window onto it.
    log.writeln('book-guard desktop: already running on :$port');
  }
  if (args.contains('--serve-only')) return;
  final browser = browserFinder();
  if (browser.isEmpty) {
    log.writeln(
      'book-guard desktop: no Chrome-family browser found; '
      'open http://localhost:$port or set BOOK_GUARD_BROWSER',
    );
    return;
  }
  final process = await startProcess(browser, browserArgs(home));
  await process.exitCode;
  await (hold ?? () => Future<void>.delayed(const Duration(days: 365)))();
}
