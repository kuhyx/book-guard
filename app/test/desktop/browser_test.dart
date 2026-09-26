import 'dart:io';

import 'package:book_guard_app/desktop/browser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('profileDir is fixed under ~/.local/share', () {
    expect(profileDir('/h'), '/h/.local/share/book-guard-desktop/profile');
  });

  group('findBrowser', () {
    test('an existing override wins', () {
      expect(
        findBrowser(override: '/my/chrome', exists: (_) => true),
        '/my/chrome',
      );
    });

    test('falls through the known locations in order', () {
      final present = {'/usr/bin/chromium', '/usr/bin/brave'};
      expect(
        findBrowser(override: '/missing', exists: present.contains),
        '/usr/bin/chromium',
      );
    });

    test('without an override the list still resolves', () {
      final env = Platform.environment['BOOK_GUARD_BROWSER'] ?? '';
      expect(
        findBrowser(exists: (path) => path == '/usr/bin/brave' || path == env),
        env.isEmpty ? '/usr/bin/brave' : env,
      );
    });

    test('is empty when nothing exists', () {
      expect(findBrowser(override: '', exists: (_) => false), '');
    });

    test('checks the real filesystem by default', () {
      final dir = Directory.systemTemp.createTempSync('bg_browser');
      addTearDown(() => dir.deleteSync(recursive: true));
      final exe = File(p.join(dir.path, 'chrome'))..createSync();
      expect(findBrowser(override: exe.path), exe.path);
    });
  });

  test('browserArgs opens an app window on the wrapper port', () {
    final args = browserArgs('/h');
    expect(args.first, '--app=http://localhost:8773');
    expect(args, contains('--user-data-dir=${profileDir('/h')}'));
    expect(args, containsAll(['--class=book-guard', '--password-store=basic']));
    expect(browserArgs('/h', port: 1234).first, '--app=http://localhost:1234');
  });
}
