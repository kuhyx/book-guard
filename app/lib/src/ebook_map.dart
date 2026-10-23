import 'dart:math';

/// One point of the page map: a text offset and its continuous page (page
/// `N` covers `[N, N + 1)`).
typedef Knot = ({int offset, double page});

/// The PC's estimate of the paper copy's page at every offset of the
/// served ebook text (`book_guard/_ebook_map.py` PageMap).
///
/// Built on the PC from the photographed pages; the app only reads it, to
/// show "≈ p. N" and to open the reader where the paper reading stopped.
/// The PC computes the credited pages with its own copy -- this port uses
/// the same arithmetic in the same order so both floor alike
/// (`test/fixtures/ebook_map_goldens.json`).
class EbookMap {
  /// Creates a map.
  const new({
    required this.knots,
    required this.start,
    required this.end,
    required this.lastPage,
    required this.photos,
    this.isbn = '',
    this.textPath = '',
    this.textSha = '',
    this.chars = 0,
  });

  /// Parses `Reading/ebooks/<isbn>.map.json`; null when it is not a map.
  static EbookMap? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final raw = json['knots'];
    if (raw is! List || raw.length < 2) return null;
    final knots = <Knot>[];
    for (final k in raw) {
      if (k is! List || k.length != 2 || k[0] is! num || k[1] is! num) {
        return null;
      }
      knots.add((
        offset: (k[0] as num).toInt(),
        page: (k[1] as num).toDouble(),
      ));
    }
    for (var i = 1; i < knots.length; i++) {
      final (a, b) = (knots[i - 1], knots[i]);
      if (a.offset >= b.offset || a.page >= b.page) return null;
    }
    return EbookMap(
      knots: knots,
      start: _int(json['start']) ?? 0,
      end: _int(json['end']) ?? knots.last.offset,
      lastPage: _int(json['last_page']),
      photos: _int(json['photos']) ?? 0,
      isbn: '${json['isbn'] ?? ''}',
      textPath: '${json['text'] ?? ''}',
      textSha: '${json['text_sha'] ?? ''}',
      chars: _int(json['chars']) ?? 0,
    );
  }

  /// Knots, strictly rising in offset and page.
  final List<Knot> knots;

  /// Where the story starts in the text.
  final int start;

  /// Where it ends (back matter after it).
  final int end;

  /// The copy's last page, if known.
  final int? lastPage;

  /// How many photographed pages the map rests on.
  final int photos;

  /// The book.
  final String isbn;

  /// The text's path under `Reading/`.
  final String textPath;

  /// sha256 (hex) of the text's UTF-8 bytes.
  final String textSha;

  /// The text's length.
  final int chars;

  /// The continuous page at [offset]: linear between knots, flat outside.
  double coordinate(int offset) {
    if (offset <= knots.first.offset) return knots.first.page;
    if (offset >= knots.last.offset) return knots.last.page;
    var i = 0;
    while (knots[i].offset <= offset) {
      i++;
    }
    final (a, b) = (knots[i - 1], knots[i]);
    return a.page +
        (b.page - a.page) * (offset - a.offset) / (b.offset - a.offset);
  }

  /// The paper page [offset] falls on (`lastPage + 1` at the very end):
  /// reading from `a` to `b` covers `pageAt(b) - pageAt(a)` pages.
  int pageAt(int offset) => max(1, coordinate(offset).floor());

  /// The page to show: never past the book's last page.
  int shownPage(int offset) {
    final page = pageAt(offset);
    final last = lastPage;
    return last != null && last > 0 ? min(page, last) : page;
  }

  /// The first offset on [page] ([chars] when the text ends before it).
  int startOf(int page) {
    var (lo, hi) = (0, chars);
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (pageAt(mid) >= page) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return lo;
  }

  /// An offset on [page] (its middle); the nearest end outside the map.
  int offsetAt(int page) {
    final target = page + 0.5;
    if (target <= knots.first.page) return knots.first.offset;
    if (target >= knots.last.page) return knots.last.offset;
    var i = 0;
    while (knots[i].page <= target) {
      i++;
    }
    final (a, b) = (knots[i - 1], knots[i]);
    return (a.offset +
            (b.offset - a.offset) * (target - a.page) / (b.page - a.page))
        .floor();
  }
}

int? _int(Object? raw) => raw is num ? raw.toInt() : null;
