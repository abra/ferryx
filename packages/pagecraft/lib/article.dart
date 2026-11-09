/// Saved articles on the pagecraft core (the WebView's article shell): the
/// cleaned markup as a `TextBookSource`, sentence anchors, selection
/// payloads, search and the contents, read in one scrolling column.
library;

export 'pagecraft.dart';
export 'src/article/article_anchor.dart'
    show ArticleAnchor, ArticleSelection, normalizeArticleText, textContentOf;
export 'src/article/article_index.dart';
export 'src/article/article_search.dart';
export 'src/article/article_text_source.dart';
