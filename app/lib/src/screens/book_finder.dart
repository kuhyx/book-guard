import 'dart:async';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/national_library.dart';
import 'package:book_guard_app/src/open_library.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Finds a book by title (and optional author) on Open Library, or takes
/// its ISBN directly when Open Library does not have it.
class BookFinder extends StatefulWidget {
  /// Creates the finder.
  const new({
    required this.api,
    required this.onChanged,
    required this.library,
    required this.nationalLibrary,
    super.key,
  });

  /// The PC.
  final GuardApi api;

  /// Refetch after an action.
  final Future<void> Function() onChanged;

  /// Title search.
  final OpenLibrary library;

  /// Title search in the Polish national catalogue.
  final NationalLibrary nationalLibrary;

  @override
  State<BookFinder> createState() => _BookFinderState();
}

class _BookFinderState extends State<BookFinder> {
  final _query = TextEditingController();
  final _author = TextEditingController();
  final _isbn = TextEditingController();
  final _titleFocus = FocusNode();
  List<BookHit> _hits = const [];

  /// A registered ISBN no catalogue knew: search hits name it, instead of
  /// registering their own edition.
  String? _unknown;

  /// The title of the last search that came back empty, shown as a miss.
  String? _missed;
  bool _busy = false;

  @override
  void dispose() {
    _query.dispose();
    _author.dispose();
    _isbn.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on Exception catch (error) {
      if (mounted) showError(context, '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
      unawaited(widget.onChanged());
    }
  }

  Future<void> _search() async {
    final title = _query.text.trim();
    if (title.isEmpty) {
      showError(context, 'Enter a title to search.');
      return;
    }
    await _run(() async {
      final hits = await _searchBoth(title, _author.text.trim());
      if (!mounted) return;
      setState(() {
        _hits = hits;
        _missed = hits.isEmpty ? title : null;
      });
    });
  }

  /// Both catalogues at once; one failing still shows the other's hits.
  Future<List<BookHit>> _searchBoth(String title, String author) async {
    Future<List<BookHit>?> safe(Future<List<BookHit>> search) =>
        search.then<List<BookHit>?>((h) => h, onError: (Object _) => null);
    final [open, national] = await Future.wait([
      safe(widget.library.search(title, author: author)),
      safe(widget.nationalLibrary.search(title, author: author)),
    ]);
    if (open == null && national == null) {
      throw Exception('Neither Open Library nor Biblioteka Narodowa answered');
    }
    final seen = <String>{};
    return [
      for (final hit in [...?national, ...?open])
        if (hit.isbn == null || seen.add(hit.isbn!)) hit,
    ];
  }

  Future<GuardResponse?> _answer(Future<GuardResponse> request) async {
    final response = await request;
    if (!mounted) return null;
    response.ok
        ? showToast(context, response.message)
        : showError(context, response.message);
    return response;
  }

  /// A hit registers its own edition -- or, after an unknown ISBN, names
  /// that one. Pages stay blank then: the hit's median is another edition's.
  Future<void> _register(BookHit hit) => _run(() async {
    final unknown = _unknown;
    await _answer(
      widget.api.send(
        'register',
        unknown == null
            ? {'isbn': hit.isbn, 'pages': hit.pages}
            : {'isbn': unknown, 'title': hit.title, 'author': hit.author},
      ),
    );
    if (mounted) {
      setState(() {
        _hits = const [];
        _unknown = null;
      });
    }
  });

  /// Registers a typed ISBN; the title/author fields name it if no
  /// catalogue knows it. Unknown with no title typed sends the user to the
  /// title search, whose pick then names this ISBN.
  Future<void> _registerIsbn() => _run(() async {
    final isbn = _isbn.text.trim();
    final title = _query.text.trim();
    final response = await _answer(
      widget.api.send('register', {
        'isbn': isbn,
        'title': title,
        'author': _author.text.trim(),
      }),
    );
    if (response == null || !response.ok) return;
    final unknown = response.data?['known'] == false && title.isEmpty;
    setState(() => _unknown = unknown ? isbn : null);
    if (unknown) _titleFocus.requestFocus();
  });

  /// A red outline and a "nothing found" icon while the ISBN is unknown.
  InputDecoration _isbnDecoration(BuildContext context) {
    const label = 'ISBN (optional)';
    if (_unknown == null) return const InputDecoration(labelText: label);
    final error = Theme.of(context).colorScheme.error;
    final border = OutlineInputBorder(borderSide: BorderSide(color: error));
    return InputDecoration(
      labelText: label,
      enabledBorder: border,
      focusedBorder: border,
      suffixIcon: Icon(
        Icons.search_off,
        color: error,
        semanticLabel: 'No catalogue knows this ISBN',
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_busy) const LinearProgressIndicator(),
      const SectionHeader('Find a book'),
      TextField(
        controller: _query,
        focusNode: _titleFocus,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _search(),
        decoration: const InputDecoration(
          labelText: 'Title, e.g. Atomic Habits',
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      TextField(
        controller: _author,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _search(),
        decoration: const InputDecoration(labelText: 'Author (optional)'),
      ),
      const SizedBox(height: AppSpacing.sm),
      FilledButton.icon(
        onPressed: _busy ? null : _search,
        icon: const Icon(Icons.search),
        label: const Text('Search'),
      ),
      if (_missed != null)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Text("No books found for '$_missed' - enter the ISBN below."),
        ),
      for (final hit in _hits)
        ListTile(
          title: Text(hit.title),
          subtitle: Text(
            '${hit.author.isEmpty ? '?' : hit.author} - '
            '${hit.pages ?? '?'} p - ISBN ${hit.isbn ?? 'none'}',
          ),
          trailing: Icon(_unknown == null ? Icons.add : Icons.link),
          enabled: (_unknown != null || hit.isbn != null) && !_busy,
          onTap: () => _register(hit),
        ),
      const SectionHeader('Or enter the ISBN'),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _isbn,
              keyboardType: TextInputType.number,
              decoration: _isbnDecoration(context),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          OutlinedButton(
            onPressed: _busy ? null : _registerIsbn,
            child: const Text('Register'),
          ),
        ],
      ),
    ],
  );
}
