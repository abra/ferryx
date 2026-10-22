import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shortcuts/shortcuts.dart';

import '../path_text.dart';
import 'dialog_support.dart';

/// Manage Favorites: the list, with add, rename and remove; a click picks
/// a row, Return or a double click opens its folder, Done keeps the list.
Future<Location?> showFavoritesDialog(
  BuildContext context, {
  required List<Favorite> favorites,
  required Location current,
  required ValueChanged<List<Favorite>> onChanged,
}) => showWorkspaceDialog<Location>(
  context,
  (context) => _FavoritesDialog(
    favorites: favorites,
    current: current,
    onChanged: onChanged,
  ),
);

class _FavoritesDialog extends StatefulWidget {
  const _FavoritesDialog({
    required this.favorites,
    required this.current,
    required this.onChanged,
  });

  final List<Favorite> favorites;
  final Location current;
  final ValueChanged<List<Favorite>> onChanged;

  @override
  State<_FavoritesDialog> createState() => _FavoritesDialogState();
}

class _FavoritesDialogState extends State<_FavoritesDialog> {
  late List<Favorite> _favorites = [...widget.favorites];

  /// The row the keys are on: the one with the focus, which Rename,
  /// Delete and Move act on.
  int _focused = 0;
  int? _lastTapIndex;
  DateTime? _lastTapAt;

  void _set(List<Favorite> next) {
    setState(() => _favorites = next);
    widget.onChanged(next);
  }

  void _addCurrent() {
    if (_favorites.any((f) => f.location == widget.current)) return;
    _set([..._favorites, Favorite(location: widget.current)]);
  }

  void _open(int index) =>
      Navigator.of(context).pop(_favorites[index].location);

  void _remove(int index) {
    final next = [..._favorites]..removeAt(index);
    _set(next);
    _focused = _focused.clamp(0, next.isEmpty ? 0 : next.length - 1);
  }

  Future<void> _rename(int index) async {
    final l10n = context.l10n;
    final favorite = _favorites[index];
    final name = await AppDialog.prompt(
      context,
      title: l10n.favoritesRenameTitle,
      confirmLabel: l10n.actionSave,
      cancelLabel: l10n.actionCancel,
      initialValue: favorite.label,
    );
    if (name == null) return;
    final next = [..._favorites];
    next[index] = Favorite(
      location: favorite.location,
      title: name.trim().isEmpty ? null : name.trim(),
    );
    _set(next);
  }

  void _move(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _favorites.length) return;
    final next = [..._favorites];
    final item = next.removeAt(index);
    next.insert(target, item);
    _set(next);
    setState(() => _focused = target);
  }

  /// A click picks the row; a second one within the double-tap time
  /// opens it.
  void _tap(int index) {
    final now = DateTime.now();
    final again =
        _lastTapIndex == index &&
        _lastTapAt != null &&
        now.difference(_lastTapAt!) <= kDoubleTapTimeout;
    _lastTapIndex = index;
    _lastTapAt = now;
    if (again) {
      _open(index);
      return;
    }
    setState(() => _focused = index);
  }

  Future<void> _menu(int index, Rect anchor) async {
    final l10n = context.l10n;
    final picked = await showAppMenu<String>(
      context: context,
      anchor: anchor,
      entries: [
        AppMenuAction(
          value: 'open',
          label: l10n.actionOpen,
          icon: AppIcons.folderOpen,
        ),
        AppMenuAction(
          value: 'rename',
          label: l10n.actionRename,
          icon: AppIcons.edit,
        ),
        const AppMenuSeparator(),
        AppMenuAction(
          value: 'up',
          label: l10n.cmdMoveItemUp,
          icon: AppIcons.up,
        ),
        AppMenuAction(
          value: 'down',
          label: l10n.cmdMoveItemDown,
          icon: AppIcons.chevronDown,
        ),
        const AppMenuSeparator(),
        AppMenuAction(
          value: 'remove',
          label: l10n.actionRemove,
          icon: AppIcons.trash,
          danger: true,
        ),
      ],
    );
    if (!mounted) return;
    switch (picked) {
      case 'open':
        _open(index);
      case 'rename':
        await _rename(index);
      case 'up':
        _move(index, -1);
      case 'down':
        _move(index, 1);
      case 'remove':
        _remove(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final hasCurrent = _favorites.any((f) => f.location == widget.current);
    return AppDialog(
      title: l10n.favoritesTitle,
      body: CommandHandlers(
        handlers: {
          AppCommand.renameItem: () {
            if (_favorites.isNotEmpty) _rename(_focused);
          },
          AppCommand.deleteItem: () {
            if (_favorites.isNotEmpty) _remove(_focused);
          },
          AppCommand.moveItemUp: () => _move(_focused, -1),
          AppCommand.moveItemDown: () => _move(_focused, 1),
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: AppSizes.pickerListMaxHeight,
              ),
              child: _favorites.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.lg,
                      ),
                      child: Text(
                        l10n.favoritesEmpty,
                        style: context.text.bodyMedium?.copyWith(
                          color: colors.textMuted,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _favorites.length,
                      itemBuilder: (context, index) => _FavoriteRow(
                        key: ValueKey(_favorites[index].location.encode()),
                        favorite: _favorites[index],
                        selected: index == _focused,
                        onFocused: () => setState(() => _focused = index),
                        onTap: () => _tap(index),
                        onOpen: () => _open(index),
                        onMenu: (anchor) => _menu(index, anchor),
                      ),
                    ),
            ),
            dialogRowGap,
            Row(
              spacing: context.metrics.toolbarSpacing,
              children: [
                OutlinedButton.icon(
                  onPressed: hasCurrent ? null : _addCurrent,
                  icon: const Icon(AppIcons.add, size: AppIconSize.sm),
                  label: Text(l10n.favoritesAddCurrent),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionDone),
        ),
      ],
    );
  }
}

/// One favorite: its name, the path after it in the secondary colour.
/// The focus moving onto it (by key or click) makes it the dialog's row;
/// Return opens it over the dialog's own default.
class _FavoriteRow extends StatelessWidget {
  const _FavoriteRow({
    required this.favorite,
    required this.selected,
    required this.onFocused,
    required this.onTap,
    required this.onOpen,
    required this.onMenu,
    super.key,
  });

  final Favorite favorite;
  final bool selected;
  final VoidCallback onFocused;
  final VoidCallback onTap;
  final VoidCallback onOpen;
  final void Function(Rect anchor) onMenu;

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.enter): _OpenIntent(),
      SingleActivator(LogicalKeyboardKey.numpadEnter): _OpenIntent(),
    },
    child: Actions(
      actions: {
        _OpenIntent: CallbackAction<_OpenIntent>(
          onInvoke: (_) {
            onOpen();
            return null;
          },
        ),
      },
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (focused) {
          if (focused) onFocused();
        },
        child: Builder(
          builder: (rowContext) => AppNavItem(
            label: favorite.label,
            icon: favorite.location.isNative
                ? AppIcons.folder
                : AppIcons.fileArchive,
            trailing: Text(
              PathText.shortened(favorite.location.display),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            selected: selected,
            autofocus: selected,
            onTap: onTap,
            onSecondaryTap: () => onMenu(keyboardMenuAnchor(rowContext)),
            tooltip: favorite.location.display,
          ),
        ),
      ),
    ),
  );
}

class _OpenIntent extends Intent {
  const _OpenIntent();
}
