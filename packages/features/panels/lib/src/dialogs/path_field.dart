import 'package:component_library/component_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A labelled path field whose Tab completes the folder being typed, as
/// Finder's Go to Folder does: each Tab takes the next completion; when
/// there is none, Tab moves on to the next control as usual.
class PathField extends StatefulWidget {
  const PathField({
    required this.label,
    required this.controller,
    required this.complete,
    this.hint,
    this.autofocus = false,
    this.onSubmitted,
    super.key,
  });

  final String label;
  final TextEditingController controller;

  /// The whole texts the field's text completes to (folders end in `/`).
  final Future<List<String>> Function(String text) complete;

  /// Said under the field, in the secondary colour.
  final String? hint;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  @override
  State<PathField> createState() => _PathFieldState();
}

class _PathFieldState extends State<PathField> {
  final _focus = FocusNode(debugLabel: 'path field');
  List<String>? _completions;
  int _completionAt = -1;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onEdit);
    _focus.onKeyEvent = _onKey;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onEdit);
    _focus.dispose();
    super.dispose();
  }

  void _onEdit() {
    // Typing drops the completions; Tab builds them anew.
    final options = _completions;
    if (options != null &&
        _completionAt >= 0 &&
        widget.controller.text != options[_completionAt]) {
      _completions = null;
      _completionAt = -1;
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey != LogicalKeyboardKey.tab ||
        HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    _complete();
    return KeyEventResult.handled;
  }

  Future<void> _complete() async {
    var options = _completions;
    if (options == null) {
      options = await widget.complete(widget.controller.text);
      if (!mounted) return;
      if (options.isEmpty) {
        _focus.nextFocus();
        return;
      }
      _completions = options;
      _completionAt = -1;
    }
    _completionAt = (_completionAt + 1) % options.length;
    final text = options[_completionAt];
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  Widget build(BuildContext context) => AppFormField(
    label: widget.label,
    helpText: widget.hint,
    child: AppTextField(
      selectAllOnFocus: false,
      controller: widget.controller,
      focusNode: _focus,
      autofocus: widget.autofocus,
      monospace: true,
      onSubmitted: widget.onSubmitted,
    ),
  );
}
