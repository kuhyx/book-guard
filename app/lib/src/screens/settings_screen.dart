import 'dart:async';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/login_store.dart';
import 'package:book_guard_app/src/screens/reading_settings.dart';
import 'package:book_guard_app/src/ui/cues.dart';
import 'package:book_guard_app/src/ui/icon_field.dart';
import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

/// The phone's dufs login (link, person and key fields) and, once
/// connected, the way to the reading settings. A save with a field empty
/// reddens the empty ones and shows an error cue.
class SettingsScreen extends StatefulWidget {
  /// Creates the screen.
  const new({required this.store, required this.onSaved, super.key, this.api});

  /// The connected API; null on the first run (no reading settings yet).
  final GuardApi? api;

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

  /// A save was tried: the empty fields are red.
  bool _tried = false;

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
      setState(() => _tried = true);
      showCue(
        context,
        const Cue(CueKind.error, semanticLabel: 'Fill in all three fields'),
      );
      return;
    }
    await widget.store.save(login);
    await widget.onSaved();
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  /// Whether [c] is empty after a save was tried.
  bool _red(TextEditingController c) => _tried && c.text.trim().isEmpty;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        IconField(
          icon: Icons.link,
          semanticLabel: 'dufs URL',
          controller: _url,
          keyboardType: TextInputType.url,
          errorBorder: _red(_url),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.sm),
        IconField(
          icon: Icons.person,
          semanticLabel: 'User',
          controller: _user,
          errorBorder: _red(_user),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.sm),
        IconField(
          icon: Icons.key,
          semanticLabel: 'Password',
          controller: _password,
          obscure: true,
          errorBorder: _red(_password),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.lg),
        Align(
          alignment: Alignment.centerLeft,
          child: GlyphButton(
            icon: Icons.check,
            semanticLabel: 'Save',
            filled: true,
            onPressed: _save,
          ),
        ),
        if (widget.api case final api?) ...[
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: Alignment.centerLeft,
            child: GlyphButton(
              icon: Icons.text_fields,
              semanticLabel: 'Reading',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ReadingSettingsScreen(api: api),
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}
