import 'package:domain_models/domain_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panels_feature/panels_feature.dart';
import 'package:shortcuts/shortcuts.dart';

void main() {
  const home = Location.native('/home');
  const parent = FileEntry(
    name: '..',
    path: '/',
    kind: EntryKind.directory,
    isDir: true,
    isParent: true,
  );
  const folder = FileEntry(
    name: 'docs',
    path: '/home/docs',
    kind: EntryKind.directory,
    isDir: true,
  );
  const file = FileEntry(
    name: 'a.txt',
    path: '/home/a.txt',
    kind: EntryKind.file,
    isDir: false,
    size: 1,
    extension: 'txt',
  );
  PanelTabState tab({
    List<FileEntry> rows = const [parent, folder, file],
    int cursor = 0,
    Set<String> selected = const {},
    String quickSearch = '',
    Map<String, List<(int, int)>> matches = const {},
    bool searching = false,
    int? visualAnchor,
    int? renaming,
  }) => PanelTabState(
    id: 't',
    location: home,
    sort: const SortOptions(),
    rows: rows,
    cursor: cursor,
    selected: selected,
    quickSearch: quickSearch,
    matches: matches,
    searching: searching,
    visualAnchor: visualAnchor,
    renaming: renaming,
  );

  List<AppCommand> commands(List<PanelHint> hints) => [
    for (final hint in hints)
      if (hint is CommandHint) hint.command,
  ];

  test('with nothing in the panel: how to get to the other one', () {
    expect(commands(hintsFor(tab: null, vim: false, hasRegister: false)), [
      AppCommand.switchPanel,
    ]);
  });

  test('a file, a folder and .. each get their own keys', () {
    expect(
      commands(hintsFor(tab: tab(cursor: 2), vim: false, hasRegister: false)),
      [
        AppCommand.enterItem,
        AppCommand.showPreview,
        AppCommand.toggleSelectionMoveDown,
        AppCommand.copyTo,
        AppCommand.switchPanel,
      ],
    );
    expect(
      commands(hintsFor(tab: tab(cursor: 1), vim: false, hasRegister: false)),
      contains(AppCommand.enterItem),
    );
    expect(
      commands(hintsFor(tab: tab(cursor: 0), vim: false, hasRegister: false)),
      isNot(contains(AppCommand.showPreview)),
    );
  });

  test('a selection is what to do with it; Vim adds the register', () {
    final hints = hintsFor(
      tab: tab(selected: {'a.txt'}),
      vim: false,
      hasRegister: false,
    );
    expect(commands(hints), [
      AppCommand.copyTo,
      AppCommand.moveTo,
      AppCommand.moveToTrash,
      AppCommand.compress,
      AppCommand.deselectAll,
    ]);
    expect(
      commands(hintsFor(tab: tab(cursor: 2), vim: true, hasRegister: true))
          .first,
      AppCommand.vimPaste,
    );
  });

  test('modes: renaming, the search prompt, matches, Visual', () {
    final renaming = hintsFor(
      tab: tab(renaming: 2),
      vim: false,
      hasRegister: false,
    );
    expect(renaming, hasLength(2));
    expect((renaming.first as KeyHint).key, LogicalKeyboardKey.enter);
    final prompt = hintsFor(
      tab: tab(searching: true),
      vim: true,
      hasRegister: false,
    );
    expect((prompt.first as KeyHint).word, HintWord.keepMatches);
    final matches = hintsFor(
      tab: tab(
        quickSearch: 'a',
        matches: {
          'a.txt': [(0, 1)],
        },
      ),
      vim: true,
      hasRegister: false,
    );
    expect(commands(matches), [
      AppCommand.vimSearchNext,
      AppCommand.vimSearchPrevious,
      AppCommand.clearQuickSearch,
    ]);
    final visual = hintsFor(
      tab: tab(cursor: 1, visualAnchor: 1, selected: {'docs'}),
      vim: true,
      hasRegister: false,
    );
    expect(commands(visual), [
      AppCommand.vimYank,
      AppCommand.vimCut,
      AppCommand.moveToTrash,
    ]);
    expect((visual.last as KeyHint).word, HintWord.back);
  });

  test('an empty folder says how to fill it', () {
    expect(
      commands(
        hintsFor(
          tab: tab(rows: const [], cursor: -1),
          vim: false,
          hasRegister: false,
        ),
      ),
      [
        AppCommand.pasteItems,
        AppCommand.newFolder,
        AppCommand.goParent,
        AppCommand.switchPanel,
      ],
    );
  });
}
