import 'dart:async';

import 'package:book_guard_app/src/app.dart';
import 'package:book_guard_app/src/login_store.dart';
import 'package:book_guard_app/src/page_reader.dart';
import 'package:book_guard_app/src/self_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // The phone reads page numbers itself; the desktop web build leaves that
  // to the PC it runs on.
  final reader = kIsWeb ? null : createPageReader();
  unawaited(runSelfTestIfAsked(reader));
  runApp(
    BookGuardApp(
      // The desktop build runs from the local wrapper, which proxies WebDAV
      // at /dav with the login attached; only the phone keeps a login.
      desktop: kIsWeb,
      loginStore: LoginStore(),
      pageReader: reader,
    ),
  );
}
