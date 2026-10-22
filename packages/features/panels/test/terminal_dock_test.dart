import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panels_feature/panels_feature.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:shortcuts/shortcuts.dart';

void main() {
  group('TerminalDockCubit', () {
    blocTest<TerminalDockCubit, TerminalDock>(
      'shown under the panels, then hidden; hiding twice is nothing',
      build: TerminalDockCubit.new,
      act: (dock) => dock
        ..show()
        ..show()
        ..hide()
        ..hide(),
      expect: () => const [
        TerminalDock(mode: TerminalPlace.overlapped),
        TerminalDock(),
      ],
    );

    blocTest<TerminalDockCubit, TerminalDock>(
      'the panels go over the terminal and come back with it under them',
      build: TerminalDockCubit.new,
      act: (dock) => dock
        ..togglePanels()
        ..togglePanels(),
      expect: () => const [
        TerminalDock(mode: TerminalPlace.panelsHidden),
        TerminalDock(mode: TerminalPlace.overlapped),
      ],
    );

    blocTest<TerminalDockCubit, TerminalDock>(
      'the whole window goes back where the terminal was',
      build: () =>
          TerminalDockCubit(const TerminalDock(mode: TerminalPlace.overlapped)),
      act: (dock) => dock
        ..toggleFullWindow()
        ..toggleFullWindow(),
      expect: () => const [
        TerminalDock(
          mode: TerminalPlace.fullWindow,
          beforeFullWindow: TerminalPlace.overlapped,
        ),
        TerminalDock(
          mode: TerminalPlace.overlapped,
          beforeFullWindow: TerminalPlace.overlapped,
        ),
      ],
    );

    blocTest<TerminalDockCubit, TerminalDock>(
      'from the whole window a hidden terminal goes back to hidden; the '
      'panels key brings them back over the terminal',
      build: TerminalDockCubit.new,
      act: (dock) => dock
        ..toggleFullWindow()
        ..toggleFullWindow()
        ..toggleFullWindow()
        ..togglePanels(),
      expect: () => const [
        TerminalDock(mode: TerminalPlace.fullWindow),
        TerminalDock(),
        TerminalDock(mode: TerminalPlace.fullWindow),
        TerminalDock(mode: TerminalPlace.overlapped),
      ],
    );

    blocTest<TerminalDockCubit, TerminalDock>(
      'the height stays within its bounds, however small the window',
      build: TerminalDockCubit.new,
      act: (dock) => dock
        ..setLines(30, maxLines: 20)
        ..setLines(0, maxLines: 20)
        ..setLines(8, maxLines: 1),
      expect: () => const [
        TerminalDock(lines: 20),
        TerminalDock(lines: TerminalDock.minLines),
      ],
    );

    test('what each place shows', () {
      expect(const TerminalDock().shown, isFalse);
      expect(const TerminalDock().panelsShown, isTrue);
      const under = TerminalDock(mode: TerminalPlace.overlapped);
      expect(under.shown && under.panelsShown, isTrue);
      for (final place in [
        TerminalPlace.panelsHidden,
        TerminalPlace.fullWindow,
      ]) {
        final dock = TerminalDock(mode: place);
        expect(dock.shown, isTrue);
        expect(dock.panelsShown, isFalse);
      }
    });
  });

  group('terminal hints', () {
    test('under the panels: hide first; over them: the panels first', () {
      final under = terminalHintsFor(TerminalPlace.overlapped);
      expect((under.first as CommandHint).command, AppCommand.hideTerminal);
      final over = terminalHintsFor(TerminalPlace.panelsHidden);
      expect(
        (over.first as CommandHint).command,
        AppCommand.togglePanelsOverTerminal,
      );
      for (final hints in [under, over]) {
        expect(hints.length, lessThanOrEqualTo(5));
        expect(
          hints.whereType<CommandHint>().map((h) => h.command),
          contains(AppCommand.terminalClear),
        );
      }
    });
  });
}
