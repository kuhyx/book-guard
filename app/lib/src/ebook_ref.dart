/// `state.json`'s `book.ebook` (split out of `guard_state.dart`, which
/// re-exports it).
library;

/// Where the in-app reader's text and page map are on the share.
class EbookRef {
  /// Creates a reference.
  const new({
    required this.map,
    required this.text,
    required this.textSha,
    this.generatedAt = '',
  });

  /// Parses `book.ebook`; null when the book has no page map.
  static EbookRef? fromJson(Object? json) => json is Map<String, dynamic>
      ? EbookRef(
          map: '${json['map'] ?? ''}',
          text: '${json['text'] ?? ''}',
          textSha: '${json['text_sha'] ?? ''}',
          generatedAt: '${json['generated_at'] ?? ''}',
        )
      : null;

  /// The map's path under `Reading/`.
  final String map;

  /// The text's path under `Reading/`.
  final String text;

  /// sha256 (hex) of the text's UTF-8 bytes.
  final String textSha;

  /// When the PC built the map: a newer one is downloaded.
  final String generatedAt;
}
