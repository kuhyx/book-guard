import 'dart:async';

import 'package:book_guard_app/src/login_store.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// The phone's dufs login: URL, user, password.
class SettingsScreen extends StatefulWidget {
  /// Creates the screen.
  const new({required this.store, required this.onSaved, super.key});

  /// Where the login is kept.
  final LoginStore store;

  /// Called after a successful save.
  final Future<void> Function() onSaved;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _password = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_fill());
  }

  Future<void> _fill() async {
    final login = await widget.store.load();
    if (!mounted) return;
    _url.text = login.url;
    _user.text = login.user;
    _password.text = login.password;
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final login = DufsLogin(
      url: _url.text.trim().replaceAll(RegExp(r'/+$'), ''),
      user: _user.text.trim(),
      password: _password.text.trim(),
    );
    if (!login.complete) {
      showError(context, 'Fill in all three fields.');
      return;
    }
    await widget.store.save(login);
    await widget.onSaved();
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Connection')),
    body: ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        const Text(
          'book-guard reads your photos and summaries from the dufs share. '
          'Use the "bookguard" login (scoped to the Reading folder).',
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _url,
          decoration: const InputDecoration(labelText: 'dufs URL'),
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _user,
          decoration: const InputDecoration(labelText: 'User'),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _password,
          decoration: const InputDecoration(labelText: 'Password'),
          obscureText: true,
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    ),
  );
}
