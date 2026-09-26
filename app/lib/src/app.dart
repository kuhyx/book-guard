import 'dart:async';

import 'package:book_guard_app/src/dav_client.dart';
import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/login_store.dart';
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
  });

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
    if (!mounted) return;
    setState(() {
      _api = dav == null ? null : (widget.apiFactory ?? GuardApi.new)(dav);
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
