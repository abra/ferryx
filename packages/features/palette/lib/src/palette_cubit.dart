import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';
import 'package:shortcuts/shortcuts.dart';

import 'fuzzy_match.dart';

/// A command the palette may offer, with the names the view gives it: its
/// label in the interface's language and, when that is not English, the
/// English one too (so English words find commands in any language), and
/// its keys as labels.
@immutable
class PaletteCommand extends Equatable {
  const PaletteCommand({
    required this.command,
    required this.label,
    this.englishLabel,
    this.keys = const [],
  });

  final AppCommand command;
  final String label;
  final String? englishLabel;
  final List<String> keys;

  CommandSection get section => command.section;

  @override
  List<Object?> get props => [command, label, englishLabel, keys];
}

/// A row of the palette's list.
sealed class PaletteRow extends Equatable {
  const PaletteRow();
}

/// The caption of a group: a section, or the commands used lately
/// ([section] `null`).
final class PaletteGroupRow extends PaletteRow {
  const PaletteGroupRow(this.section);

  final CommandSection? section;

  @override
  List<Object?> get props => [section];
}

/// A command, with what matched the query: ranges of its label, or of
/// its English label when that matched better ([englishRanges]).
final class PaletteCommandRow extends PaletteRow {
  const PaletteCommandRow(
    this.entry, {
    this.labelRanges = const [],
    this.englishRanges,
  });

  final PaletteCommand entry;
  final List<(int, int)> labelRanges;
  final List<(int, int)>? englishRanges;

  @override
  List<Object?> get props => [entry, labelRanges, englishRanges];
}

@immutable
class PaletteState extends Equatable {
  const PaletteState({this.query = '', this.rows = const []});

  final String query;
  final List<PaletteRow> rows;

  @override
  List<Object?> get props => [query, rows];
}

/// The palette's list for what is typed: with nothing typed, the
/// commands used lately, then every command by section; else the commands
/// whose label (or English label) the query fuzzily matches, the best
/// first, a tie going to the one used more lately, then to the shorter
/// label.
class PaletteCubit extends Cubit<PaletteState> {
  PaletteCubit({
    required this._commands,
    this._recent = const [],
    this.recentShown = 5,
  }) : super(const PaletteState()) {
    // The list before anything is typed.
    emit(PaletteState(rows: _browse()));
  }

  final List<PaletteCommand> _commands;

  /// The commands run from the palette lately, the newest first.
  final List<AppCommand> _recent;

  /// How many of [_recent] lead the list before anything is typed.
  final int recentShown;

  void setQuery(String query) {
    if (query == state.query) return;
    emit(
      PaletteState(
        query: query,
        rows: query.trim().isEmpty ? _browse() : _search(query),
      ),
    );
  }

  List<PaletteRow> _browse() {
    final byCommand = {for (final c in _commands) c.command: c};
    final recent = [
      for (final command in _recent) ?byCommand[command],
    ].take(recentShown).toList(growable: false);
    final shown = {for (final r in recent) r.command};
    final rows = <PaletteRow>[
      if (recent.isNotEmpty) ...[
        const PaletteGroupRow(null),
        for (final entry in recent) PaletteCommandRow(entry),
      ],
    ];
    for (final section in CommandSection.values) {
      final entries = [
        for (final entry in _commands)
          if (entry.section == section && !shown.contains(entry.command)) entry,
      ]..sort((a, b) => a.command.index.compareTo(b.command.index));
      if (entries.isEmpty) continue;
      rows
        ..add(PaletteGroupRow(section))
        ..addAll(entries.map(PaletteCommandRow.new));
    }
    return rows;
  }

  List<PaletteRow> _search(String query) {
    final hits = <(PaletteCommandRow, int, int)>[];
    for (final entry in _commands) {
      final label = fuzzyMatch(query, entry.label);
      final english = switch (entry.englishLabel) {
        final text? => fuzzyMatch(query, text),
        null => null,
      };
      if (label == null && english == null) continue;
      final byEnglish =
          english != null && (label == null || english.score > label.score);
      final row = byEnglish
          ? PaletteCommandRow(entry, englishRanges: english.ranges)
          : PaletteCommandRow(entry, labelRanges: label!.ranges);
      final length = byEnglish
          ? entry.englishLabel!.length
          : entry.label.length;
      hits.add((row, byEnglish ? english.score : label!.score, length));
    }
    int recency(PaletteCommandRow row) {
      final at = _recent.indexOf(row.entry.command);
      return at < 0 ? _recent.length : at;
    }

    hits.sort((a, b) {
      final byScore = b.$2.compareTo(a.$2);
      if (byScore != 0) return byScore;
      final byRecency = recency(a.$1).compareTo(recency(b.$1));
      if (byRecency != 0) return byRecency;
      final byLength = a.$3.compareTo(b.$3);
      if (byLength != 0) return byLength;
      return a.$1.entry.command.index.compareTo(b.$1.entry.command.index);
    });
    return [for (final (row, _, _) in hits) row];
  }
}
