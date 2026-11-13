import 'package:material_ui/material_ui.dart';

/// Leaves the keyboard focus where it is when a click lands outside the
/// focused text field, as macOS, Windows and GNOME do: the focus moves only
/// to what takes it (another field, a list row, the PDF page), and a click
/// on a bar button, a label or blank space keeps the caret in its field.
/// The field's context menu still closes, as any menu does on a click
/// outside it.
///
/// Flutter's desktop default drops the field's focus onto the route's
/// scope instead. No command handler sits that high, so every window chord
/// went dead until the next click into a field, and a pop-up opened from a
/// bar button had nothing to give the focus back to. One above the app's
/// navigator covers every route.
class TapOutsideKeepsFocus extends StatelessWidget {
  const TapOutsideKeepsFocus({required this.child, super.key});

  final Widget child;

  // One map for the app's lifetime: a new one per build would notify every
  // dependent of the Actions scope.
  static final _actions = <Type, Action<Intent>>{
    EditableTextTapOutsideIntent: _KeepFocusAction(),
  };

  @override
  Widget build(BuildContext context) =>
      Actions(actions: _actions, child: child);
}

class _KeepFocusAction extends Action<EditableTextTapOutsideIntent> {
  @override
  void invoke(EditableTextTapOutsideIntent intent) =>
      ContextMenuController.removeAny();
}
