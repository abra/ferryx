import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:ferryx/app/dependency_scope.dart';
import 'package:ferryx/app/routing.dart';
import 'package:ferryx/app/window_chrome.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:palette_feature/palette_feature.dart';
import 'package:platform_services/platform_services.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:shortcuts/shortcuts.dart';

/// `MaterialApp.router` with theme, locale and the global shortcut table.
///
/// Stateful so the router is created once and survives theme/locale changes.
class FerryxApp extends StatefulWidget {
  const FerryxApp({super.key});

  @override
  State<FerryxApp> createState() => _FerryxAppState();
}

class _FerryxAppState extends State<FerryxApp> {
  late final GoRouter _router;
  final _title = WindowTitle();

  /// Focus rings while the keyboard is in use only, as on every desktop.
  final _focusHighlight = FocusHighlightTracker.attach();

  @override
  void initState() {
    super.initState();
    _router = buildRouter(
      deps: DependenciesScope.of(context),
      windowTitle: _title,
    );
  }

  @override
  void dispose() {
    _router.dispose();
    _title.dispose();
    _focusHighlight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deps = DependenciesScope.of(context);
    final preferences = PreferencesScope.of(context);
    final themeMode = PreferencesScope.themeModeOf(context);
    final locale = PreferencesScope.localeOf(context);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      scrollBehavior: const AppScrollBehavior(),
      onGenerateTitle: (context) => context.l10n.appTitle,
      locale: locale,
      supportedLocales: FerryxSupportedLocales.locales,
      localizationsDelegates: FerryxSupportedLocales.delegates,
      themeMode: themeMode,
      // The platform's own conventions: macOS HIG (of the running macOS's
      // generation), Fluent, GNOME HIG.
      theme: AppTheme.of(
        AppPlatformStyle.current,
        Brightness.light,
        generation: MacGeneration.current,
      ),
      darkTheme: AppTheme.of(
        AppPlatformStyle.current,
        Brightness.dark,
        generation: MacGeneration.current,
      ),
      routerConfig: _router,
      builder: (context, child) {
        final platform = Theme.of(context).platform;
        // Global chords only: the panels' single keys are installed around
        // the panels, so typing in a dialog never triggers them.
        final app = CommandShortcuts(
          shortcuts: deps.shortcutMap.toShortcuts(
            platform,
            scopes: const {CommandScope.global},
          ),
          // Hint mode (⌘J) over every route: the window, its dialogs and
          // the settings.
          child: HintModeHost(
            message: context.l10n.hintModeHint,
            child: Builder(
              builder: (context) => CommandHandlers(
                handlers: {
                  AppCommand.hintMode: () =>
                      HintModeHost.maybeOf(context)?.toggle(),
                  // Over every route: the palette lists what can run where
                  // the focus is (a panel, the viewer, a dialog).
                  AppCommand.commandPalette: () {
                    final focused = FocusManager.instance.primaryFocus?.context;
                    if (focused == null) return;
                    unawaited(
                      showCommandPalette(
                        focused,
                        shortcutMap: deps.shortcutMap,
                        vim: deps.preferencesService.current.vimMode,
                        recents: deps.recentCommands,
                      ),
                    );
                  },
                },
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.6,
                  child: _TextScale(
                    scale: preferences.textScale,
                    child: WindowChrome(
                      title: _title,
                      frame: deps.windowFrame,
                      child: child!,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        // A click beside a text field keeps its caret, on every route; the
        // selections grey while the window is not the active one; files
        // dragged over the window reach the drop target under the pointer;
        // a macOS alert shows the app's icon.
        return PlatformDropArea(
          enabled: deps.platformServices.capabilities.fileDrags,
          child: AppWindowActivity(
            child: AppIdentity(
              icon: const AssetImage(_appIcon),
              child: TapOutsideKeepsFocus(child: app),
            ),
          ),
        );
      },
    );
  }
}

/// The macOS icon, rendered by `make icons` (brand/build_icons.py).
const _appIcon = 'brand/ferryx-256.png';

/// Applies the user's text scale on top of the system scale.
class _TextScale extends StatelessWidget {
  const _TextScale({required this.scale, required this.child});

  final double scale;
  final Widget child;

  // Always this MediaQuery, even at 100 %: wrapping the router only when
  // the scale moves off 1 reparents the whole app under it.
  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: scale == 1.0
          ? media
          : media.copyWith(
              textScaler: TextScaler.linear(media.textScaler.scale(scale)),
            ),
      child: child,
    );
  }
}
