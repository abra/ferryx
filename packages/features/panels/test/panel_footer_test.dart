import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panels_feature/panels_feature.dart';
import 'package:panels_feature/src/panel/panel_footer.dart';

import 'support/workspace_harness.dart';

void main() {
  setUpAll(WorkspaceHarness.registerFallbacks);

  late WorkspaceHarness h;

  tearDown(() => h.tearDown());

  group('without Vim keys', () {
    setUp(() async {
      h = WorkspaceHarness();
      await h.setUp();
    });

    testWidgets('the count and the free space keep to the footer\'s end, and '
        'the footer stands as high as the hint line under it', (tester) async {
      await h.pump(tester);
      final footer = find.byType(PanelFooter).first;
      final count = tester.getRect(
        find.descendant(of: footer, matching: find.text('3 items')),
      );
      expect(tester.getRect(footer).right - count.right, AppSpacing.sm);
      expect(
        tester.getSize(footer).height,
        tester.getSize(find.byType(KeyHintStrip)).height,
      );
    });
  });

  group('with Vim keys', () {
    setUp(() async {
      h = WorkspaceHarness();
      await h.setUp(vim: true);
    });

    Finder hint(String text) => find.descendant(
      of: find.byType(KeyHintStrip),
      matching: find.text(text),
    );

    testWidgets('tab hints follow creation, the active panel and closing', (
      tester,
    ) async {
      await h.pump(tester);
      expect(hint('gt'), findsNothing);
      await h.press(tester, LogicalKeyboardKey.keyT, meta: true);
      expect(hint('gt'), findsOneWidget);
      expect(hint('gT'), findsOneWidget);

      // The advertised sequences select tabs in the active panel.
      await h.press(tester, LogicalKeyboardKey.keyG);
      await h.press(tester, LogicalKeyboardKey.keyT);
      expect(tester.widget<AppTabStrip>(find.byType(AppTabStrip)).active, 0);
      await h.press(tester, LogicalKeyboardKey.keyG);
      await h.press(tester, LogicalKeyboardKey.keyT, shift: true);
      expect(tester.widget<AppTabStrip>(find.byType(AppTabStrip)).active, 1);

      await h.press(tester, LogicalKeyboardKey.tab);
      expect(hint('gt'), findsNothing, reason: 'the right panel has one tab');
      await h.press(tester, LogicalKeyboardKey.tab);
      expect(hint('gt'), findsOneWidget);
      await h.press(tester, LogicalKeyboardKey.keyW, meta: true);
      expect(hint('gt'), findsNothing);
      expect(hint('gT'), findsNothing);
    });

    testWidgets('a command line hides tab hints until the panel has keys', (
      tester,
    ) async {
      await h.pump(tester);
      await h.press(tester, LogicalKeyboardKey.keyT, meta: true);
      expect(hint('gt'), findsOneWidget);
      await h.press(tester, LogicalKeyboardKey.semicolon, shift: true);
      expect(find.byType(TextField), findsOneWidget);
      expect(hint('gt'), findsNothing);
      expect(hint('gT'), findsNothing);
      await h.press(tester, LogicalKeyboardKey.escape);
      expect(find.byType(TextField), findsNothing);
      expect(hint('gt'), findsOneWidget);
      expect(hint('gT'), findsOneWidget);
    });

    testWidgets('the keys of the hint line are typed text, in the monospace '
        'face, where `l` does not read as a bar', (tester) async {
      await h.pump(tester);
      Finder cap(String label) => find.descendant(
        of: find.byType(KeyHintStrip),
        matching: find.byWidgetPredicate(
          (w) => w is AppKeyCap && w.label == label,
        ),
      );
      expect(
        tester.widget<AppKeyCap>(cap('gl')).typed,
        isTrue,
        reason: 'Enter, as Vim types it in any mode',
      );
      expect(
        tester.widget<AppKeyCap>(cap('⇧⌘N')).typed,
        isFalse,
        reason: 'a chord, not typed text',
      );
      final face = tester
          .widget<Text>(
            find.descendant(of: cap('gl'), matching: find.byType(Text)),
          )
          .style!;
      final mono = AppTheme.of(
        AppPlatformStyle.macos,
        Brightness.light,
      ).extension<AppMetrics>()!.typeScale.mono;
      expect(face.fontFamily, mono.fontFamily);
    });

    testWidgets(
      'position follows the cursor and filter in both languages and themes',
      (tester) async {
        for (final language in ['en', 'ru']) {
          for (final brightness in Brightness.values) {
            await h.pump(
              tester,
              locale: Locale(language),
              brightness: brightness,
              size: const Size(900, 600),
              textScale: 1.3,
            );
            final panel = find.byType(PanelView).first;
            final c = tester.element(panel).read<PanelCubit>();
            final footer = find.descendant(
              of: panel,
              matching: find.byType(PanelFooter),
            );
            final l10n = tester.element(footer).l10n;
            expect(
              find.descendant(
                of: footer,
                matching: find.text(l10n.panelItemsCount(3)),
              ),
              findsOneWidget,
            );
            c.moveCursorTo(2);
            await h.settle(tester);
            expect(
              find.descendant(
                of: footer,
                matching: find.text(l10n.itemPosition(2, 3)),
              ),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: footer,
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is AppTooltip &&
                      widget.message == l10n.itemPositionHelp(2, 3),
                ),
              ),
              findsOneWidget,
            );
            await tester.runAsync(
              () => h.preferences.update(
                (p) => p.copyWith(quickSearchOnlyMatching: true),
              ),
            );
            c.quickSearchType('a');
            await h.settle(tester);
            expect(
              find.descendant(
                of: footer,
                matching: find.text(l10n.itemPosition(1, 1)),
              ),
              findsOneWidget,
            );
            c.quickSearchType('no-match');
            await h.settle(tester);
            expect(
              find.descendant(
                of: footer,
                matching: find.text(l10n.panelItemsCount(0)),
              ),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          }
        }
      },
    );

    testWidgets(
      'large totals are localized and capped Flat results keep their plus marker',
      (tester) async {
        const file = FileEntry(
          name: 'a.txt',
          path: '/a.txt',
          kind: EntryKind.file,
          isDir: false,
        );
        for (final language in ['en', 'ru']) {
          final l10n = lookupFerryxLocalizations(Locale(language));
          for (final capped in [false, true]) {
            await tester.pumpWidget(
              MaterialApp(
                theme: AppTheme.light(AppPlatformStyle.macos),
                locale: Locale(language),
                localizationsDelegates: FerryxSupportedLocales.delegates,
                supportedLocales: FerryxSupportedLocales.locales,
                home: Scaffold(
                  body: Align(
                    alignment: Alignment.bottomCenter,
                    child: PanelFooter(
                      tab: PanelTabState(
                        id: 't',
                        location: const Location.native('/'),
                        sort: const SortOptions(),
                        rows: List.filled(100000, file),
                        cursor: 120,
                        flat: capped
                            ? const FlatView(
                                generation: 1,
                                walking: false,
                                capped: true,
                              )
                            : null,
                      ),
                      active: true,
                      vim: const VimLine(mode: VimMode.normal),
                    ),
                  ),
                ),
              ),
            );
            expect(
              find.text(
                l10n.itemPosition(121, 100000, capped: capped),
              ),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
          }
        }
      },
    );
  });
}
