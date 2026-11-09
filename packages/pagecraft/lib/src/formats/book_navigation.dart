/// Navigation entries shared by every format: a table of contents, page
/// list or landmarks list, as `epub.js`, `fb2.js` and `mobi.js` all
/// produce them.
library;

import 'package:meta/meta.dart';

/// An entry of a table of contents, page list or landmarks list.
///
/// [href] is a container path with an optional fragment, already
/// resolved against the navigation document, or null for a heading
/// without a target. [type] holds the `epub:type` values of a landmark.
@immutable
class BookNavItem {
  const BookNavItem({
    required this.label,
    required this.href,
    this.subitems,
    this.type,
  });

  final String label;
  final String? href;
  final List<BookNavItem>? subitems;
  final List<String>? type;

  @override
  bool operator ==(Object other) =>
      other is BookNavItem &&
      other.label == label &&
      other.href == href &&
      _listEquals(other.subitems, subitems) &&
      _listEquals(other.type, type);

  @override
  int get hashCode => Object.hash(
    label,
    href,
    subitems == null ? null : Object.hashAll(subitems!),
    type == null ? null : Object.hashAll(type!),
  );

  @override
  String toString() =>
      'BookNavItem($label → $href${subitems == null ? '' : ', ${subitems!.length} sub'})';
}

bool _listEquals<T>(List<T>? a, List<T>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
