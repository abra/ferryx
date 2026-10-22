import 'package:component_library/component_library.dart';
import 'package:equatable/equatable.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:shortcuts/shortcuts.dart';

/// Jump to Folder (⌘G): the folders the panels showed, the most frecent
/// first, narrowed zoxide's way by what is typed. Answers the folder
/// picked and how: Return for the active panel, ⌘Return for a new tab,
/// ⌥Return for the other panel. [exclude] (the folder the panel is in) is
/// not offered.
Future<AppQuickPick<String>?> showJumpToFolder(
  BuildContext context, {
  required FolderFrecency frecency,
  required String home,
  String? exclude,
  String initialQuery = '',
}) => showAppQuickPicker<AppQuickPick<String>>(
  context,
  builder: (context) => BlocProvider(
    create: (_) => FolderJumpCubit(
      frecency: frecency,
      exclude: exclude,
      initialQuery: initialQuery,
    ),
    child: FolderJumpView(home: home, initialQuery: initialQuery),
  ),
);

@immutable
class FolderJumpState extends Equatable {
  const FolderJumpState({this.query = '', this.matches = const []});

  final String query;
  final List<FolderMatch> matches;

  @override
  List<Object?> get props => [query, matches];
}

/// The folders matching what is typed, from [FolderFrecency.query].
class FolderJumpCubit extends Cubit<FolderJumpState> {
  FolderJumpCubit({
    required FolderFrecency frecency,
    this.exclude,
    String initialQuery = '',
  }) : _frecency = frecency,
       super(
         FolderJumpState(
           query: initialQuery,
           matches: frecency.query(initialQuery, exclude: exclude),
         ),
       );

  final FolderFrecency _frecency;
  final String? exclude;

  void setQuery(String query) {
    if (query == state.query) return;
    emit(
      FolderJumpState(
        query: query,
        matches: _frecency.query(query, exclude: exclude),
      ),
    );
  }
}

/// A folder as the jump lists it: its name, and the folder it is in with
/// `~` for the home folder, each with the ranges the query matched (the
/// ranges of the whole path, moved into the two).
@immutable
class FolderLabel extends Equatable {
  const FolderLabel({
    required this.name,
    required this.parent,
    this.nameRanges = const [],
    this.parentRanges = const [],
  });

  factory FolderLabel.of(
    String path, {
    required String home,
    List<(int, int)> ranges = const [],
  }) {
    final slash = path.lastIndexOf('/');
    if (slash < 0 || path == '/') {
      return FolderLabel(name: path, parent: '', nameRanges: ranges);
    }
    final name = path.substring(slash + 1);
    final rawParent = slash == 0 ? '/' : path.substring(0, slash);
    final tilde =
        home.length > 1 &&
        (rawParent == home || rawParent.startsWith('$home/'));
    final parent = tilde ? '~${rawParent.substring(home.length)}' : rawParent;
    // An index of the raw parent in the parent shown: the home's part of
    // it all lands on the `~`.
    int shown(int at, {required bool end}) {
      if (!tilde) return at;
      if (at < home.length) return end ? 1 : 0;
      return at - home.length + 1;
    }

    final nameRanges = <(int, int)>[];
    final parentRanges = <(int, int)>[];
    for (final (start, end) in ranges) {
      if (end > slash + 1) {
        nameRanges.add((
          (start - slash - 1).clamp(0, name.length),
          (end - slash - 1).clamp(0, name.length),
        ));
      }
      final parentEnd = end.clamp(0, rawParent.length);
      if (start < parentEnd && slash > 0) {
        final from = shown(start, end: false);
        final to = shown(parentEnd, end: true);
        if (parentRanges.isNotEmpty && parentRanges.last.$2 >= from) {
          parentRanges.last = (parentRanges.last.$1, to);
        } else {
          parentRanges.add((from, to));
        }
      }
    }
    return FolderLabel(
      name: name,
      parent: parent,
      nameRanges: nameRanges,
      parentRanges: parentRanges,
    );
  }

  final String name;
  final String parent;
  final List<(int, int)> nameRanges;
  final List<(int, int)> parentRanges;

  @override
  List<Object?> get props => [name, parent, nameRanges, parentRanges];
}

/// The jump's list over [FolderJumpCubit].
class FolderJumpView extends StatelessWidget {
  const FolderJumpView({required this.home, this.initialQuery = '', super.key});

  final String home;
  final String initialQuery;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final platform = Theme.of(context).platform;
    String key(LogicalKeyboardKey key) => Chord.keyLabel(key, platform);
    return BlocBuilder<FolderJumpCubit, FolderJumpState>(
      builder: (context, state) => AppQuickPicker<String>(
        entries: [
          for (final match in state.matches)
            if (FolderLabel.of(
                  match.folder.path,
                  home: home,
                  ranges: match.ranges,
                )
                case final label)
              AppQuickPickerItem(
                value: match.folder.path,
                label: label.name,
                labelHighlights: label.nameRanges,
                detail: label.parent,
                detailHighlights: label.parentRanges,
                icon: AppIcons.folder,
              ),
        ],
        title: l10n.jumpTitle,
        hintText: l10n.jumpHint,
        emptyText: l10n.jumpEmpty,
        noResultsText: l10n.jumpNoResults,
        initialQuery: initialQuery,
        actions: AppQuickPickerAction.values.toSet(),
        hints: [
          (key(LogicalKeyboardKey.enter), l10n.jumpKeyOpen),
          (
            const Chord(
              LogicalKeyboardKey.enter,
              primary: true,
            ).label(platform),
            l10n.jumpKeyNewTab,
          ),
          (
            const Chord(LogicalKeyboardKey.enter, alt: true).label(platform),
            l10n.jumpKeyOtherPanel,
          ),
          (key(LogicalKeyboardKey.escape), l10n.paletteKeyClose),
        ],
        onQueryChanged: context.read<FolderJumpCubit>().setQuery,
        onPick: (pick) => Navigator.of(context).pop(pick),
      ),
    );
  }
}
