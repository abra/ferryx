/// The keyboard model shared by every feature.
///
/// Every user action is an [AppCommand]. Features handle commands with
/// [CommandHandlers] placed in the widget tree; the app root installs a
/// `Shortcuts` map built from a [ShortcutMap]. Because commands are data,
/// the command palette, the cheat sheet and the settings page all read the
/// same table.
library;

export 'src/app_command.dart';
export 'src/chord.dart';
export 'src/chord_codec.dart';
export 'src/command_action.dart';
export 'src/command_section.dart';
export 'src/key_sequence.dart';
export 'src/shortcut_map.dart';
