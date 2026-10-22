import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

@immutable
class ContentQuery extends Equatable {
  const ContentQuery({
    required this.text,
    this.caseSensitive = false,
    this.wholePhrase = true,
    this.notContaining = false,
  });

  final String text;
  final bool caseSensitive;

  /// The text as one phrase; else every word of it, in any order.
  final bool wholePhrase;

  /// Files that do *not* contain the text.
  final bool notContaining;

  @override
  List<Object?> get props => [text, caseSensitive, wholePhrase, notContaining];
}

enum SizeOp { less, equal, greater }

@immutable
class SizeCondition extends Equatable {
  const SizeCondition({required this.op, required this.bytes});

  final SizeOp op;
  final int bytes;

  @override
  List<Object?> get props => [op, bytes];
}

@immutable
class FindRequest extends Equatable {
  const FindRequest({
    required this.root,
    this.name = '',
    this.nameIsRegex = false,
    this.content,
    this.size,
    this.includeHidden = false,
    this.includeFolders = true,
  });

  final String root;

  /// A mask (`*.txt;*.md`) or, with [nameIsRegex], a regular expression;
  /// empty for every name.
  final String name;
  final bool nameIsRegex;
  final ContentQuery? content;
  final SizeCondition? size;
  final bool includeHidden;
  final bool includeFolders;

  @override
  List<Object?> get props => [
    root,
    name,
    nameIsRegex,
    content,
    size,
    includeHidden,
    includeFolders,
  ];
}

@immutable
class FindHit extends Equatable {
  const FindHit({
    required this.path,
    required this.isDir,
    required this.size,
    this.modified,
  });

  final String path;
  final bool isDir;
  final int size;
  final DateTime? modified;

  String get name {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? path : path.substring(slash + 1);
  }

  String get parentPath {
    final slash = path.lastIndexOf('/');
    return slash <= 0 ? '/' : path.substring(0, slash);
  }

  @override
  List<Object?> get props => [path, isDir, size, modified];
}

/// What a running search says: hits so far, where it is, whether it ended.
@immutable
class FindUpdate extends Equatable {
  const FindUpdate({
    required this.findId,
    this.hits = const [],
    this.current,
    this.scanned = 0,
    this.done = false,
    this.error,
  });

  final int findId;
  final List<FindHit> hits;
  final String? current;
  final int scanned;
  final bool done;
  final String? error;

  @override
  List<Object?> get props => [findId, hits, current, scanned, done, error];
}
