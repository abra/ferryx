import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shortcuts/shortcuts.dart';

/// Around a text field inside the panels: the panel's single keys (`j`,
/// Space, Backspace, Tab, `/`…) are text there, not commands. The field
/// keeps its own editing keys (`DefaultTextEditingShortcuts`, innermost),
/// and every other plain key of the panel scope stops here instead of
/// reaching the panel's shortcuts; Return and Esc are left to the field's
/// own handler.
class PanelTextGuard extends StatelessWidget {
  const PanelTextGuard({
    required this.shortcutMap,
    required this.child,
    super.key,
  });

  final ShortcutMap shortcutMap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final guarded = <ShortcutActivator, Intent>{};
    for (final entry in shortcutMap.bindings.entries) {
      if (entry.key.scope != CommandScope.panel) continue;
      for (final chord in entry.value) {
        if (chord.primary || chord.control || chord.alt) continue;
        if (chord.key == LogicalKeyboardKey.enter ||
            chord.key == LogicalKeyboardKey.numpadEnter ||
            chord.key == LogicalKeyboardKey.escape) {
          continue;
        }
        final key = chord.prefix ?? chord.key;
        final activator = Chord(
          key,
          shift: chord.shift && chord.prefix == null,
        ).toShortcutActivator(platform);
        guarded[activator] = const DoNothingAndStopPropagationTextIntent();
        if (chord.prefix != null) {
          guarded[chord.toShortcutActivator(platform)] =
              const DoNothingAndStopPropagationTextIntent();
        }
      }
    }
    return Shortcuts(
      shortcuts: guarded,
      child: DefaultTextEditingShortcuts(child: child),
    );
  }
}
