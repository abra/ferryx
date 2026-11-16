import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shortcuts/shortcuts.dart';
import 'package:viewer_feature/src/viewer_footer.dart';
import 'package:viewer_feature/src/viewer_search_hints.dart';

void main() {
  Finder cap(String key) => find.byWidgetPredicate(
    (widget) => widget is AppKeyCap && widget.label == key,
  );
  for (final language in ['en', 'ru']) {
    testWidgets('$language search hints respect custom and unbound keys', (
      tester,
    ) async {
      final locale = Locale(language);
      final l10n = lookupFerryxLocalizations(locale);
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final map = ShortcutMap.defaults(TargetPlatform.macOS)
          .rebind(AppCommand.confirm, [
            Chord(LogicalKeyboardKey.enter, control: true),
          ])
          .rebind(AppCommand.viewerFindNext, [
            Chord(LogicalKeyboardKey.keyN, primary: true),
          ])
          .rebind(AppCommand.viewerFindPrevious, [])
          .rebind(AppCommand.dismiss, []);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppPlatformStyle.macos),
          locale: locale,
          localizationsDelegates: FerryxSupportedLocales.delegates,
          supportedLocales: FerryxSupportedLocales.locales,
          home: Scaffold(
            body: Focus(
              focusNode: focus,
              autofocus: true,
              child: Align(
                alignment: Alignment.topLeft,
                child: ViewerSearchHints(
                  chord: (command) =>
                      map.labelOf(command, TargetPlatform.macOS),
                  focusNode: focus,
                  hasQuery: true,
                  hasMatches: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(cap('⌃↩'), findsOneWidget);
      expect(cap('⌘N'), findsOneWidget);
      expect(cap('⌘G'), findsNothing);
      expect(find.text(l10n.cmdViewerFindPrevious), findsNothing);
      expect(find.text(l10n.actionClear), findsOneWidget);
      final escape = Chord.keyLabel(
        LogicalKeyboardKey.escape,
        TargetPlatform.macOS,
      );
      expect(cap(escape), findsOneWidget);

      focus.unfocus();
      await tester.pumpAndSettle();
      expect(cap('⌃↩'), findsNothing);
      expect(cap(escape), findsNothing);
      expect(cap('⌘N'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [320.0, 1600.0]) {
    testWidgets('footer keeps its shared height and exit priority at $width', (
      tester,
    ) async {
      tester.view
        ..physicalSize = Size(width, 600)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final l10n = lookupFerryxLocalizations(const Locale('en'));
      final map = ShortcutMap.defaults(TargetPlatform.macOS);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppPlatformStyle.macos),
          localizationsDelegates: FerryxSupportedLocales.delegates,
          supportedLocales: FerryxSupportedLocales.locales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ViewerFooter(
                status: '1 MiB / 24 MiB',
                shortcutMap: map,
                showFiles: true,
                hints: [
                  AppKeyHint(['⌘L'], l10n.cmdViewerGoTo),
                ],
              ),
            ),
          ),
        ),
      );
      final footer = find.byType(ViewerFooter);
      final context = tester.element(footer);
      expect(tester.getSize(footer).height, AppStatusBar.heightOf(context));
      expect(
        find.text(
          l10n.viewerCloseHint(
            map.labelOf(AppCommand.dismiss, TargetPlatform.macOS)!,
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          l10n.viewerFilesHint(
            map.labelOf(AppCommand.switchPanel, TargetPlatform.macOS)!,
          ),
        ),
        findsOneWidget,
      );
      expect(cap('⌘L'), width > 320 ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
