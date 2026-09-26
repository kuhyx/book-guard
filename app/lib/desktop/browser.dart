/// Finding and launching the Chrome window the desktop app runs in.
library;

import 'dart:io';

import 'package:book_guard_app/desktop/wrapper_server.dart';
import 'package:path/path.dart' as p;

/// Browser profile for the app. Fixed: a moving profile is a fresh browser
/// with none of the window state, and a second instance would fight over it.
String profileDir(String home) =>
    p.join(home, '.local', 'share', 'book-guard-desktop', 'profile');

/// The first Chrome-family browser on this machine, or ''.
///
/// Broad on purpose: this machine runs Thorium behind /opt/google/chrome and
/// has a policy that uninstalls `chromium`. `$BOOK_GUARD_BROWSER` overrides.
String findBrowser({String? override, bool Function(String path)? exists}) {
  final candidates = [
    override ?? Platform.environment['BOOK_GUARD_BROWSER'] ?? '',
    '/opt/google/chrome/chrome',
    '/opt/thorium-browser/thorium-browser',
    '/usr/bin/google-chrome-stable',
    '/usr/bin/chromium',
    '/usr/bin/brave',
  ];
  return candidates.firstWhere(
    (path) => path.isNotEmpty && (exists ?? (x) => File(x).existsSync())(path),
    orElse: () => '',
  );
}

/// Arguments for the app window.
List<String> browserArgs(String home, {int port = kWrapperPort}) => [
  '--app=http://localhost:$port',
  '--user-data-dir=${profileDir(home)}',
  // WM_CLASS, matched by the .desktop entry's StartupWMClass.
  '--class=book-guard',
  '--no-first-run',
  // Keeps Chrome off the GNOME keyring: a locked keyring blocks the first
  // page load behind an unlock prompt on another workspace.
  '--password-store=basic',
];
