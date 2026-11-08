// The terminal feature behind the panels' terminal contract.
//
// The panels feature never imports the terminal feature: the workspace is
// handed a `WorkspaceTerminal` whose controller is this link and whose
// builder (routing.dart) shows its `TerminalPane`.

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:panels_feature/panels_feature.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:terminal_feature/terminal_feature.dart';
import 'package:terminal_service/terminal_service.dart';

/// The window's terminal session as the workspace drives it.
class TerminalLink implements WorkspaceTerminalController {
  TerminalLink({
    required TerminalService service,
    required PreferencesService preferences,
    required TargetPlatform platform,
  }) : _preferences = preferences,
       cubit = TerminalSessionCubit(
         service: service,
         preferences: preferences,
         platform: platform,
         // The system's language and region, for the shell's LANG.
         locale: PlatformDispatcher.instance.locale.toLanguageTag(),
       );

  final PreferencesService _preferences;
  final TerminalSessionCubit cubit;

  /// The link behind [controller]: the workspace hands back what it was
  /// given.
  static TerminalLink of(WorkspaceTerminalController controller) =>
      controller as TerminalLink;

  @override
  void show(String? folder) => cubit.show(folder);

  @override
  void hide() => cubit.hide();

  @override
  void followFolder(String? folder) => cubit.followFolder(folder);

  @override
  Stream<String> get shellFolders => cubit.shellFolders;

  @override
  bool run(String command) => cubit.runCommand(command);

  @override
  double lineHeight(BuildContext context) => TerminalPane.lineHeightOf(
    context,
    _preferences.current.terminal.fontSize,
    fontFamily: _preferences.current.terminal.fontFamily,
  );

  @override
  double chromeHeight(BuildContext context) =>
      TerminalPane.chromeHeightOf(context);

  @override
  Future<void> dispose() => cubit.close();
}
