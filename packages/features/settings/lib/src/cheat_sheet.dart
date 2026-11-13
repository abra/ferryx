import 'dart:math' as math;

import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shortcuts/shortcuts.dart';

/// ⌘/: every key the window answers, by scope.
Future<void> showCheatSheet(
  BuildContext context, {
  required ShortcutMap shortcutMap,
  required TargetPlatform platform,
  bool vim = false,
}) => showAppDialog<void>(
  context,
  (context) =>
      CheatSheetDialog(shortcutMap: shortcutMap, platform: platform, vim: vim),
);

class CheatSheetDialog extends StatefulWidget {
  const CheatSheetDialog({
    required this.shortcutMap,
    required this.platform,
    required this.vim,
    super.key,
  });

  final ShortcutMap shortcutMap;
  final TargetPlatform platform;

  /// Keys read as Vim writes them, as the panels take them.
  final bool vim;

  @override
  State<CheatSheetDialog> createState() => _CheatSheetDialogState();
}

class _CheatSheetDialogState extends State<CheatSheetDialog> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<String> _labels(Chord chord) => [
    widget.vim ? chord.vimLabel(widget.platform) : chord.label(widget.platform),
  ];

  /// The sheet's height: the dialog's, as far as the window allows once
  /// the dialog's inset, its padding, the title, the hint and the actions
  /// have theirs; never less than a picker's list.
  double _height(BuildContext context) {
    final metrics = context.metrics;
    final chrome =
        2 * AppSpacing.xl +
        4 * metrics.contentMargin +
        3 * metrics.controlHeightLarge;
    final room = MediaQuery.sizeOf(context).height - chrome;
    return math.max(
      AppSizes.pickerListMaxHeight,
      math.min(AppSizes.panelDialogHeight, room),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final needle = _query.trim().toLowerCase();
    bool shown(AppCommand command) {
      if (needle.isEmpty) return true;
      if (l10n.commandLabel(command).toLowerCase().contains(needle)) {
        return true;
      }
      return widget.shortcutMap
          .chordsFor(command)
          .expand(_labels)
          .any((label) => label.toLowerCase().contains(needle));
    }

    final sections = [
      for (final scope in CommandScope.values)
        _SectionData(
          scope: scope,
          title: l10n.scopeLabel(scope),
          commands: [
            for (final command in AppCommand.inScope(scope))
              if (widget.shortcutMap.isAvailable(command) &&
                  widget.shortcutMap.chordsFor(command).isNotEmpty &&
                  shown(command))
                command,
          ],
        ),
    ].where((s) => s.commands.isNotEmpty).toList(growable: false);
    return CommandShortcuts(
      shortcuts: widget.shortcutMap.toShortcuts(
        widget.platform,
        scopes: const {CommandScope.dialogs},
      ),
      child: CommandHandlers(
        handlers: {
          AppCommand.dismiss: () => Navigator.of(context).pop(),
          AppCommand.cheatSheet: () => Navigator.of(context).pop(),
        },
        child: AppDialog(
          title: l10n.cheatSheetTitle,
          width: AppSizes.panelDialogWidth,
          body: SizedBox(
            height: _height(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.cheatSheetHint,
                  style: context.text.bodySmall?.copyWith(
                    color: colors.textMuted,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                AppSearchField(
                  hintText: l10n.hotkeysSearchHint,
                  controller: _search,
                  autofocus: true,
                  onChanged: (q) => setState(() => _query = q),
                ),
                const SizedBox(height: AppSpacing.md),
                Expanded(
                  child: AppScrollKeys(
                    child: _Columns(
                      sections: sections,
                      shortcutMap: widget.shortcutMap,
                      platform: widget.platform,
                      vim: widget.vim,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.actionClose),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionData {
  const _SectionData({
    required this.scope,
    required this.title,
    required this.commands,
  });

  final CommandScope scope;
  final String title;
  final List<AppCommand> commands;

  /// The rows the section takes: its caption and its commands.
  int get rows => commands.length + 1;
}

/// The sections flowed into as many columns as the width holds, each at
/// least [AppSizes.cheatSheetColumnWidth], in order and about as tall as
/// one another; the whole scrolls as one.
class _Columns extends StatelessWidget {
  const _Columns({
    required this.sections,
    required this.shortcutMap,
    required this.platform,
    required this.vim,
  });

  final List<_SectionData> sections;
  final ShortcutMap shortcutMap;
  final TargetPlatform platform;
  final bool vim;

  /// [sections] split into up to [count] runs in order, each closing at
  /// the section that brings the rows so far nearest its share of the
  /// whole (a section goes to whichever side of the cut leaves the
  /// columns more even).
  static List<List<_SectionData>> flow(List<_SectionData> sections, int count) {
    final columns = <List<_SectionData>>[];
    final total = sections.fold(0, (sum, s) => sum + s.rows);
    var current = <_SectionData>[];
    var filled = 0;
    void close() {
      columns.add(current);
      current = <_SectionData>[];
    }

    for (final section in sections) {
      final share = total * (columns.length + 1) / count;
      final after = filled + section.rows;
      if (current.isNotEmpty && columns.length < count - 1 && after > share) {
        if (after - share < share - filled) {
          current.add(section);
          filled = after;
          close();
          continue;
        }
        close();
      }
      current.add(section);
      filled += section.rows;
    }
    if (current.isNotEmpty) close();
    return columns;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final count = math.max(
        1,
        (constraints.maxWidth / AppSizes.cheatSheetColumnWidth).floor(),
      );
      final columns = flow(sections, count);
      return ListView(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < columns.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.xl),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final section in columns[i])
                        _Section(
                          key: ValueKey(section.scope),
                          title: section.title,
                          commands: section.commands,
                          shortcutMap: shortcutMap,
                          platform: platform,
                          vim: vim,
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      );
    },
  );
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.commands,
    required this.shortcutMap,
    required this.platform,
    required this.vim,
    super.key,
  });

  final String title;
  final List<AppCommand> commands;
  final ShortcutMap shortcutMap;
  final TargetPlatform platform;

  /// Keys read as Vim writes them, as the panels take them.
  final bool vim;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final metrics = context.metrics;
    return Padding(
      // The label pads itself above by a part of the group gap.
      padding: EdgeInsets.only(bottom: metrics.contentMargin - AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSectionLabel(title, inset: false),
          for (final command in commands)
            ConstrainedBox(
              key: ValueKey(command),
              constraints: BoxConstraints(minHeight: metrics.listRowHeight),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.commandLabel(command),
                      style: context.text.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  AppKeyCaps([
                    for (final chord in shortcutMap.chordsFor(command))
                      vim ? chord.vimLabel(platform) : chord.label(platform),
                  ]),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
