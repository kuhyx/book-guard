/// `book-guard-desktop`: serve the web build, open it in a Chrome app window.
///
/// Only wiring: every decision lives in `lib/desktop/launcher.dart`.
library;

import 'dart:io';

import 'package:book_guard_app/desktop/launcher.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) => runDesktop(
  args,
  home: Platform.environment['HOME'] ?? '',
  exeDir: p.dirname(Platform.resolvedExecutable),
  cwd: Directory.current.path,
);
