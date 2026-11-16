import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:component_library/component_library.dart';
import 'package:ferryx/app/context_guidance.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:settings_feature/settings_feature.dart';

final _captureKey = GlobalKey();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final (family, asset) in [
      ('Inter', 'packages/component_library/fonts/Inter-Variable.ttf'),
      ('Geist Mono', 'packages/component_library/fonts/GeistMono-Variable.ttf'),
      (
        '.AppleSystemUIFont',
        'packages/component_library/fonts/Inter-Variable.ttf',
      ),
      (
        '.AppleSystemUIFontMonospaced',
        'packages/component_library/fonts/GeistMono-Variable.ttf',
      ),
      (
        'packages/lucide_icons_flutter/Lucide',
        'packages/lucide_icons_flutter/assets/lucide.ttf',
      ),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(asset))).load();
    }
  });

  for (final brightness in Brightness.values) {
    for (final language in ['en', 'ru']) {
      testWidgets('$language ${brightness.name}: settings and popup guidance', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1180, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final prefs = await PreferencesService.create(
          storage: InMemoryPreferencesStorage(),
        );
        // Stream listeners are torn down in the widget test's fake clock.
        addTearDown(() => unawaited(prefs.dispose()));
        await prefs.update(
          (p) => p.copyWith(
            themeMode: brightness == Brightness.dark
                ? AppThemeMode.dark
                : AppThemeMode.light,
          ),
        );
        final l10n = lookupFerryxLocalizations(Locale(language));
        await tester.pumpWidget(
          _Host(
            brightness: brightness,
            language: language,
            child: SettingsScreen(
              preferencesService: prefs,
              platform: TargetPlatform.macOS,
              version: '0.1.0',
              onClose: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        final themeGroup = find.byType(AppSegmentedControl<AppThemeMode>);
        final ring = find
            .descendant(of: themeGroup, matching: find.byType(FocusRing))
            .first;
        Focus.of(tester.element(ring)).requestFocus();
        await tester.pumpAndSettle();
        final footer = find.byType(AppStatusBar);
        expect(
          find.descendant(of: footer, matching: find.text(l10n.hintChoose)),
          findsOneWidget,
        );
        final footerRect = tester.getRect(footer);
        await _capture(tester, 'settings-$language-${brightness.name}');

        final popup = find.byType(AppPopupButton<String?>);
        await tester.tap(popup);
        await tester.pumpAndSettle();
        final menu = find.byType(AppMenuList<int>);
        expect(menu, findsOneWidget);
        expect(
          find.descendant(of: menu, matching: find.byType(AppMenuFooter)),
          findsOneWidget,
        );
        expect(
          AppGuidanceScope.maybeOf(tester.element(menu))!.labels.choose,
          l10n.hintChoose,
        );
        await _capture(tester, 'menu-$language-${brightness.name}');
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(prefs.current.localeCode, 'en');
        expect(menu, findsNothing);
        Focus.of(tester.element(ring)).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(
          prefs.current.themeMode,
          brightness == Brightness.dark
              ? AppThemeMode.light
              : AppThemeMode.system,
        );
        expect(tester.getRect(footer), footerRect);
        expect(tester.takeException(), isNull);
      }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
    }
  }

  testWidgets(
    'scope visibility survives popup routes without disabling their keys',
    (tester) async {
      int? value;
      await tester.pumpWidget(
        _Host(
          enabled: false,
          child: Center(
            child: AppPopupButton<int>(
              value: 1,
              items: const [(1, 'One'), (2, 'Two')],
              onChanged: (next) => value = next,
            ),
          ),
        ),
      );
      await tester.tap(find.byType(AppPopupButton<int>));
      await tester.pumpAndSettle();
      expect(find.byType(AppMenuFooter), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(value, 2);
      expect(tester.takeException(), isNull);
    },
  );
}

/// Optional review artifacts contain actual widgets and bundled fonts.
Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['FERRYX_GUIDANCE_SHOTS'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final boundary =
        _captureKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$directory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

class _Host extends StatelessWidget {
  const _Host({
    required this.child,
    this.brightness = Brightness.light,
    this.language = 'en',
    this.enabled = true,
  });

  final Widget child;
  final Brightness brightness;
  final String language;
  final bool enabled;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.of(
      AppPlatformStyle.macos,
      brightness,
      generation: MacGeneration.tahoe,
    ),
    locale: Locale(language),
    supportedLocales: FerryxSupportedLocales.locales,
    localizationsDelegates: FerryxSupportedLocales.delegates,
    builder: (context, child) => RepaintBoundary(
      key: _captureKey,
      child: ContextGuidance(enabled: enabled, child: child!),
    ),
    home: Scaffold(body: child),
  );
}
