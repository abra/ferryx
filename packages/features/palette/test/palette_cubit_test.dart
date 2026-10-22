import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:palette_feature/palette_feature.dart';
import 'package:shortcuts/shortcuts.dart';

void main() {
  const copyTo = PaletteCommand(
    command: AppCommand.copyTo,
    label: 'Копировать',
    englishLabel: 'Copy To',
    keys: ['F5'],
  );
  const refresh = PaletteCommand(
    command: AppCommand.refresh,
    label: 'Обновить',
    englishLabel: 'Refresh',
  );
  const newFolder = PaletteCommand(
    command: AppCommand.newFolder,
    label: 'Новая папка',
    englishLabel: 'New Folder',
  );
  const goHome = PaletteCommand(
    command: AppCommand.goHome,
    label: 'Домой',
    englishLabel: 'Home',
  );
  const moveDown = PaletteCommand(
    command: AppCommand.moveDown,
    label: 'Вниз',
    englishLabel: 'Down',
  );
  const all = [moveDown, refresh, goHome, copyTo, newFolder];

  List<AppCommand?> commandsOf(PaletteState state) => [
    for (final row in state.rows)
      switch (row) {
        PaletteCommandRow(:final entry) => entry.command,
        PaletteGroupRow() => null,
      },
  ];

  test('with nothing typed: the recent commands, then every section in '
      'order, each command once', () {
    final cubit = PaletteCubit(
      commands: all,
      // Find Files is not offered here: it is left out.
      recent: const [AppCommand.goHome, AppCommand.findFiles],
    );
    expect(cubit.state.rows, [
      const PaletteGroupRow(null),
      const PaletteCommandRow(goHome),
      const PaletteGroupRow(CommandSection.file),
      const PaletteCommandRow(newFolder),
      const PaletteGroupRow(CommandSection.view),
      const PaletteCommandRow(refresh),
      const PaletteGroupRow(CommandSection.command),
      const PaletteCommandRow(copyTo),
      const PaletteGroupRow(CommandSection.panel),
      const PaletteCommandRow(moveDown),
    ]);
    cubit.close();
  });

  test('at most recentShown recent commands lead the list', () {
    final cubit = PaletteCubit(
      commands: all,
      recent: const [AppCommand.goHome, AppCommand.copyTo, AppCommand.refresh],
      recentShown: 2,
    );
    expect(commandsOf(cubit.state).take(3), [
      null,
      AppCommand.goHome,
      AppCommand.copyTo,
    ]);
    expect(commandsOf(cubit.state).where((c) => c == AppCommand.refresh), [
      AppCommand.refresh,
    ]);
    cubit.close();
  });

  blocTest<PaletteCubit, PaletteState>(
    'a query ranks the matches, best first, without groups',
    build: () => PaletteCubit(commands: all),
    act: (cubit) => cubit.setQuery('нов'),
    verify: (cubit) {
      expect(cubit.state.query, 'нов');
      // The word's start first; "Обновить" holds the letters mid-word.
      expect(cubit.state.rows, [
        const PaletteCommandRow(newFolder, labelRanges: [(0, 3)]),
        const PaletteCommandRow(refresh, labelRanges: [(2, 5)]),
      ]);
    },
  );

  blocTest<PaletteCubit, PaletteState>(
    'English words find commands named in another language',
    build: () => PaletteCubit(commands: all),
    act: (cubit) => cubit.setQuery('copy'),
    verify: (cubit) {
      expect(cubit.state.rows, [
        const PaletteCommandRow(copyTo, englishRanges: [(0, 4)]),
      ]);
    },
  );

  blocTest<PaletteCubit, PaletteState>(
    'a tie goes to the command used more lately',
    build: () => PaletteCubit(
      commands: const [
        PaletteCommand(command: AppCommand.selectAll, label: 'Select All'),
        PaletteCommand(command: AppCommand.deselectAll, label: 'Select Al'),
      ],
      recent: const [AppCommand.selectAll],
    ),
    act: (cubit) => cubit.setQuery('sel'),
    verify: (cubit) {
      expect(commandsOf(cubit.state), [
        AppCommand.selectAll,
        AppCommand.deselectAll,
      ]);
    },
  );

  blocTest<PaletteCubit, PaletteState>(
    'nothing matches: no rows; clearing the query browses again',
    build: () => PaletteCubit(commands: all),
    act: (cubit) => cubit
      ..setQuery('zzz')
      ..setQuery(''),
    expect: () => [
      const PaletteState(query: 'zzz'),
      isA<PaletteState>().having(
        (s) => s.rows.first,
        'first row',
        const PaletteGroupRow(CommandSection.file),
      ),
    ],
  );
}
