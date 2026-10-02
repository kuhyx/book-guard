import 'dart:async';

import 'package:book_guard_app/src/guard_api.dart';
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
    super.key,
  });

  /// The PC.
  final GuardApi api;

  /// Refetch after an action.
  final Future<void> Function() onChanged;

  /// Title search.
  final OpenLibrary library;

  @override
  State<BookFinder> createState() => _BookFinderState();
}

class _BookFinderState extends State<BookFinder> {
  final _query = TextEditingController();
  final _author = TextEditingController();
  final _isbn = TextEditingController();
  List<BookHit> _hits = const [];

  /// The title of the last search that came back empty, shown as a miss.
  String? _missed;
  bool _busy = false;

  @override
  void dispose() {
    _query.dispose();
    _author.dispose();
    _isbn.dispose();
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
      final hits = await widget.library.search(
        title,
        author: _author.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _hits = hits;
        _missed = hits.isEmpty ? title : null;
      });
    });
  }

  Future<void> _answer(Future<GuardResponse> request) async {
    final response = await request;
    if (!mounted) return;
    response.ok
        ? showToast(context, response.message)
        : showError(context, response.message);
  }

  Future<void> _register(BookHit hit) => _run(() async {
    await _answer(
      widget.api.send('register', {'isbn': hit.isbn, 'pages': hit.pages}),
    );
    if (mounted) setState(() => _hits = const []);
  });

  /// Registers a typed ISBN; the title/author fields name it if Open
  /// Library does not know it.
  Future<void> _registerIsbn() => _run(
    () => _answer(
      widget.api.send('register', {
        'isbn': _isbn.text.trim(),
        'title': _query.text.trim(),
        'author': _author.text.trim(),
      }),
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_busy) const LinearProgressIndicator(),
      const SectionHeader('Find a book'),
      TextField(
        controller: _query,
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
          trailing: const Icon(Icons.add),
          enabled: hit.isbn != null && !_busy,
          onTap: () => _register(hit),
        ),
      const SectionHeader('Or enter the ISBN'),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _isbn,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'ISBN (optional)'),
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
