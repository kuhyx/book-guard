import 'dart:async';

import 'package:book_guard_app/src/dav_client.dart';
import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/local_store.dart';
import 'package:book_guard_app/src/login_store.dart';
import 'package:book_guard_app/src/page_reader.dart';
import 'package:book_guard_app/src/screens/home_screen.dart';
import 'package:book_guard_app/src/screens/settings_screen.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// The root widget: one app for the phone and the desktop web build.
class BookGuardApp extends StatefulWidget {
  /// Creates the app.
  const new({
    required this.desktop,
    required this.loginStore,
    super.key,
    this.apiFactory,
    this.pageReader,
    this.storeFactory,
  });

  /// On-device page-number reading; null on the desktop.
  final PageReader? pageReader;

  /// Opens the device's store; replaced in tests.
  final Future<LocalStore> Function()? storeFactory;

  /// Whether this is the desktop build served by the local wrapper.
  final bool desktop;

  /// The phone's login store.
  final LoginStore loginStore;

  /// Builds the API for a login; replaced in tests.
  final GuardApi Function(DavClient dav)? apiFactory;

  @override
  State<BookGuardApp> createState() => _BookGuardAppState();
}

class _BookGuardAppState extends State<BookGuardApp> {
  GuardApi? _api;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_connect());
  }

  Future<void> _connect() async {
    DavClient? dav;
    if (widget.desktop) {
      dav = DavClient(baseUrl: Uri.base.resolve(kWrapperDavPath).toString());
    } else {
      final login = await widget.loginStore.load();
      if (login.complete) {
        dav = DavClient(
          baseUrl: login.url,
          user: login.user,
          password: login.password,
        );
      }
    }
    final factory = widget.apiFactory;
    final api = dav == null
        ? null
        : factory != null
        ? factory(dav)
        : GuardApi(
            dav,
            // Opened only once there is a share to talk to: the outbox,
            // the photo journal and the last snapshot live here.
            store: await (widget.storeFactory ?? createLocalStore)(),
            host: widget.desktop ? 'desktop' : 'phone',
          );
    if (!mounted) return;
    setState(() {
      _api = api;
      _loading = false;
    });
  }

  Future<void> _onSaved() async {
    setState(() => _loading = true);
    await _connect();
  }

  @override
  Widget build(BuildContext context) {
    final api = _api;
    return MaterialApp(
      title: 'Book Guard',
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      home: _loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : api == null
          ? SettingsScreen(store: widget.loginStore, onSaved: _onSaved)
          : HomeScreen(
              api: api,
              desktop: widget.desktop,
              reader: widget.pageReader,
              // The Navigator lives below MaterialApp, so HomeScreen pushes
              // this page with its own context.
              settingsPage: widget.desktop
                  ? null
                  : () => SettingsScreen(
                      store: widget.loginStore,
                      onSaved: _onSaved,
                    ),
            ),
    );
  }
}
