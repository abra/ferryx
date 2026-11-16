import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:settings_feature/settings_feature.dart';
import 'package:shortcuts/shortcuts.dart';

import 'support.dart';

void main() {
  const closeChord = Chord(LogicalKeyboardKey.keyQ, primary: true, alt: true);
  late PreferencesService service;
  setUp(() async {
    service = await testPreferences();
    await service.update(
      (prefs) => prefs.copyWith(
        vimMode: true,
        shortcutOverrides: {
          AppCommand.dismiss.name: [ChordCodec.encode(closeChord)],
        },
      ),
    );
  });
  tearDown(() => service.dispose());

  List<AppKeyHint> hints(WidgetTester tester) => tester
      .widget<AppKeyHints>(
        find.descendant(
          of: find.byType(AppStatusBar),
          matching: find.byType(AppKeyHints),
        ),
      )
      .hints;

  for (final language in ['en', 'ru']) {
    testWidgets(
      '$language settings hints track search text, selection and clear/close keys',
      (tester) async {
        final locale = Locale(language);
        final l10n = lookupFerryxLocalizations(locale);
        var closed = 0;
        await pumpScreen(
          tester,
          SettingsScreen(
            preferencesService: service,
            platform: TargetPlatform.macOS,
            version: '0.1.0',
            onClose: () => closed++,
          ),
          locale: locale,
        );
        final search = find.byType(AppSearchField);
        await tester.enterText(search, l10n.settingsTerminal);
        await tester.pump();
        final native = MaterialLocalizations.of(tester.element(search));
        final escape = Chord.keyLabel(
          LogicalKeyboardKey.escape,
          TargetPlatform.macOS,
        );
        final close = closeChord.label(TargetPlatform.macOS);
        expect(
          hints(tester)
              .where((hint) => hint.keys.contains(escape))
              .single
              .label,
          l10n.actionClear,
        );
        expect(
          hints(tester).map((hint) => hint.label),
          contains(native.selectAllButtonLabel),
        );
        expect(
          hints(tester).map((hint) => hint.label),
          contains(native.pasteButtonLabel),
        );
        expect(
          hints(tester).map((hint) => hint.label),
          isNot(contains(native.copyButtonLabel)),
        );
        expect(
          hints(tester).expand((hint) => hint.keys),
          isNot(contains('yn')),
        );
        expect(
          hints(tester).expand((hint) => hint.keys),
          isNot(contains('yp')),
        );

        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pump();

        expect(
          hints(tester).map((hint) => hint.label),
          contains(native.copyButtonLabel),
        );
        expect(
          hints(tester).map((hint) => hint.label),
          contains(native.cutButtonLabel),
        );

        final searchEditor = tester.widget<EditableText>(
          find.descendant(of: search, matching: find.byType(EditableText)),
        );
        final navigationLabel = find.descendant(
          of: find.widgetWithText(AppNavItem, l10n.settingsTerminal),
          matching: find.text(l10n.settingsTerminal),
        );
        Focus.of(tester.element(navigationLabel)).requestFocus();
        await tester.pumpAndSettle();

        expect(searchEditor.focusNode.hasFocus, isFalse);
        expect(searchEditor.controller.text, l10n.settingsTerminal);
        expect(
          hints(tester).where((hint) => hint.keys.contains(close)).single.label,
          l10n.actionClose,
        );
        for (final label in [
          l10n.actionClear,
          native.copyButtonLabel,
          native.cutButtonLabel,
          native.pasteButtonLabel,
        ]) {
          expect(
            hints(tester).map((hint) => hint.label),
            isNot(contains(label)),
          );
        }

        searchEditor.focusNode.requestFocus();
        await tester.pumpAndSettle();
        expect(searchEditor.controller.text, l10n.settingsTerminal);
        expect(
          hints(tester)
              .where((hint) => hint.keys.contains(escape))
              .single
              .label,
          l10n.actionClear,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        final field = tester.widget<AppSearchField>(search);
        expect(field.controller!.text, isEmpty);
        expect(closed, 0);
        expect(
          hints(tester).where((hint) => hint.keys.contains(close)).single.label,
          l10n.actionClose,
        );
        expect(
          hints(tester).map((hint) => hint.label),
          isNot(contains(l10n.actionClear)),
        );
        expect(
          hints(tester).map((hint) => hint.label),
          isNot(contains(native.copyButtonLabel)),
        );
        expect(
          hints(tester).map((hint) => hint.label),
          contains(native.pasteButtonLabel),
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pump();
        expect(closed, 1);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  for (final (language, dark, size, scale) in [
    ('en', false, const Size(1280, 800), 1.0),
    ('ru', true, const Size(920, 650), 1.3),
  ]) {
    testWidgets(
      '$language settings controls show and execute their focused keys',
      (tester) async {
        tester.view
          ..physicalSize = size
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final l10n = lookupFerryxLocalizations(Locale(language));
        await tester.pumpWidget(
          MaterialApp(
            theme: dark
                ? AppTheme.dark(AppPlatformStyle.macos)
                : AppTheme.light(AppPlatformStyle.macos),
            locale: Locale(language),
            localizationsDelegates: FerryxSupportedLocales.delegates,
            supportedLocales: FerryxSupportedLocales.locales,
            builder: (context, child) => AppGuidanceScope(
              labels: AppGuidanceLabels(
                navigate: l10n.hintNavigate,
                choose: l10n.hintChoose,
                dismiss: l10n.actionClose,
                clear: l10n.actionClear,
                nextControl: l10n.hintNextControl,
                previousControl: l10n.hintPreviousControl,
                toggle: l10n.hintToggle,
                adjust: l10n.hintAdjust,
                activate: l10n.hintActivate,
              ),
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                ),
                child: child!,
              ),
            ),
            home: Scaffold(
              body: SettingsScreen(
                preferencesService: service,
                platform: TargetPlatform.macOS,
                version: '0.1.0',
                onClose: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        Future<void> focus(Finder control, Finder child) async {
          await tester.ensureVisible(control);
          await tester.pumpAndSettle();
          Focus.of(
            tester.element(find.descendant(of: control, matching: child).first),
          ).requestFocus();
          await tester.pumpAndSettle();
        }

        Future<void> press(LogicalKeyboardKey key) async {
          await tester.runAsync(() => tester.sendKeyEvent(key));
          await tester.pumpAndSettle();
        }

        final segmented = find.byWidgetPredicate(
          (widget) => widget is AppSegmentedControl<AppThemeMode>,
        );
        await focus(segmented, find.byType(FocusRing));
        expect(hints(tester).first.label, l10n.hintChoose);
        expect(hints(tester).first.keys, ['←', '→']);
        await press(LogicalKeyboardKey.arrowRight);
        expect(service.current.themeMode, AppThemeMode.light);

        final popup = find.byWidgetPredicate(
          (widget) => widget is AppPopupButton<String?>,
        );
        await focus(popup, find.byType(Text));
        expect(hints(tester).first.label, l10n.hintChoose);
        expect(hints(tester).first.keys, ['Space']);
        final footer = find.descendant(
          of: find.byType(SettingsScreen),
          matching: find.byType(AppStatusBar),
        );
        final beforeMenu = tester.getRect(footer);
        await press(LogicalKeyboardKey.space);
        expect(tester.getRect(footer), beforeMenu);
        expect(
          find.descendant(of: footer, matching: find.byType(AppKeyHints)),
          findsNothing,
        );
        await press(LogicalKeyboardKey.arrowDown);
        await press(LogicalKeyboardKey.enter);
        expect(service.current.localeCode, 'en');

        final slider = find.byType(Slider).first;
        await tester.ensureVisible(slider);
        await tester.pumpAndSettle();
        tester.widget<Slider>(slider).focusNode!.requestFocus();
        await tester.pumpAndSettle();
        expect(hints(tester).first.label, l10n.hintAdjust);
        expect(hints(tester).first.keys, ['←', '→']);
        await press(LogicalKeyboardKey.arrowRight);
        expect(service.current.textScale, 1.1);

        final toggle = find.descendant(
          of: find.ancestor(
            of: find.text(l10n.confirmTrashLabel),
            matching: find.byType(AppControlRow),
          ),
          matching: find.byType(AppToggle),
        );
        await focus(toggle, find.byType(FocusRing));
        expect(hints(tester).first.label, l10n.hintToggle);
        expect(hints(tester).first.keys, ['Space']);
        final beforeToggle = service.current.confirmTrash;
        await press(LogicalKeyboardKey.space);
        expect(service.current.confirmTrash, !beforeToggle);
        expect(
          hints(tester).map((hint) => hint.label),
          contains(l10n.hintNextControl),
        );
        expect(
          find.descendant(
            of: find.byType(AppStatusBar),
            matching: find.text(l10n.hintToggle),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }
}
