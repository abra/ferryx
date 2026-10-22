import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

enum CaseTransform { unchanged, lower, upper, capitalize }

/// Which part of a name a search or a case change touches.
enum NamePart { whole, name, extension }

/// The Batch Rename dialog's settings; the placeholder language is
/// documented in the Rust core (`ferryx_core::batch_rename`).
@immutable
class RenameOptions extends Equatable {
  const RenameOptions({
    this.pattern = '[N].[E]',
    this.search = '',
    this.replace = '',
    this.searchRegex = false,
    this.searchCaseSensitive = false,
    this.searchOnce = false,
    this.searchPart = NamePart.whole,
    this.caseTransform = CaseTransform.unchanged,
    this.casePart = NamePart.whole,
    this.counterStart = 1,
    this.counterStep = 1,
    this.counterWidth = 1,
  });

  final String pattern;
  final String search;
  final String replace;
  final bool searchRegex;
  final bool searchCaseSensitive;
  final bool searchOnce;
  final NamePart searchPart;
  final CaseTransform caseTransform;
  final NamePart casePart;
  final int counterStart;
  final int counterStep;
  final int counterWidth;

  RenameOptions copyWith({
    String? pattern,
    String? search,
    String? replace,
    bool? searchRegex,
    bool? searchCaseSensitive,
    bool? searchOnce,
    NamePart? searchPart,
    CaseTransform? caseTransform,
    NamePart? casePart,
    int? counterStart,
    int? counterStep,
    int? counterWidth,
  }) => RenameOptions(
    pattern: pattern ?? this.pattern,
    search: search ?? this.search,
    replace: replace ?? this.replace,
    searchRegex: searchRegex ?? this.searchRegex,
    searchCaseSensitive: searchCaseSensitive ?? this.searchCaseSensitive,
    searchOnce: searchOnce ?? this.searchOnce,
    searchPart: searchPart ?? this.searchPart,
    caseTransform: caseTransform ?? this.caseTransform,
    casePart: casePart ?? this.casePart,
    counterStart: counterStart ?? this.counterStart,
    counterStep: counterStep ?? this.counterStep,
    counterWidth: counterWidth ?? this.counterWidth,
  );

  @override
  List<Object?> get props => [
    pattern,
    search,
    replace,
    searchRegex,
    searchCaseSensitive,
    searchOnce,
    searchPart,
    caseTransform,
    casePart,
    counterStart,
    counterStep,
    counterWidth,
  ];
}

enum RenameProblem { empty, invalid, duplicate }

@immutable
class RenameOutcome extends Equatable {
  const RenameOutcome({
    required this.path,
    required this.oldName,
    required this.newName,
    this.problem,
  });

  final String path;
  final String oldName;
  final String newName;
  final RenameProblem? problem;

  bool get changes => oldName != newName;

  @override
  List<Object?> get props => [path, oldName, newName, problem];
}

@immutable
class RenameFailure extends Equatable {
  const RenameFailure({required this.path, required this.message});

  final String path;
  final String message;

  @override
  List<Object?> get props => [path, message];
}
