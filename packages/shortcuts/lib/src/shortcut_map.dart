import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app_command.dart';
import 'chord.dart';
import 'chord_codec.dart';
import 'command_action.dart';
import 'key_sequence.dart';

/// Bindings from commands to chords; immutable, with the defaults built in.
@immutable
class ShortcutMap {
  const ShortcutMap._(this._bindings) : unavailable = const {};

  /// The built-in table for [platform]. Chords are written once for every
  /// desktop ([Chord.primary] is ⌘ or Ctrl); where Windows and Linux use
  /// another key, not just another modifier, `_otherDesktops` replaces the
  /// Mac chord. The panel's single keys are here too, so the cheat sheet
  /// can list them; the panel decides when they apply.
  factory ShortcutMap.defaults(TargetPlatform platform) =>
      platform == TargetPlatform.macOS ? _macDefaults : _otherDefaults;

  /// What the keys do for one user: the [platform]'s defaults, Vim keys
  /// when [vimMotions] is on, then [overrides] as the preferences store
  /// them (see [ChordCodec.apply]).
  ///
  /// The [unavailable] commands (a capability this desktop lacks: Quick
  /// Look, the share picker) lose every chord, whatever the overrides
  /// say, and [isAvailable] answers false for them, so the menus, the
  /// palette, the cheat sheet and the hotkeys leave them out.
  factory ShortcutMap.forUser(
    TargetPlatform platform, {
    bool vimMotions = false,
    Map<String, List<String>> overrides = const {},
    Set<AppCommand> unavailable = const {},
  }) {
    final defaults = ShortcutMap.defaults(platform);
    final map = ChordCodec.apply(
      vimMotions ? defaults.withVimMotions(platform) : defaults,
      overrides,
    );
    return unavailable.isEmpty ? map : map.withUnavailable(unavailable);
  }

  const ShortcutMap._withUnavailable(this._bindings, this.unavailable);

  static const _macDefaults = ShortcutMap._(_defaults);
  static final _otherDefaults = ShortcutMap._(
    Map.unmodifiable({..._defaults, ..._otherDesktops}),
  );

  final Map<AppCommand, List<Chord>> _bindings;

  /// Commands this desktop cannot run: unbound, and shown nowhere.
  final Set<AppCommand> unavailable;

  /// Whether [command] can run here; a menu, the palette or a list of keys
  /// shows it only then.
  bool isAvailable(AppCommand command) => !unavailable.contains(command);

  /// A copy where [commands] are unavailable: no chords, [isAvailable]
  /// false.
  ShortcutMap withUnavailable(Set<AppCommand> commands) =>
      ShortcutMap._withUnavailable(
        Map<AppCommand, List<Chord>>.unmodifiable({
          ..._bindings,
          for (final command in commands) command: const <Chord>[],
        }),
        Set.unmodifiable({...unavailable, ...commands}),
      );

  List<Chord> chordsFor(AppCommand command) => _bindings[command] ?? const [];

  Chord? primaryChord(AppCommand command) {
    final chords = chordsFor(command);
    return chords.isEmpty ? null : chords.first;
  }

  /// The chord a Vim user knows [command] by: its letter, with ⇧ or after
  /// a prefix at most (`j`, `G`, `gg`), else a letter with ⌃ (`⌃d`), else
  /// another key Vim names as typed (`/`, `*`); its first chord when it
  /// has none of these.
  Chord? letterChord(AppCommand command) {
    final chords = chordsFor(command);
    bool letter(Chord chord) => Chord.isLetter(chord.key);
    bool typed(Chord chord) =>
        chord.isVimKey &&
        chord.key != LogicalKeyboardKey.space &&
        chord.key.keyLabel.runes.length == 1;
    return chords.where((c) => c.isVimKey && letter(c)).firstOrNull ??
        chords
            .where((c) => c.control && !c.primary && !c.alt && letter(c))
            .firstOrNull ??
        chords.where(typed).firstOrNull ??
        primaryChord(command);
  }

  /// [command]'s key as a label: with [vim] the one a Vim user knows it
  /// by, as Vim writes it ([letterChord], [Chord.vimLabel]); else its
  /// first chord. `null` when the command has none.
  String? labelOf(
    AppCommand command,
    TargetPlatform platform, {
    bool vim = false,
  }) => vim
      ? letterChord(command)?.vimLabel(platform)
      : primaryChord(command)?.label(platform);

  /// Vim keys on top of the current bindings, as a file manager with Vim
  /// keys (ranger, vifm) has them: `j k` down and up; `h l` out of the
  /// folder and into the item in a table, a column left and right where
  /// the names stand in columns, as vifm's ls-like view has them (`gl`,
  /// `gf` and `-` go in and out in either); `gg`/`G` and counts, `w`/`b`
  /// by a column too, `H M L` and
  /// `zz zt zb` on the screen, `⌃d ⌃u ⌃f ⌃b` by half a page and a page
  /// (on desktops whose command key is not Control), `⌃o ⌃i` back and
  /// forward; `v` selects as the cursor moves, `Space` and `x` toggle a
  /// row, `*` `#` the rows of the focused extension, `uv` none, `gv` the
  /// last selection; `yy` and `dd` take the rows to copy or move, `p`
  /// puts them here, `uy` lets go; `yn yp yd` copy a name, a path, a
  /// folder; `D` to the trash, `dD` for good, `dc` the folder sizes;
  /// `cw` renames, `A` and `I` at the name's end and start; `/` searches
  /// and `n`/`N` walk the matches, `f`/`F` jump to a name's first letter
  /// and `;`/`,` again; `m` sets a mark and `'` goes to one; `gt gT gn gc`
  /// are the tabs; `o…` sorts (`on os om oe oc oa ox`, `or` reverses);
  /// `zh` hidden items, `R` reloads, `i` previews, `gx` opens with the
  /// desktop, `gf` enters, `gh` `gr` home and root, `cd` asks for a
  /// folder, `:` is the command line, `?` the keys; `gj` jumps to a
  /// frecent folder, `ys` adds to the shelf and `gs` shows it, `cn` edits
  /// the names as text. `/`, Space and `~` move from their plain meanings
  /// to make room.
  ShortcutMap withVimMotions(TargetPlatform platform) {
    var map = this;
    void add(AppCommand command, Chord chord) =>
        map = map.rebind(command, [...map.chordsFor(command), chord]);
    Chord key(
      LogicalKeyboardKey k, {
      bool shift = false,
      bool control = false,
    }) => Chord(k, shift: shift, control: control);
    Chord seq(
      LogicalKeyboardKey prefix,
      LogicalKeyboardKey k, {
      bool shift = false,
    }) => Chord(k, prefix: prefix, shift: shift);
    const g = LogicalKeyboardKey.keyG;
    const d = LogicalKeyboardKey.keyD;
    const y = LogicalKeyboardKey.keyY;
    const u = LogicalKeyboardKey.keyU;
    const o = LogicalKeyboardKey.keyO;
    const z = LogicalKeyboardKey.keyZ;
    const c = LogicalKeyboardKey.keyC;

    // Motions.
    add(AppCommand.moveDown, key(LogicalKeyboardKey.keyJ));
    add(AppCommand.moveUp, key(LogicalKeyboardKey.keyK));
    add(AppCommand.vimLeft, key(LogicalKeyboardKey.keyH));
    add(AppCommand.vimRight, key(LogicalKeyboardKey.keyL));
    add(AppCommand.enterItem, seq(g, LogicalKeyboardKey.keyL));
    add(AppCommand.enterItem, seq(g, LogicalKeyboardKey.keyF));
    add(AppCommand.goParent, key(LogicalKeyboardKey.minus));
    add(AppCommand.moveFirst, seq(g, g));
    add(AppCommand.moveLast, key(g, shift: true));
    add(AppCommand.vimScreenTop, key(LogicalKeyboardKey.keyH, shift: true));
    add(AppCommand.vimScreenMiddle, key(LogicalKeyboardKey.keyM, shift: true));
    add(AppCommand.vimScreenBottom, key(LogicalKeyboardKey.keyL, shift: true));
    add(AppCommand.vimScrollCenter, seq(z, z));
    add(AppCommand.vimScrollTop, seq(z, LogicalKeyboardKey.keyT));
    add(AppCommand.vimScrollBottom, seq(z, LogicalKeyboardKey.keyB));
    add(AppCommand.vimColumnNext, key(LogicalKeyboardKey.keyW));
    add(AppCommand.vimColumnPrevious, key(LogicalKeyboardKey.keyB));
    add(AppCommand.vimFindChar, key(LogicalKeyboardKey.keyF));
    add(AppCommand.vimFindCharBack, key(LogicalKeyboardKey.keyF, shift: true));
    add(AppCommand.vimRepeatFind, key(LogicalKeyboardKey.semicolon));
    add(AppCommand.vimRepeatFindBack, key(LogicalKeyboardKey.comma));
    add(AppCommand.vimSetMark, key(LogicalKeyboardKey.keyM));
    add(AppCommand.vimGoMark, key(LogicalKeyboardKey.quoteSingle));
    add(AppCommand.vimGoMark, key(LogicalKeyboardKey.backquote));
    if (platform == TargetPlatform.macOS) {
      // Elsewhere Ctrl is the command key: Ctrl+D duplicates, Ctrl+F
      // finds, Ctrl+B is a favorite, Ctrl+U swaps the panels.
      add(AppCommand.vimHalfPageDown, key(d, control: true));
      add(AppCommand.vimHalfPageUp, key(u, control: true));
      add(AppCommand.movePageDown, key(LogicalKeyboardKey.keyF, control: true));
      add(AppCommand.movePageUp, key(LogicalKeyboardKey.keyB, control: true));
      add(AppCommand.goBack, key(o, control: true));
      add(AppCommand.goForward, key(LogicalKeyboardKey.keyI, control: true));
    }
    // Selection.
    add(AppCommand.vimVisual, key(LogicalKeyboardKey.keyV));
    add(AppCommand.vimVisual, key(LogicalKeyboardKey.keyV, shift: true));
    map = map.rebind(AppCommand.showPreview, [key(LogicalKeyboardKey.keyI)]);
    add(AppCommand.toggleSelectionMoveDown, key(LogicalKeyboardKey.space));
    add(AppCommand.toggleSelection, key(LogicalKeyboardKey.keyX));
    add(
      AppCommand.selectWithExtension,
      key(LogicalKeyboardKey.digit8, shift: true),
    );
    add(
      AppCommand.deselectWithExtension,
      key(LogicalKeyboardKey.digit3, shift: true),
    );
    add(AppCommand.deselectAll, seq(u, LogicalKeyboardKey.keyV));
    add(AppCommand.vimReselect, seq(g, LogicalKeyboardKey.keyV));
    // Registers and files.
    add(AppCommand.vimYank, seq(y, y));
    add(AppCommand.vimCut, seq(d, d));
    add(AppCommand.vimPaste, key(LogicalKeyboardKey.keyP));
    add(AppCommand.vimCancelRegister, seq(u, y));
    add(AppCommand.copyItemName, seq(y, LogicalKeyboardKey.keyN));
    add(AppCommand.copyItemPath, seq(y, LogicalKeyboardKey.keyP));
    add(AppCommand.copyItemDirectory, seq(y, d));
    add(AppCommand.moveToTrash, key(d, shift: true));
    add(AppCommand.deletePermanently, seq(d, d, shift: true));
    add(AppCommand.calcFolderSizes, seq(d, c));
    add(AppCommand.renameInPlace, seq(c, LogicalKeyboardKey.keyW));
    add(AppCommand.vimRenameAppend, key(LogicalKeyboardKey.keyA, shift: true));
    add(AppCommand.vimRenamePrepend, key(LogicalKeyboardKey.keyI, shift: true));
    // Search and the command line.
    map = map.rebind(AppCommand.goRootKey, [seq(g, LogicalKeyboardKey.keyR)]);
    add(AppCommand.goHomeKey, seq(g, LogicalKeyboardKey.keyH));
    add(AppCommand.vimSearch, key(LogicalKeyboardKey.slash));
    add(AppCommand.vimSearchNext, key(LogicalKeyboardKey.keyN));
    add(
      AppCommand.vimSearchPrevious,
      key(LogicalKeyboardKey.keyN, shift: true),
    );
    add(
      AppCommand.vimCommandLine,
      key(LogicalKeyboardKey.semicolon, shift: true),
    );
    add(AppCommand.goToFolder, seq(c, d));
    // Tabs, sorting, the rest.
    add(AppCommand.nextTab, seq(g, LogicalKeyboardKey.keyT));
    add(AppCommand.previousTab, seq(g, LogicalKeyboardKey.keyT, shift: true));
    add(AppCommand.newTab, seq(g, LogicalKeyboardKey.keyN));
    add(AppCommand.closeTab, seq(g, c));
    add(AppCommand.sortByName, seq(o, LogicalKeyboardKey.keyN));
    add(AppCommand.sortByExtension, seq(o, LogicalKeyboardKey.keyE));
    add(AppCommand.sortBySize, seq(o, LogicalKeyboardKey.keyS));
    add(AppCommand.sortByModified, seq(o, LogicalKeyboardKey.keyM));
    add(AppCommand.sortByCreated, seq(o, c));
    add(AppCommand.sortByAdded, seq(o, LogicalKeyboardKey.keyA));
    add(AppCommand.sortByAccessed, seq(o, LogicalKeyboardKey.keyX));
    add(AppCommand.vimSortReverse, seq(o, LogicalKeyboardKey.keyR));
    add(AppCommand.toggleHiddenFiles, seq(z, LogicalKeyboardKey.keyH));
    add(AppCommand.refresh, key(LogicalKeyboardKey.keyR, shift: true));
    add(AppCommand.openItem, seq(g, LogicalKeyboardKey.keyX));
    add(AppCommand.cheatSheet, key(LogicalKeyboardKey.slash, shift: true));
    // ─── Interface ───
    add(AppCommand.jumpToFolder, seq(g, LogicalKeyboardKey.keyJ));
    add(AppCommand.addToShelf, seq(y, LogicalKeyboardKey.keyS));
    add(AppCommand.toggleShelf, seq(g, LogicalKeyboardKey.keyS));
    add(AppCommand.renameInEditor, seq(c, LogicalKeyboardKey.keyN));
    // ─── Operations ───
    // `u` is a prefix here (`uv`, `uy`), so undo takes `uu`.
    add(AppCommand.undo, seq(u, u));
    add(AppCommand.redo, key(u, shift: true));
    // ─── Files core ───
    add(AppCommand.toggleFlatView, seq(z, LogicalKeyboardKey.keyF));
    return map;
  }

  /// Returns a copy with [command] bound to [chords] (empty = unbound).
  ShortcutMap rebind(AppCommand command, List<Chord> chords) =>
      ShortcutMap._withUnavailable(
        Map<AppCommand, List<Chord>>.unmodifiable({
          ..._bindings,
          command: List<Chord>.unmodifiable(chords),
        }),
        unavailable,
      );

  /// The command a chord would trigger, if any (for conflict warnings).
  AppCommand? commandFor(Chord chord) {
    for (final entry in _bindings.entries) {
      if (entry.value.contains(chord)) return entry.key;
    }
    return null;
  }

  /// A `Shortcuts`-compatible map for [platform], limited to [scopes] so
  /// single keys never fire while typing. A plain Enter or Space yields to
  /// a focused button or row ([CommandIntent.yieldsToControls]).
  ///
  /// [sequencesOf] adds the two-key sequences of other scopes: an inner
  /// map (the panel's) must try `gn` before its own `n`, or the sequence
  /// of an outer map never completes.
  Map<ShortcutActivator, Intent> toShortcuts(
    TargetPlatform platform, {
    required Set<CommandScope> scopes,
    Set<CommandScope> sequencesOf = const {},
  }) {
    final out = <ShortcutActivator, Intent>{};
    final prefixes = <LogicalKeyboardKey>{};
    // Sequences go first: a key that completes one may be a chord of its
    // own too, and the sequence must be tried before it.
    for (final sequences in [true, false]) {
      for (final entry in _bindings.entries) {
        final scope = entry.key.scope;
        if (!scopes.contains(scope) &&
            !(sequences && sequencesOf.contains(scope))) {
          continue;
        }
        for (final chord in entry.value) {
          if ((chord.prefix != null) != sequences) continue;
          out[chord.toShortcutActivator(platform)] = CommandIntent(
            entry.key,
            yieldsToControls: CommandIntent.isActivation(
              chord.key,
              plain: !chord.hasModifier && chord.prefix == null,
            ),
          );
          if (chord.prefix != null) prefixes.add(chord.prefix!);
        }
      }
    }
    // Prefix activators go last: on the completing key the sequence must be
    // tried before the prefix would be re-armed.
    for (final prefix in prefixes) {
      out[PrefixActivator(prefix)] = KeyPrefixIntent(prefix);
    }
    return out;
  }

  Map<AppCommand, List<Chord>> get bindings => _bindings;

  /// The terminal's place in the window: the commands whose keys reach the
  /// window from inside the terminal whatever they would mean to a program.
  static const terminalPlacement = {
    AppCommand.toggleTerminal,
    AppCommand.showTerminal,
    AppCommand.hideTerminal,
    AppCommand.togglePanelsOverTerminal,
  };

  /// The keys the integrated terminal leaves to the window, for [platform]:
  /// its own ([CommandScope.terminal]) and its menu's
  /// ([AppCommand.contextMenu]), [terminalPlacement], and the window's
  /// chords no program in a terminal is given — those with ⌘ on macOS,
  /// those with Ctrl+Shift elsewhere (the keys GNOME Terminal and Windows
  /// Terminal keep for themselves). Every other key, a Ctrl+letter above
  /// all, is the shell's. The terminal's own keys come first, so they win
  /// over a window chord of the same keys.
  Map<ShortcutActivator, CommandIntent> terminalShortcuts(
    TargetPlatform platform,
  ) {
    final out = <ShortcutActivator, CommandIntent>{};
    void add(AppCommand command) {
      for (final chord in chordsFor(command)) {
        if (chord.prefix != null) continue;
        final activator = chord.toShortcutActivator(platform);
        out.putIfAbsent(activator, () => CommandIntent(command));
      }
    }

    AppCommand.inScope(CommandScope.terminal).forEach(add);
    add(AppCommand.contextMenu);
    terminalPlacement.forEach(add);
    for (final command in AppCommand.inScope(CommandScope.global)) {
      for (final chord in chordsFor(command)) {
        if (chord.prefix == null && chord.reachesWindowFromTerminal(platform)) {
          out.putIfAbsent(
            chord.toShortcutActivator(platform),
            () => CommandIntent(command),
          );
        }
      }
    }
    return out;
  }
}

const _defaults = <AppCommand, List<Chord>>{
  // File
  AppCommand.newFolder: [
    Chord(LogicalKeyboardKey.keyN, primary: true, shift: true),
  ],
  AppCommand.newFolderWithSelection: [
    Chord(LogicalKeyboardKey.keyN, primary: true, control: true),
  ],
  AppCommand.newFile: [
    Chord(LogicalKeyboardKey.keyN, primary: true, alt: true),
  ],
  AppCommand.newTab: [Chord(LogicalKeyboardKey.keyT, primary: true)],
  AppCommand.closeTab: [Chord(LogicalKeyboardKey.keyW, primary: true)],
  AppCommand.closeOtherTabs: [
    Chord(LogicalKeyboardKey.keyW, primary: true, alt: true),
  ],
  AppCommand.reopenClosedTab: [
    Chord(LogicalKeyboardKey.keyR, primary: true, shift: true),
  ],
  AppCommand.nextTab: [
    Chord(LogicalKeyboardKey.bracketRight, primary: true, shift: true),
    Chord(LogicalKeyboardKey.tab, control: true),
  ],
  AppCommand.previousTab: [
    Chord(LogicalKeyboardKey.bracketLeft, primary: true, shift: true),
    Chord(LogicalKeyboardKey.tab, control: true, shift: true),
  ],
  AppCommand.toggleTabBar: [
    Chord(LogicalKeyboardKey.keyT, primary: true, shift: true),
  ],
  AppCommand.openItem: [Chord(LogicalKeyboardKey.enter, shift: true)],
  AppCommand.revealInOppositePanel: [
    Chord(LogicalKeyboardKey.enter, alt: true),
  ],
  AppCommand.revealInOppositeTab: [
    Chord(LogicalKeyboardKey.enter, primary: true, alt: true),
  ],
  AppCommand.calcFolderSizes: [
    Chord(LogicalKeyboardKey.enter, shift: true, alt: true),
  ],
  AppCommand.calcAllFolderSizes: [
    Chord(LogicalKeyboardKey.enter, control: true, shift: true),
  ],
  AppCommand.duplicate: [Chord(LogicalKeyboardKey.keyD, primary: true)],
  AppCommand.addToFavorites: [Chord(LogicalKeyboardKey.keyB, primary: true)],
  AppCommand.manageFavorites: [
    Chord(LogicalKeyboardKey.keyB, primary: true, control: true),
  ],
  AppCommand.findFiles: [Chord(LogicalKeyboardKey.keyF, primary: true)],

  // Edit
  AppCommand.copyPaths: [Chord(LogicalKeyboardKey.keyC, primary: true)],
  AppCommand.pasteItems: [Chord(LogicalKeyboardKey.keyV, primary: true)],
  AppCommand.moveItemsHere: [
    Chord(LogicalKeyboardKey.keyV, primary: true, alt: true),
  ],
  AppCommand.selectAll: [Chord(LogicalKeyboardKey.keyA, primary: true)],
  AppCommand.deselectAll: [
    Chord(LogicalKeyboardKey.keyA, primary: true, alt: true),
  ],
  AppCommand.invertSelection: [
    Chord(LogicalKeyboardKey.keyA, primary: true, control: true),
  ],
  AppCommand.selectWithMask: [Chord(LogicalKeyboardKey.equal, primary: true)],
  AppCommand.deselectWithMask: [Chord(LogicalKeyboardKey.minus, primary: true)],
  AppCommand.selectWithExtension: [
    Chord(LogicalKeyboardKey.equal, primary: true, alt: true),
  ],
  AppCommand.deselectWithExtension: [
    Chord(LogicalKeyboardKey.minus, primary: true, alt: true),
  ],

  // View
  AppCommand.toggleSinglePane: [
    Chord(LogicalKeyboardKey.keyP, primary: true, shift: true),
  ],
  AppCommand.swapPanels: [Chord(LogicalKeyboardKey.keyU, primary: true)],
  AppCommand.syncPanels: [
    Chord(LogicalKeyboardKey.keyU, primary: true, alt: true),
  ],
  AppCommand.viewMode1: [Chord(LogicalKeyboardKey.digit1, control: true)],
  AppCommand.viewMode2: [Chord(LogicalKeyboardKey.digit2, control: true)],
  AppCommand.viewMode3: [Chord(LogicalKeyboardKey.digit3, control: true)],
  AppCommand.viewMode4: [Chord(LogicalKeyboardKey.digit4, control: true)],
  AppCommand.viewMode5: [Chord(LogicalKeyboardKey.digit5, control: true)],
  AppCommand.sortByName: [
    Chord(LogicalKeyboardKey.digit1, primary: true, control: true),
  ],
  AppCommand.sortByExtension: [
    Chord(LogicalKeyboardKey.digit2, primary: true, control: true),
  ],
  AppCommand.sortByModified: [
    Chord(LogicalKeyboardKey.digit3, primary: true, control: true),
  ],
  AppCommand.sortBySize: [
    Chord(LogicalKeyboardKey.digit4, primary: true, control: true),
  ],
  AppCommand.sortByCreated: [
    Chord(LogicalKeyboardKey.digit5, primary: true, control: true),
  ],
  AppCommand.sortByAdded: [
    Chord(LogicalKeyboardKey.digit6, primary: true, control: true),
  ],
  AppCommand.sortByAccessed: [
    Chord(LogicalKeyboardKey.digit7, primary: true, control: true),
  ],
  AppCommand.toggleFoldersFirst: [],
  AppCommand.toggleExtensionlessFolders: [],
  AppCommand.collationNatural: [],
  AppCommand.collationCaseInsensitive: [],
  AppCommand.collationCaseSensitive: [],
  AppCommand.toggleHiddenFiles: [
    Chord(LogicalKeyboardKey.period, primary: true, shift: true),
  ],
  AppCommand.panelsMoveLeft: [
    Chord(LogicalKeyboardKey.arrowLeft, control: true, alt: true),
  ],
  AppCommand.panelsMoveRight: [
    Chord(LogicalKeyboardKey.arrowRight, control: true, alt: true),
  ],
  AppCommand.resizePanels: [
    Chord(LogicalKeyboardKey.backslash, primary: true, alt: true),
  ],
  AppCommand.refresh: [Chord(LogicalKeyboardKey.keyR, primary: true)],
  AppCommand.toggleOperations: [
    Chord(LogicalKeyboardKey.keyO, primary: true, control: true),
  ],

  // Go
  AppCommand.goToLeftPanel: [Chord(LogicalKeyboardKey.f1)],
  AppCommand.goToRightPanel: [Chord(LogicalKeyboardKey.f2)],
  AppCommand.goBack: [Chord(LogicalKeyboardKey.bracketLeft, primary: true)],
  AppCommand.goForward: [Chord(LogicalKeyboardKey.bracketRight, primary: true)],
  AppCommand.goEnclosingFolder: [
    Chord(LogicalKeyboardKey.arrowUp, primary: true),
  ],
  AppCommand.goInto: [Chord(LogicalKeyboardKey.arrowDown, primary: true)],
  AppCommand.followSymlink: [
    Chord(LogicalKeyboardKey.arrowRight, primary: true),
  ],
  AppCommand.goDocuments: [
    Chord(LogicalKeyboardKey.keyO, primary: true, shift: true),
  ],
  AppCommand.goDesktop: [
    Chord(LogicalKeyboardKey.keyD, primary: true, shift: true),
  ],
  AppCommand.goDownloads: [
    Chord(LogicalKeyboardKey.keyL, primary: true, alt: true),
  ],
  AppCommand.goHome: [
    Chord(LogicalKeyboardKey.keyH, primary: true, shift: true),
  ],
  AppCommand.goLibrary: [],
  AppCommand.goApplications: [
    Chord(LogicalKeyboardKey.keyA, primary: true, shift: true),
  ],
  AppCommand.goUtilities: [
    Chord(LogicalKeyboardKey.keyU, primary: true, shift: true),
  ],
  AppCommand.goRoot: [],
  AppCommand.quickListParents: [
    Chord(LogicalKeyboardKey.digit1, primary: true),
  ],
  AppCommand.quickListHistory: [
    Chord(LogicalKeyboardKey.digit2, primary: true),
  ],
  AppCommand.quickListFavorites: [
    Chord(LogicalKeyboardKey.digit3, primary: true),
  ],
  AppCommand.quickListVolumes: [
    Chord(LogicalKeyboardKey.digit4, primary: true),
  ],
  AppCommand.goToFolder: [
    Chord(LogicalKeyboardKey.keyG, primary: true, shift: true),
  ],

  // Command
  AppCommand.fileAttributes: [Chord(LogicalKeyboardKey.keyA, control: true)],
  AppCommand.copyItemName: [
    Chord(LogicalKeyboardKey.keyC, primary: true, shift: true),
  ],
  AppCommand.copyItemPath: [
    Chord(LogicalKeyboardKey.keyC, primary: true, alt: true),
  ],
  AppCommand.copyItemDirectory: [
    Chord(LogicalKeyboardKey.keyC, primary: true, alt: true, shift: true),
  ],
  // ⌘Y is Quick Look's, as in Finder (`quickLook`).
  AppCommand.preview: [
    Chord(LogicalKeyboardKey.keyY, primary: true, shift: true),
  ],
  AppCommand.internalViewer: [Chord(LogicalKeyboardKey.f3)],
  AppCommand.externalEditor: [Chord(LogicalKeyboardKey.f4)],
  AppCommand.ejectVolume: [Chord(LogicalKeyboardKey.keyE, primary: true)],
  AppCommand.batchRename: [Chord(LogicalKeyboardKey.keyM, control: true)],
  AppCommand.copyTo: [Chord(LogicalKeyboardKey.f5)],
  AppCommand.copyAs: [Chord(LogicalKeyboardKey.f5, shift: true)],
  AppCommand.moveTo: [Chord(LogicalKeyboardKey.f6)],
  AppCommand.moveAs: [Chord(LogicalKeyboardKey.f6, shift: true)],
  AppCommand.renameInPlace: [Chord(LogicalKeyboardKey.f6, control: true)],
  AppCommand.createDirectory: [Chord(LogicalKeyboardKey.f7)],
  AppCommand.createDirectoryInOppositePanel: [
    Chord(LogicalKeyboardKey.f7, shift: true),
  ],
  // ⌘⌫ as in Finder; Del on the other desktops (`_otherDesktops`).
  AppCommand.moveToTrash: [
    Chord(LogicalKeyboardKey.backspace, primary: true),
  ],
  AppCommand.deleteItems: [Chord(LogicalKeyboardKey.f8)],
  AppCommand.deletePermanently: [Chord(LogicalKeyboardKey.f8, shift: true)],
  AppCommand.compress: [Chord(LogicalKeyboardKey.f9)],
  AppCommand.compressTo: [Chord(LogicalKeyboardKey.f9, shift: true)],
  AppCommand.createSymlink: [],
  AppCommand.createHardlink: [],
  AppCommand.editSymlink: [],
  AppCommand.revealInFileManager: [],
  AppCommand.openWith: [],
  // Native
  AppCommand.quickLook: [Chord(LogicalKeyboardKey.keyY, primary: true)],
  AppCommand.share: [
    Chord(LogicalKeyboardKey.keyS, primary: true, shift: true),
  ],

  // ─── Operations ───
  // Total Commander's Compare and Synchronize Directories.
  AppCommand.compareFolders: [Chord(LogicalKeyboardKey.f2, shift: true)],
  AppCommand.synchronizeFolders: [
    Chord(LogicalKeyboardKey.f2, shift: true, alt: true),
  ],
  AppCommand.undo: [Chord(LogicalKeyboardKey.keyZ, primary: true)],
  AppCommand.redo: [Chord(LogicalKeyboardKey.keyZ, primary: true, shift: true)],
  AppCommand.checksums: [
    Chord(LogicalKeyboardKey.keyH, primary: true, control: true),
  ],
  AppCommand.findDuplicates: [
    Chord(LogicalKeyboardKey.keyF, primary: true, shift: true),
  ],

  // Window and help
  AppCommand.focusLeftPanel: [
    Chord(LogicalKeyboardKey.arrowLeft, primary: true, shift: true),
  ],
  AppCommand.focusRightPanel: [
    Chord(LogicalKeyboardKey.arrowRight, primary: true, shift: true),
  ],
  AppCommand.openSettings: [Chord(LogicalKeyboardKey.comma, primary: true)],
  AppCommand.hintMode: [Chord(LogicalKeyboardKey.keyJ, primary: true)],
  AppCommand.cheatSheet: [Chord(LogicalKeyboardKey.slash, primary: true)],
  // What a right click opens, for the focused row: Shift+F10 and the
  // Menu key as on Windows and GNOME, ⌃↩ as macOS names it.
  AppCommand.contextMenu: [
    Chord(LogicalKeyboardKey.enter, control: true),
    Chord(LogicalKeyboardKey.f10, shift: true),
    Chord(LogicalKeyboardKey.contextMenu),
  ],

  // ─── Interface ───
  AppCommand.commandPalette: [Chord(LogicalKeyboardKey.keyP, primary: true)],
  AppCommand.jumpToFolder: [Chord(LogicalKeyboardKey.keyG, primary: true)],
  AppCommand.addToShelf: [
    Chord(LogicalKeyboardKey.keyS, primary: true, alt: true),
  ],
  AppCommand.toggleShelf: [
    Chord(LogicalKeyboardKey.keyS, primary: true, control: true),
  ],
  AppCommand.renameInEditor: [
    Chord(LogicalKeyboardKey.keyM, control: true, shift: true),
  ],
  // ─── Terminal ───
  // Nimble Commander's keys: ⌥⌘O the whole window, ⌃⌥↑ ⌃⌥↓ the terminal
  // under the panels, ⌃⌥O the panels over it. Window managers (Rectangle,
  // Magnet) take ⌃⌥↑ and ⌃⌥↓ for halves of the screen, so ⌃` and ⌃⇧`
  // come first, as editors' terminal keys; NC's stay for who has them.
  AppCommand.toggleTerminal: [
    Chord(LogicalKeyboardKey.keyO, primary: true, alt: true),
  ],
  AppCommand.showTerminal: [
    Chord(LogicalKeyboardKey.backquote, control: true),
    Chord(LogicalKeyboardKey.arrowUp, control: true, alt: true),
  ],
  AppCommand.hideTerminal: [
    Chord(LogicalKeyboardKey.backquote, control: true, shift: true),
    Chord(LogicalKeyboardKey.arrowDown, control: true, alt: true),
  ],
  AppCommand.togglePanelsOverTerminal: [
    Chord(LogicalKeyboardKey.keyO, control: true, alt: true),
  ],
  // ─── Files core ───
  AppCommand.extractTo: [Chord(LogicalKeyboardKey.f9, alt: true)],
  AppCommand.toggleFlatView: [
    Chord(LogicalKeyboardKey.keyB, primary: true, alt: true),
  ],
  AppCommand.editTags: [
    Chord(LogicalKeyboardKey.keyT, primary: true, control: true),
  ],
  // ─── Network ───
  // Finder's Connect to Server. Inside the terminal ⌘K clears it, as in
  // Terminal.app: the terminal's own keys are matched first.
  AppCommand.connectToServer: [Chord(LogicalKeyboardKey.keyK, primary: true)],
  AppCommand.disconnectServer: [],

  // File panel keys
  AppCommand.moveUp: [Chord(LogicalKeyboardKey.arrowUp)],
  AppCommand.moveDown: [Chord(LogicalKeyboardKey.arrowDown)],
  AppCommand.moveLeft: [Chord(LogicalKeyboardKey.arrowLeft)],
  AppCommand.moveRight: [Chord(LogicalKeyboardKey.arrowRight)],
  AppCommand.moveFirst: [Chord(LogicalKeyboardKey.home)],
  AppCommand.moveLast: [Chord(LogicalKeyboardKey.end)],
  AppCommand.scrollFirst: [Chord(LogicalKeyboardKey.home, alt: true)],
  AppCommand.scrollLast: [Chord(LogicalKeyboardKey.end, alt: true)],
  AppCommand.movePageUp: [Chord(LogicalKeyboardKey.pageUp)],
  AppCommand.movePageDown: [Chord(LogicalKeyboardKey.pageDown)],
  AppCommand.scrollPageUp: [Chord(LogicalKeyboardKey.pageUp, alt: true)],
  AppCommand.scrollPageDown: [Chord(LogicalKeyboardKey.pageDown, alt: true)],
  AppCommand.selectMoveUp: [Chord(LogicalKeyboardKey.arrowUp, shift: true)],
  AppCommand.selectMoveDown: [
    Chord(LogicalKeyboardKey.arrowDown, shift: true),
  ],
  AppCommand.selectMoveLeft: [
    Chord(LogicalKeyboardKey.arrowLeft, shift: true),
  ],
  AppCommand.selectMoveRight: [
    Chord(LogicalKeyboardKey.arrowRight, shift: true),
  ],
  AppCommand.selectMoveFirst: [Chord(LogicalKeyboardKey.home, shift: true)],
  AppCommand.selectMoveLast: [Chord(LogicalKeyboardKey.end, shift: true)],
  AppCommand.selectMovePageUp: [
    Chord(LogicalKeyboardKey.pageUp, shift: true),
  ],
  AppCommand.selectMovePageDown: [
    Chord(LogicalKeyboardKey.pageDown, shift: true),
  ],
  // ⌥Space and Insert: the orthodox managers' Insert, which Mac
  // keyboards lack.
  AppCommand.toggleSelection: [Chord(LogicalKeyboardKey.space, control: true)],
  AppCommand.toggleSelectionMoveDown: [
    Chord(LogicalKeyboardKey.insert),
    Chord(LogicalKeyboardKey.space, alt: true),
  ],
  AppCommand.enterItem: [Chord(LogicalKeyboardKey.enter)],
  AppCommand.goParent: [Chord(LogicalKeyboardKey.backspace)],
  AppCommand.goHomeKey: [Chord(LogicalKeyboardKey.backquote, shift: true)],
  AppCommand.goRootKey: [Chord(LogicalKeyboardKey.slash)],
  AppCommand.switchPanel: [Chord(LogicalKeyboardKey.tab)],
  AppCommand.showPreview: [Chord(LogicalKeyboardKey.space)],
  AppCommand.clearQuickSearch: [Chord(LogicalKeyboardKey.escape)],
  AppCommand.showTab1: [],
  AppCommand.showTab2: [],
  AppCommand.showTab3: [],
  AppCommand.showTab4: [],
  AppCommand.showTab5: [],
  AppCommand.showTab6: [],
  AppCommand.showTab7: [],
  AppCommand.showTab8: [],
  AppCommand.showTab9: [],
  AppCommand.showTab10: [],

  // Vim keys: bound by `withVimMotions` only.
  AppCommand.vimVisual: [],
  AppCommand.vimSearch: [],
  AppCommand.vimSearchNext: [],
  AppCommand.vimSearchPrevious: [],
  AppCommand.vimCommandLine: [],
  AppCommand.vimCut: [],
  AppCommand.vimYank: [],
  AppCommand.vimPaste: [],
  AppCommand.vimCancelRegister: [],
  AppCommand.vimFindChar: [],
  AppCommand.vimFindCharBack: [],
  AppCommand.vimRepeatFind: [],
  AppCommand.vimRepeatFindBack: [],
  AppCommand.vimSetMark: [],
  AppCommand.vimGoMark: [],
  AppCommand.vimScreenTop: [],
  AppCommand.vimScreenMiddle: [],
  AppCommand.vimScreenBottom: [],
  AppCommand.vimScrollCenter: [],
  AppCommand.vimScrollTop: [],
  AppCommand.vimScrollBottom: [],
  AppCommand.vimHalfPageDown: [],
  AppCommand.vimHalfPageUp: [],
  AppCommand.vimColumnNext: [],
  AppCommand.vimColumnPrevious: [],
  AppCommand.vimLeft: [],
  AppCommand.vimRight: [],
  AppCommand.vimRenameAppend: [],
  AppCommand.vimRenamePrepend: [],
  AppCommand.vimSortReverse: [],
  AppCommand.vimReselect: [],

  // Viewer
  AppCommand.viewerText: [Chord(LogicalKeyboardKey.digit1, primary: true)],
  AppCommand.viewerHex: [Chord(LogicalKeyboardKey.digit2, primary: true)],
  AppCommand.viewerPreview: [Chord(LogicalKeyboardKey.digit3, primary: true)],
  AppCommand.viewerGoTo: [Chord(LogicalKeyboardKey.keyL, primary: true)],
  AppCommand.viewerRefresh: [Chord(LogicalKeyboardKey.keyR, primary: true)],
  AppCommand.viewerFind: [Chord(LogicalKeyboardKey.keyF, primary: true)],
  AppCommand.viewerFindNext: [Chord(LogicalKeyboardKey.keyG, primary: true)],
  AppCommand.viewerFindPrevious: [
    Chord(LogicalKeyboardKey.keyG, primary: true, shift: true),
  ],
  AppCommand.viewerToggleWrap: [
    Chord(LogicalKeyboardKey.keyW, primary: true, alt: true),
  ],

  // ─── Terminal ───
  // Terminal.app's keys; ⌘K clears as there (inside the terminal its own
  // keys win over the window's). Ctrl+Shift elsewhere (`_otherDesktops`).
  AppCommand.terminalCopy: [Chord(LogicalKeyboardKey.keyC, primary: true)],
  AppCommand.terminalPaste: [Chord(LogicalKeyboardKey.keyV, primary: true)],
  AppCommand.terminalSelectAll: [
    Chord(LogicalKeyboardKey.keyA, primary: true),
  ],
  AppCommand.terminalClear: [Chord(LogicalKeyboardKey.keyK, primary: true)],
  AppCommand.terminalScrollPageUp: [
    Chord(LogicalKeyboardKey.pageUp, shift: true),
  ],
  AppCommand.terminalScrollPageDown: [
    Chord(LogicalKeyboardKey.pageDown, shift: true),
  ],

  // Lists
  AppCommand.renameItem: [Chord(LogicalKeyboardKey.f2)],
  AppCommand.deleteItem: [Chord(LogicalKeyboardKey.backspace, primary: true)],
  AppCommand.filterList: [Chord(LogicalKeyboardKey.keyF, primary: true)],
  AppCommand.moveItemUp: [Chord(LogicalKeyboardKey.arrowUp, alt: true)],
  AppCommand.moveItemDown: [Chord(LogicalKeyboardKey.arrowDown, alt: true)],

  // Dialogs
  AppCommand.confirm: [Chord(LogicalKeyboardKey.enter)],
  AppCommand.dismiss: [Chord(LogicalKeyboardKey.escape)],
};

/// Chords Windows and Linux desktops press with another key than a Mac.
const _otherDesktops = <AppCommand, List<Chord>>{
  // Explorer, GNOME Files and Dolphin move the selected item to the trash
  // with Del; a Mac keyboard has no such key, so Finder uses ⌘⌫.
  AppCommand.moveToTrash: [Chord(LogicalKeyboardKey.delete)],
  AppCommand.deleteItem: [Chord(LogicalKeyboardKey.delete)],
  // Ctrl+Enter is the primary chord there; the menu takes the desktop's
  // own keys.
  AppCommand.contextMenu: [
    Chord(LogicalKeyboardKey.f10, shift: true),
    Chord(LogicalKeyboardKey.contextMenu),
  ],
  // Ctrl+Alt is AltGr on many layouts there: it types characters.
  AppCommand.panelsMoveLeft: [
    Chord(LogicalKeyboardKey.arrowLeft, control: true, shift: true),
  ],
  AppCommand.panelsMoveRight: [
    Chord(LogicalKeyboardKey.arrowRight, control: true, shift: true),
  ],

  // ─── Terminal ───
  // Ctrl+Alt is AltGr, and Ctrl+letter is a control character the shell
  // reads: the terminal's own keys take Ctrl+Shift, as in GNOME Terminal
  // and Windows Terminal; Ctrl+` is the terminal key of those desktops'
  // editors.
  AppCommand.toggleTerminal: [
    Chord(LogicalKeyboardKey.backquote, control: true),
  ],
  AppCommand.showTerminal: [
    Chord(LogicalKeyboardKey.arrowUp, control: true, shift: true),
  ],
  AppCommand.hideTerminal: [
    Chord(LogicalKeyboardKey.arrowDown, control: true, shift: true),
  ],
  AppCommand.togglePanelsOverTerminal: [
    Chord(LogicalKeyboardKey.backquote, control: true, shift: true),
  ],
  AppCommand.terminalCopy: [
    Chord(LogicalKeyboardKey.keyC, control: true, shift: true),
  ],
  AppCommand.terminalPaste: [
    Chord(LogicalKeyboardKey.keyV, control: true, shift: true),
  ],
  AppCommand.terminalSelectAll: [
    Chord(LogicalKeyboardKey.keyA, control: true, shift: true),
  ],
  AppCommand.terminalClear: [
    Chord(LogicalKeyboardKey.keyK, control: true, shift: true),
  ],
  // ─── Files core ───
  // Finder tags are macOS's alone; there Ctrl with the primary key would
  // be Ctrl+T, New Tab.
  AppCommand.editTags: [],
};
