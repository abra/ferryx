import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';

/// What a tag menu's item does.
sealed class TagPick {
  const TagPick();
}

/// Turns [choice]'s tag on for every target, or off when it was on for
/// all of them.
final class TagToggle extends TagPick {
  const TagToggle(this.choice);

  final TagChoice choice;
}

/// "New Tag…".
final class TagNew extends TagPick {
  const TagNew();
}

/// Whether the targets have a tag: all, some, none.
enum TagState { off, mixed, on }

/// A tag the menu lists, with its state over the targets.
class TagChoice {
  const TagChoice({
    required this.tag,
    required this.state,
    required this.standard,
  });

  /// The tag as it is written when added.
  final FileTag tag;
  final TagState state;

  /// One of Finder's seven colours, named in the interface's language.
  final bool standard;

  /// What picking it does: the tags to add, the names to take off. A
  /// standard tag goes off under an English Finder's name too.
  (List<FileTag>, List<String>) get edit => state == TagState.on
      ? (
          const <FileTag>[],
          [
            tag.name,
            if (standard && FileTag.finderNames[tag.color] != null)
              FileTag.finderNames[tag.color]!,
          ],
        )
      : ([tag], const <String>[]);
}

/// The menu's tags: Finder's seven colours in its order, then the named
/// tags found in the folder's rows and on the targets, each with its
/// state over [targets]. [localName] names a standard colour.
List<TagChoice> tagChoices({
  required List<FileEntry> targets,
  required Iterable<FileEntry> folderRows,
  required String Function(int color) localName,
}) {
  TagState stateOf(bool Function(FileTag tag) has) {
    var count = 0;
    for (final target in targets) {
      if (target.tags.any(has)) count++;
    }
    if (count == 0) return TagState.off;
    return count == targets.length ? TagState.on : TagState.mixed;
  }

  bool isStandard(FileTag tag) => AppTagColors.menuOrder.any(
    (color) => tag.isStandard(color, localName(color)),
  );

  final named = <String, FileTag>{};
  for (final row in [...folderRows, ...targets]) {
    for (final tag in row.tags) {
      if (isStandard(tag)) continue;
      named.putIfAbsent(tag.name.toLowerCase(), () => tag);
    }
  }
  final others = named.values.toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return [
    for (final color in AppTagColors.menuOrder)
      TagChoice(
        tag: FileTag(localName(color), color: color),
        standard: true,
        state: stateOf((t) => t.isStandard(color, localName(color))),
      ),
    for (final tag in others)
      TagChoice(
        tag: tag,
        standard: false,
        state: stateOf((t) => t.sameName(tag.name)),
      ),
  ];
}

/// The menu of [choices]: each with a check (on for all targets), a dash
/// (for some) or nothing, its colour as a dot; then "New Tag…".
List<AppMenuEntry<TagPick>> tagMenuEntries(
  BuildContext context,
  List<TagChoice> choices,
) {
  final l10n = context.l10n;
  final dot = (context.text.bodyMedium?.fontSize ?? AppIconSize.sm) * 0.75;
  final standard = choices.where((c) => c.standard).toList();
  final named = choices.where((c) => !c.standard).toList();
  AppMenuAction<TagPick> item(TagChoice choice) => AppMenuAction(
    value: TagToggle(choice),
    label: choice.tag.name,
    leading: choice.tag.color > 0
        ? AppTagDots(colors: [choice.tag.color], size: dot.roundToDouble())
        : const SizedBox.shrink(),
    checked: choice.state == TagState.on,
    mixed: choice.state == TagState.mixed,
  );
  return [
    AppMenuSection(l10n.tagsMenuTitle),
    for (final choice in standard) item(choice),
    if (named.isNotEmpty) ...[
      const AppMenuSeparator(),
      for (final choice in named) item(choice),
    ],
    const AppMenuSeparator(),
    AppMenuAction(
      value: const TagNew(),
      label: l10n.tagsNew,
      icon: AppIcons.add,
    ),
  ];
}

/// `:tag red,work` adds, `:tag -red` takes off; a standard colour may be
/// named in the interface's language or in English, and a name the
/// folder's rows already carry keeps its colour. Answers the tags to add
/// and the names to take off.
(List<FileTag>, List<String>) parseTagCommand(
  String arg, {
  required String Function(int color) localName,
  required Iterable<FileEntry> folderRows,
}) {
  final add = <FileTag>[];
  final remove = <String>[];
  final known = <String, FileTag>{
    for (final row in folderRows)
      for (final tag in row.tags) tag.name.toLowerCase(): tag,
  };
  for (final raw in arg.split(',')) {
    var word = raw.trim();
    if (word.isEmpty) continue;
    final off = word.startsWith('-');
    if (off) word = word.substring(1).trim();
    if (word.isEmpty) continue;
    final color = [
      for (final c in AppTagColors.menuOrder)
        if (word.toLowerCase() == localName(c).toLowerCase() ||
            word.toLowerCase() == FileTag.finderNames[c]!.toLowerCase() ||
            (c == 1 && word.toLowerCase() == 'grey'))
          c,
    ].firstOrNull;
    if (off) {
      remove.add(color == null ? word : localName(color));
      if (color != null) remove.add(FileTag.finderNames[color]!);
      continue;
    }
    add.add(
      color != null
          ? FileTag(localName(color), color: color)
          : known[word.toLowerCase()] ?? FileTag(word),
    );
  }
  return (add, remove);
}
