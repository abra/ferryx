import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app_command.dart';
import 'key_sequence.dart';

/// Intent carrying an [AppCommand]. One intent type for every command keeps
/// the `Shortcuts` map flat; handlers decide by [command].
class CommandIntent extends Intent {
  const CommandIntent(this.command, {this.yieldsToControls = false});

  final AppCommand command;

  /// Raised by plain Enter or Space, the keys a focused button, toggle or
  /// list row presses on: such a control keeps the key, and the command
  /// runs only from elsewhere (a text field, the screen itself).
  final bool yieldsToControls;

  /// Whether a chord of [key], [plain] when it has no modifier and no
  /// prefix, is one a focused control presses on ([yieldsToControls]).
  static bool isActivation(LogicalKeyboardKey key, {required bool plain}) =>
      plain &&
      (key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter ||
          key == LogicalKeyboardKey.space);
}

/// Registers handlers for a subset of commands below this point in the tree.
///
/// Dispatch walks from the focused widget outward: the innermost scope that
/// handles a command wins, everything else keeps bubbling to outer scopes.
/// Flutter's `Actions` stops at the first action of the matching type even
/// when it is disabled, which is why the chain is kept explicitly here.
class CommandHandlers extends StatelessWidget {
  const CommandHandlers({
    required this.handlers,
    required this.child,
    this.onInvoked,
    super.key,
  });

  final Map<AppCommand, VoidCallback> handlers;
  final Widget child;

  /// Completes transient input state after a command runs here or in a
  /// parent scope. Scopes outside the handler's owner are not notified.
  final ValueChanged<AppCommand>? onInvoked;

  @override
  Widget build(BuildContext context) => _CommandScope(
    handlers: handlers,
    parent: context.getInheritedWidgetOfExactType<_CommandScope>(),
    onInvoked: onInvoked,
    child: child,
  );
}

class _CommandScope extends InheritedWidget {
  const _CommandScope({
    required this.handlers,
    required this.parent,
    required this.onInvoked,
    required super.child,
  });

  final Map<AppCommand, VoidCallback> handlers;
  final _CommandScope? parent;
  final ValueChanged<AppCommand>? onInvoked;

  VoidCallback? _find(AppCommand command) {
    for (_CommandScope? scope = this; scope != null; scope = scope.parent) {
      final handler = scope.handlers[command];
      if (handler != null) return handler;
    }
    return null;
  }

  @override
  bool updateShouldNotify(_CommandScope oldWidget) => false;
}

/// Every command some scope above [context] handles: what a key press
/// there could run. The command palette offers these and no others.
Set<AppCommand> commandsAt(BuildContext context) => {
  for (
    _CommandScope? scope = context
        .getInheritedWidgetOfExactType<_CommandScope>();
    scope != null;
    scope = scope.parent
  )
    ...scope.handlers.keys,
};

/// Whether some scope above [context] handles [command].
bool canInvokeCommand(BuildContext context, AppCommand command) =>
    context.getInheritedWidgetOfExactType<_CommandScope>()?._find(command) !=
    null;

/// Runs [command] through the nearest scope that handles it.
///
/// Returns `true` when someone handled it; menus and the palette use this.
bool invokeCommand(BuildContext context, AppCommand command) {
  final start = context.getInheritedWidgetOfExactType<_CommandScope>();
  for (var owner = start; owner != null; owner = owner.parent) {
    final handler = owner.handlers[command];
    if (handler == null) continue;
    try {
      handler();
    } finally {
      for (var scope = start; scope != null; scope = scope.parent) {
        scope.onInvoked?.call(command);
        if (identical(scope, owner)) break;
      }
    }
    return true;
  }
  return false;
}

/// Root action that routes [CommandIntent]s raised by `Shortcuts` to the
/// handler chain of the focused widget. Install once, at the app root:
///
/// ```dart
/// Actions(actions: {CommandIntent: CommandDispatcherAction()}, child: ...)
/// ```
///
/// Unhandled chords stay unhandled so the key event continues to the focused
/// text field.
class CommandDispatcherAction extends ContextAction<CommandIntent> {
  @override
  bool isEnabled(CommandIntent intent, [BuildContext? context]) {
    final target = context ?? primaryFocus?.context;
    if (target == null) return false;
    // Disabled, the shortcut lets the key go on to the app's own
    // Enter/Space → ActivateIntent, which presses the focused control.
    if (intent.yieldsToControls && _pressesOnActivation(target)) return false;
    return canInvokeCommand(target, intent.command);
  }

  /// Whether the focused widget at [focused] is a control that Enter and
  /// Space press: it answers [ActivateIntent] (buttons, toggles, rows built
  /// on `InkWell` or `FocusableActionDetector`). A text field is not one,
  /// even inside such a row: there the keys are text.
  static bool _pressesOnActivation(BuildContext focused) {
    if (focused.findAncestorStateOfType<EditableTextState>() != null) {
      return false;
    }
    final action = Actions.maybeFind<ActivateIntent>(focused);
    return action != null && action.isEnabled(const ActivateIntent());
  }

  /// Tests see each command the keys reach; returning `true` keeps it from
  /// running, so a test can press every chord from one place in a row.
  @visibleForTesting
  static bool Function(AppCommand command)? debugReached;

  @override
  Object? invoke(CommandIntent intent, [BuildContext? context]) {
    // Any command ends a pending `d`/`g` prefix.
    KeySequenceState.clear();
    if (debugReached?.call(intent.command) ?? false) return true;
    final target = context ?? primaryFocus?.context;
    if (target == null) return false;
    return invokeCommand(target, intent.command);
  }
}

/// `Shortcuts` + root dispatcher in one widget, for app roots and for
/// screens that own a scope of single-key chords (review, block mode).
class CommandShortcuts extends StatelessWidget {
  const CommandShortcuts({
    required this.shortcuts,
    required this.child,
    super.key,
  });

  final Map<ShortcutActivator, Intent> shortcuts;
  final Widget child;

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: shortcuts,
    child: Actions(
      actions: {
        CommandIntent: CommandDispatcherAction(),
        KeyPrefixIntent: KeyPrefixAction(),
      },
      child: child,
    ),
  );
}
