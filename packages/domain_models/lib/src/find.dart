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
    this.useSpotlight = false,
    this.modifiedWithinDays,
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

  /// Ask the Spotlight index first (macOS); the folders are walked when it
  /// cannot answer.
  final bool useSpotlight;

  /// A relative date range, evaluated again each time a saved search runs.
  final int? modifiedWithinDays;

  Map<String, Object?> toJson() => {
    'root': root,
    'name': name,
    'nameIsRegex': nameIsRegex,
    'includeHidden': includeHidden,
    'includeFolders': includeFolders,
    'useSpotlight': useSpotlight,
    'modifiedWithinDays': modifiedWithinDays,
    if (content case final query?)
      'content': {
        'text': query.text,
        'caseSensitive': query.caseSensitive,
        'wholePhrase': query.wholePhrase,
        'notContaining': query.notContaining,
      },
    if (size case final condition?)
      'size': {'op': condition.op.name, 'bytes': condition.bytes},
  };

  static FindRequest? fromJson(Map<String, Object?> json) {
    final root = json['root'];
    if (root is! String ||
        root.trim().isEmpty ||
        root.length > 32768 ||
        root.contains('\u0000')) {
      return null;
    }
    final name = json['name'];
    final days = json['modifiedWithinDays'];
    if (days != null && (days is! int || days < 1 || days > 36500)) return null;
    ContentQuery? content;
    if (json['content'] case final Map<String, Object?> value) {
      final text = value['text'];
      if (text is! String || text.length > 65536) return null;
      content = ContentQuery(
        text: text,
        caseSensitive: value['caseSensitive'] == true,
        wholePhrase: value['wholePhrase'] != false,
        notContaining: value['notContaining'] == true,
      );
    }
    SizeCondition? size;
    if (json['size'] case final Map<String, Object?> value) {
      final op = SizeOp.values.asNameMap()[value['op']];
      final bytes = value['bytes'];
      if (op == null || bytes is! int || bytes < 0) return null;
      size = SizeCondition(op: op, bytes: bytes);
    }
    return FindRequest(
      root: root,
      name: name is String ? name : '',
      nameIsRegex: json['nameIsRegex'] == true,
      content: content,
      size: size,
      includeHidden: json['includeHidden'] == true,
      includeFolders: json['includeFolders'] != false,
      useSpotlight: json['useSpotlight'] == true,
      modifiedWithinDays: days as int?,
    );
  }

  @override
  List<Object?> get props => [
    root,
    name,
    nameIsRegex,
    content,
    size,
    includeHidden,
    includeFolders,
    useSpotlight,
    modifiedWithinDays,
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
    this.spotlightFailed = false,
  });

  final int findId;
  final List<FindHit> hits;
  final String? current;
  final int scanned;
  final bool done;
  final String? error;

  /// The search asked Spotlight, which could not answer: the folders were
  /// walked instead.
  final bool spotlightFailed;

  @override
  List<Object?> get props => [
    findId,
    hits,
    current,
    scanned,
    done,
    error,
    spotlightFailed,
  ];
}
