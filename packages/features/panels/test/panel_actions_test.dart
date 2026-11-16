import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:panels_feature/src/panel/flat_view.dart';
import 'package:panels_feature/src/panel/panel_state.dart';
import 'package:panels_feature/src/workspace/panel_actions.dart';
import 'package:panels_feature/src/workspace/context_menu.dart';
import 'package:shortcuts/shortcuts.dart';

const _parent = FileEntry(
  name: '..',
  path: '/',
  kind: EntryKind.directory,
  isDir: true,
  isParent: true,
);
const _folder = FileEntry(
  name: 'folder',
  path: '/home/folder',
  kind: EntryKind.directory,
  isDir: true,
);
const _first = FileEntry(
  name: 'first.txt',
  path: '/home/first.txt',
  kind: EntryKind.file,
  isDir: false,
  extension: 'txt',
);
const _second = FileEntry(
  name: 'second.txt',
  path: '/home/second.txt',
  kind: EntryKind.file,
  isDir: false,
  extension: 'txt',
);
const _other = FileEntry(
  name: 'other.md',
  path: '/home/other.md',
  kind: EntryKind.file,
  isDir: false,
  extension: 'md',
);

PanelTabState _tab({
  Location location = const Location.native('/home'),
  List<FileEntry> rows = const [_parent, _folder, _first, _second, _other],
  int cursor = 4,
  Set<String> selected = const {},
  String query = '',
  int? visual,
  FlatView? flat,
}) => PanelTabState(
  id: 'test',
  location: location,
  sort: const SortOptions(),
  rows: rows,
  cursor: cursor,
  selected: selected,
  quickSearch: query,
  visualAnchor: visual,
  flat: flat,
);

void main() {
  final map = ShortcutMap.forUser(TargetPlatform.macOS);
  List<PanelAction> actions(
    PanelTabState tab, {
    ShortcutMap? shortcuts,
    PanelTabState? opposite,
    bool vim = false,
    bool archives = false,
    bool tags = false,
    bool comparison = false,
    bool pending = false,
    bool shelf = false,
  }) => panelActionsFor(
    PanelActionContext(
      tab: tab,
      shortcuts: shortcuts ?? map,
      opposite: opposite,
      vim: vim,
      hasArchives: archives,
      finderTags: tags,
      comparisonAvailable: comparison,
      deletionPending: pending,
      hasShelf: shelf,
    ),
  );
  Set<AppCommand> commands(List<PanelAction> actions) => {
    for (final action in actions) action.command,
  };

  test('native multi-selection retains complete bulk continuations', () {
    final result = actions(
      _tab(selected: {_first.key, _second.key}),
      tags: true,
    );
    final bulk = commands(
      result.where((a) => a.target == PanelActionTarget.targets).toList(),
    );
    expect(
      bulk,
      containsAll([
        AppCommand.copyItemName,
        AppCommand.copyItemPath,
        AppCommand.copyPaths,
        AppCommand.copyTo,
        AppCommand.moveTo,
        AppCommand.duplicate,
        AppCommand.batchRename,
        AppCommand.renameInEditor,
        AppCommand.compress,
        AppCommand.compressTo,
        AppCommand.fileAttributes,
        AppCommand.checksums,
        AppCommand.addToShelf,
        AppCommand.newFolderWithSelection,
        AppCommand.editTags,
        AppCommand.moveToTrash,
        AppCommand.deletePermanently,
        AppCommand.deselectAll,
      ]),
    );
    for (final command in [
      AppCommand.renameInPlace,
      AppCommand.openItem,
      AppCommand.internalViewer,
    ]) {
      expect(
        result.singleWhere((a) => a.command == command).target,
        PanelActionTarget.focusedItem,
      );
    }
    expect(
      commands(result).length,
      result.length,
      reason: 'no duplicate commands',
    );
    expect(commands(result), isNot(contains(AppCommand.copyAs)));
    expect(commands(result), isNot(contains(AppCommand.copyItemDirectory)));
  });

  test(
    'search, Visual and key rebinding never shrink the action inventory',
    () {
      final plain = _tab(selected: {_first.key, _second.key});
      final baseline = commands(actions(plain));
      for (final current in [
        plain,
        _tab(selected: {_first.key, _second.key}, query: 'txt'),
        _tab(selected: {_first.key, _second.key}, visual: 2),
      ]) {
        for (final vim in [false, true]) {
          final unbound =
              ShortcutMap.forUser(TargetPlatform.macOS, vimMotions: vim)
                  .rebind(AppCommand.copyItemName, [])
                  .rebind(AppCommand.batchRename, [])
                  .rebind(AppCommand.fileAttributes, []);
          expect(
            commands(actions(current, vim: vim, shortcuts: unbound)),
            containsAll(baseline),
          );
        }
      }
    },
  );

  test(
    'remote operations exclude local-only tools and destructive Trash alias',
    () {
      final result = commands(
        actions(
          _tab(
            location: const Location.remote(
              server: 'sftp://host',
              path: '/home',
            ),
            selected: {_first.key, _second.key},
          ),
          archives: true,
          tags: true,
        ),
      );
      expect(
        result,
        containsAll([
          AppCommand.copyTo,
          AppCommand.moveTo,
          AppCommand.renameInPlace,
          AppCommand.deletePermanently,
          AppCommand.copyItemName,
          AppCommand.copyItemPath,
          AppCommand.internalViewer,
          AppCommand.newFolder,
        ]),
      );
      for (final command in [
        AppCommand.moveToTrash,
        AppCommand.compress,
        AppCommand.batchRename,
        AppCommand.renameInEditor,
        AppCommand.fileAttributes,
        AppCommand.checksums,
        AppCommand.addToShelf,
        AppCommand.editTags,
        AppCommand.quickLook,
        AppCommand.share,
        AppCommand.extractTo,
        AppCommand.openWith,
        AppCommand.duplicate,
      ]) {
        expect(result, isNot(contains(command)), reason: command.name);
      }
    },
  );

  test(
    'archive members have read/copy-text/extraction but no local mutations',
    () {
      final result = commands(
        actions(
          _tab(
            location: const Location.inArchive(archive: '/tmp/data.zip'),
            selected: {_first.key, _second.key},
          ),
          tags: true,
        ),
      );
      expect(
        result,
        containsAll([
          AppCommand.openItem,
          AppCommand.preview,
          AppCommand.internalViewer,
          AppCommand.extractTo,
          AppCommand.copyItemName,
          AppCommand.copyItemPath,
        ]),
      );
      for (final command in [
        AppCommand.copyTo,
        AppCommand.moveTo,
        AppCommand.renameInPlace,
        AppCommand.deletePermanently,
        AppCommand.moveToTrash,
        AppCommand.compress,
        AppCommand.addToShelf,
        AppCommand.checksums,
        AppCommand.editTags,
        AppCommand.pasteItems,
      ]) {
        expect(result, isNot(contains(command)), reason: command.name);
      }
      final foldersOnly = commands(
        actions(
          _tab(
            location: const Location.inArchive(archive: '/tmp/data.zip'),
            rows: const [_parent, _folder],
            cursor: 1,
            selected: {_folder.key},
          ),
        ),
      );
      expect(foldersOnly, isNot(contains(AppCommand.quickLook)));
      expect(foldersOnly, isNot(contains(AppCommand.share)));
    },
  );

  test('parent and empty panels never target a navigation row as a file', () {
    for (final current in [_tab(cursor: 0), _tab(rows: const [], cursor: -1)]) {
      final result = actions(current);
      expect(
        result.where((a) => a.target == PanelActionTarget.targets),
        isEmpty,
      );
      expect(
        commands(result),
        containsAll([
          AppCommand.newFolder,
          AppCommand.newFile,
          AppCommand.createDirectory,
          AppCommand.pasteItems,
        ]),
      );
      for (final command in [
        AppCommand.moveToTrash,
        AppCommand.batchRename,
        AppCommand.copyItemName,
        AppCommand.fileAttributes,
        AppCommand.share,
      ]) {
        expect(commands(result), isNot(contains(command)));
      }
    }
    final marked = commands(
      actions(_tab(cursor: 0, selected: {_first.key, _second.key})),
    );
    expect(marked, contains(AppCommand.copyItemName));
    expect(
      panelActionsFor(PanelActionContext(tab: null, shortcuts: map)),
      isEmpty,
    );
  });

  test('comparison requires the exact pair the handler can open', () {
    final pair = _tab(selected: {_first.key, _second.key});
    expect(
      commands(actions(pair, comparison: true)),
      contains(AppCommand.compareFiles),
    );
    for (final current in [
      _tab(selected: {_first.key, _second.key, _other.key}),
      _tab(selected: {_folder.key, _first.key}),
      _tab(
        rows: const [_first],
        cursor: 0,
        selected: {_first.key, _second.key},
      ),
    ]) {
      expect(
        commands(actions(current, comparison: true)),
        isNot(contains(AppCommand.compareFiles)),
      );
    }
    expect(commands(actions(pair)), isNot(contains(AppCommand.compareFiles)));
    expect(
      commands(actions(_tab(), opposite: _tab(cursor: 2), comparison: true)),
      contains(AppCommand.compareFiles),
    );
    expect(
      commands(actions(_tab(), opposite: pair, comparison: true)),
      isNot(contains(AppCommand.compareFiles)),
    );
  });

  test(
    'pending deletion, platform capability and archive detection are honored',
    () {
      final current = _tab(selected: {_first.key, _second.key});
      final limited = commands(
        actions(
          current,
          pending: true,
          tags: true,
          shortcuts: map.withUnavailable({
            AppCommand.quickLook,
            AppCommand.share,
            AppCommand.editTags,
          }),
        ),
      );
      for (final command in [
        AppCommand.moveToTrash,
        AppCommand.deletePermanently,
        AppCommand.quickLook,
        AppCommand.share,
        AppCommand.editTags,
        AppCommand.extractTo,
      ]) {
        expect(limited, isNot(contains(command)));
      }
      expect(
        commands(actions(current, archives: true)),
        contains(AppCommand.extractTo),
      );
      expect(
        commands(actions(current, shelf: true)),
        contains(AppCommand.toggleShelf),
      );
    },
  );

  test('name-editor and Quick Look scopes match their actual target rules', () {
    final wholeFolder = actions(_tab());
    expect(
      wholeFolder
          .singleWhere((a) => a.command == AppCommand.renameInEditor)
          .target,
      PanelActionTarget.directory,
    );
    final singleMark = actions(_tab(selected: {_first.key}));
    expect(
      singleMark.singleWhere((a) => a.command == AppCommand.quickLook).target,
      PanelActionTarget.focusedItem,
    );
    final multiple = actions(_tab(selected: {_first.key, _second.key}));
    expect(
      multiple.singleWhere((a) => a.command == AppCommand.quickLook).target,
      PanelActionTarget.targets,
    );
    expect(
      commands(actions(_tab(flat: const FlatView(generation: 1)))),
      isNot(contains(AppCommand.renameInEditor)),
    );
    expect(
      commands(actions(_tab(selected: {_first.key}))),
      containsAll([
        AppCommand.copyAs,
        AppCommand.moveAs,
        AppCommand.copyItemDirectory,
      ]),
    );
  });
  test('Vim shelf replacement, cut intent and paste retain native guards', () {
    final selected = _tab(selected: {_first.key, _second.key});
    final native = commands(actions(selected, vim: true, shelf: true));
    expect(
      native,
      containsAll([
        AppCommand.vimYank,
        AppCommand.vimCut,
        AppCommand.vimPaste,
        AppCommand.vimCancelRegister,
        AppCommand.addToShelf,
      ]),
    );
    expect(commands(actions(selected)), isNot(contains(AppCommand.vimYank)));
    expect(
      commands(actions(selected, vim: true)),
      isNot(contains(AppCommand.vimPaste)),
    );
    final archive = commands(
      actions(
        _tab(
          location: const Location.inArchive(archive: '/tmp/data.zip'),
          selected: {_first.key, _second.key},
        ),
        vim: true,
        shelf: true,
      ),
    );
    expect(archive, contains(AppCommand.vimCancelRegister));
    for (final command in [
      AppCommand.vimYank,
      AppCommand.vimCut,
      AppCommand.vimPaste,
    ]) {
      expect(archive, isNot(contains(command)));
    }
  });

  testWidgets(
    'curated row menu uses shared availability and retains unbound Actions',
    (
      tester,
    ) async {
      final unbound = map
          .rebind(AppCommand.copyItemName, [])
          .rebind(AppCommand.contextMenu, []);
      late List<AppMenuEntry<AppCommand>> row;
      late List<AppMenuEntry<AppCommand>> panel;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppPlatformStyle.macos),
          localizationsDelegates: FerryxSupportedLocales.delegates,
          supportedLocales: FerryxSupportedLocales.locales,
          home: Builder(
            builder: (context) {
              final tab = _tab(selected: {_first.key, _second.key});
              row = rowMenuEntries(
                context,
                entry: _other,
                location: tab.location,
                severalSelected: true,
                map: unbound,
                actionContext: PanelActionContext(
                  tab: tab,
                  shortcuts: unbound,
                  deletionPending: true,
                ),
              );
              panel = panelMenuEntries(
                context,
                showHidden: false,
                singlePane: false,
                stacked: false,
                native: true,
                map: unbound,
              );
              return const SizedBox();
            },
          ),
        ),
      );
      final entries = row.whereType<AppMenuAction<AppCommand>>().toList();
      expect(
        entries.map((entry) => entry.value),
        isNot(
          anyOf(
            contains(AppCommand.moveToTrash),
            contains(AppCommand.deletePermanently),
          ),
        ),
      );
      expect(
        entries
            .singleWhere((entry) => entry.value == AppCommand.copyItemName)
            .shortcut,
        isNull,
      );
      expect(entries.last.value, AppCommand.contextMenu);
      expect(
        entries.last.shortcut,
        isNull,
        reason: 'the row-menu key does not directly open the expanded picker',
      );
      expect(
        panel.whereType<AppMenuAction<AppCommand>>().last.value,
        AppCommand.contextMenu,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
