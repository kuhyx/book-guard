import 'dart:async';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/national_library.dart';
import 'package:book_guard_app/src/open_library.dart';
import 'package:book_guard_app/src/screens/book_cues.dart';
import 'package:book_guard_app/src/ui/cues.dart';
import 'package:book_guard_app/src/ui/icon_field.dart';
import 'package:book_guard_app/src/ui/reply_cue.dart';
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

  /// Whether the last search came back empty (shown as a miss).
  bool _missed = false;

  /// A search was tried with no title: the title field is red.
  bool _titleEmpty = false;
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
      if (mounted) reportFailure(context, widget.api, 'finder', error);
    } finally {
      if (mounted) setState(() => _busy = false);
      unawaited(widget.onChanged());
    }
  }

  Future<void> _search() async {
    final title = _query.text.trim();
    if (title.isEmpty) {
      setState(() => _titleEmpty = true);
      showCue(
        context,
        const Cue(
          CueKind.error,
          icon: Icons.title,
          semanticLabel: 'Enter a title to search',
        ),
      );
      return;
    }
    await _run(() async {
      final hits = await _searchBoth(title, _author.text.trim());
      if (!mounted) return;
      setState(() {
        _hits = hits;
        _missed = hits.isEmpty;
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
    showReply(context, response);
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

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_busy) const LinearProgressIndicator(),
      const SizedBox(height: AppSpacing.md),
      IconField(
        icon: Icons.title,
        semanticLabel: 'Title, e.g. Atomic Habits',
        controller: _query,
        focusNode: _titleFocus,
        textInputAction: TextInputAction.search,
        onChanged: (_) {
          if (_titleEmpty) setState(() => _titleEmpty = false);
        },
        onSubmitted: (_) => _search(),
        errorBorder: _titleEmpty,
      ),
      const SizedBox(height: AppSpacing.sm),
      IconField(
        icon: Icons.person,
        semanticLabel: 'Author (optional)',
        controller: _author,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _search(),
      ),
      const SizedBox(height: AppSpacing.sm),
      Align(
        alignment: Alignment.centerLeft,
        child: GlyphButton(
          icon: Icons.search,
          semanticLabel: 'Search',
          filled: true,
          onPressed: _busy ? null : _search,
        ),
      ),
      if (_missed)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Center(
            child: Icon(
              Icons.search_off,
              size: 64,
              color: context.statusColors.warning,
              semanticLabel: 'No books found: enter the ISBN below',
            ),
          ),
        ),
      for (final hit in _hits)
        ListTile(
          title: Text(hit.title),
          subtitle: Wrap(
            spacing: AppSpacing.md,
            children: [
              if (hit.author.isNotEmpty) Text(hit.author),
              IconNumber(
                Icons.last_page,
                hit.pages == null ? '?' : '${hit.pages}',
                semanticLabel: 'Pages',
              ),
              if (hit.isbn case final isbn?)
                IconNumber(Icons.qr_code, isbn, semanticLabel: 'ISBN'),
            ],
          ),
          trailing: Icon(
            _unknown == null ? Icons.add : Icons.link,
            semanticLabel: _unknown == null ? 'Register' : 'Name the ISBN',
          ),
          enabled: (_unknown != null || hit.isbn != null) && !_busy,
          onTap: () => _register(hit),
        ),
      const SizedBox(height: AppSpacing.md),
      Row(
        children: [
          Expanded(
            child: IconField(
              icon: Icons.qr_code,
              semanticLabel: _unknown == null
                  ? 'ISBN (optional)'
                  : 'ISBN (optional), no catalogue knows it',
              controller: _isbn,
              keyboardType: TextInputType.number,
              errorBorder: _unknown != null,
              // Spoken by the field's own label below: a labelled icon
              // appearing inside the merged field node trips semantics.
              suffix: _unknown == null
                  ? null
                  : ExcludeSemantics(
                      child: Icon(
                        Icons.search_off,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          GlyphButton(
            icon: Icons.library_add,
            semanticLabel: 'Register',
            onPressed: _busy ? null : _registerIsbn,
          ),
        ],
      ),
    ],
  );
}
