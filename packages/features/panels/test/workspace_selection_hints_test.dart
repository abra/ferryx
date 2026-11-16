import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:panels_feature/panels_feature.dart';

import 'support/workspace_harness.dart';

void main() {
  setUpAll(() async {
    WorkspaceHarness.registerFallbacks();
    for (final (family, file) in [
      ('Inter', 'Inter-Variable.ttf'),
      ('Geist Mono', 'GeistMono-Variable.ttf'),
    ]) {
      await (FontLoader(family)..addFont(
            rootBundle.load('packages/component_library/fonts/$file'),
          ))
          .load();
    }
  });
  late WorkspaceHarness h;
  setUp(() async {
    h = WorkspaceHarness();
    await h.setUp(vim: true);
  });
  tearDown(() => h.tearDown());

  for (final language in ['en', 'ru']) {
    for (final mode in ['normal', 'visual', 'ordinary']) {
      testWidgets('$language $mode selection shows copy hints at 900px', (
        tester,
      ) async {
        if (mode == 'ordinary') {
          await tester.runAsync(
            () =>
                h.preferences.update((prefs) => prefs.copyWith(vimMode: false)),
          );
        }
        final locale = Locale(language);
        await h.pump(tester, size: const Size(900, 600), locale: locale);
        final panel = tester
            .element(find.byType(PanelView).first)
            .read<PanelCubit>();
        panel.moveCursorTo(panel.state.active!.firstItemIndex);
        await tester.pumpAndSettle();
        expect(panel.state.active!.selected, isEmpty);

        await h.press(
          tester,
          mode == 'visual' ? LogicalKeyboardKey.keyV : LogicalKeyboardKey.space,
          character: mode == 'visual' ? 'v' : ' ',
          alt: mode == 'ordinary',
        );
        await h.press(
          tester,
          mode == 'visual' ? LogicalKeyboardKey.keyJ : LogicalKeyboardKey.space,
          character: mode == 'visual' ? 'j' : ' ',
          alt: mode == 'ordinary',
        );

        expect(panel.state.active!.selected, hasLength(2));
        expect(panel.state.active!.visual, mode == 'visual');
        if (mode == 'normal') {
          expect(
            find.descendant(
              of: find.byType(PanelView).first,
              matching: find.text('NORMAL'),
            ),
            findsOneWidget,
          );
        }
        final l10n = lookupFerryxLocalizations(locale);
        final footer = find.byType(KeyHintStrip);
        final bounds = tester.getRect(footer);
        expect(bounds.width, 900);
        for (final (key, label) in [
          (mode == 'ordinary' ? '⇧⌘C' : 'yn', l10n.cmdCopyItemName),
          (mode == 'ordinary' ? '⌥⌘C' : 'yp', l10n.cmdCopyItemPath),
        ]) {
          final cap = find.descendant(
            of: footer,
            matching: find.byWidgetPredicate(
              (widget) => widget is AppKeyCap && widget.label == key,
            ),
          );
          final text = find.descendant(of: footer, matching: find.text(label));
          expect(cap, findsOneWidget);
          expect(text, findsOneWidget);
          expect(bounds.contains(tester.getRect(cap).topLeft), isTrue);
          expect(bounds.contains(tester.getRect(text).bottomRight), isTrue);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
