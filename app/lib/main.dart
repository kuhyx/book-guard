import 'package:book_guard_app/src/app.dart';
import 'package:book_guard_app/src/login_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(
    BookGuardApp(
      // The desktop build runs from the local wrapper, which proxies WebDAV
      // at /dav with the login attached; only the phone keeps a login.
      desktop: kIsWeb,
      loginStore: LoginStore(),
    ),
  );
}
