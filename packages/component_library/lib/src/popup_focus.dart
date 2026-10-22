import 'package:flutter/widgets.dart';

/// Pushes [route] on the root navigator and, once it closes, gives the
/// focus back to what held it when it opened, as native menus and popovers
/// do, a text field with its selection as it was. The navigator's own guess
/// goes by its scope's history, which can land elsewhere in the window.
/// Whatever the caller does with the result runs after this, so a picked
/// item may still move the focus on.
Future<T?> pushReturningFocus<T>(BuildContext context, Route<T> route) {
  final opener = FocusManager.instance.primaryFocus;
  final value = fieldValueOf(opener);
  return Navigator.of(context, rootNavigator: true).push(route).whenComplete(
    () {
      if (opener != null &&
          opener.context?.mounted == true &&
          opener.canRequestFocus) {
        focusWithSelection(opener, value?.selection, text: value?.text);
      }
    },
  );
}

/// The text and selection of the field [node] focuses, if it focuses one.
TextEditingValue? fieldValueOf(FocusNode? node) => _controllerOf(node)?.value;

/// Gives [node] the focus and its text field [selection]. A single-line
/// field selects all of itself as it gains the focus on the desktops, as a
/// native one does when tabbed into; a pop-up closing, or a command that
/// puts the caret somewhere, must not have that. With [text], the
/// selection is one read while the field held that text: what the pop-up
/// did to the text since (a colour, an edit) placed the caret itself, so
/// it is left as it is.
void focusWithSelection(
  FocusNode node,
  TextSelection? selection, {
  String? text,
}) {
  node.requestFocus();
  final controller = _controllerOf(node);
  if (selection == null || controller == null) return;
  if (text != null && controller.text != text) return;
  // The field takes the focus in a microtask and selects then; the
  // selection goes back after the frame that follows.
  WidgetsBinding.instance
    ..addPostFrameCallback((_) {
      if (node.hasFocus &&
          (text == null || controller.text == text) &&
          selection.end <= controller.text.length) {
        controller.selection = selection;
      }
    })
    ..scheduleFrame();
}

TextEditingController? _controllerOf(FocusNode? node) =>
    node?.context?.findAncestorWidgetOfExactType<EditableText>()?.controller;
