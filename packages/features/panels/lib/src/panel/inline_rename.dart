import 'package:component_library/component_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shortcuts/shortcuts.dart';

import 'panel_state.dart';
import 'panel_text_guard.dart';

/// The field that replaces a row's name while it is renamed in place: the
/// stem selected (or the caret at an end, as Vim's `I` and `A` ask),
/// Return commits, Esc leaves. The panel's single keys are text here.
class InlineRename extends StatefulWidget {
  const InlineRename({
    required this.name,
    required this.shortcutMap,
    required this.onCommit,
    required this.onCancel,
    this.caret = RenameCaret.stem,
    super.key,
  });

  final String name;
  final ShortcutMap shortcutMap;
  final ValueChanged<String> onCommit;
  final VoidCallback onCancel;
  final RenameCaret caret;

  @override
  State<InlineRename> createState() => _InlineRenameState();
}

class _InlineRenameState extends State<InlineRename> {
  late final TextEditingController _controller;
  final _focus = FocusNode(debugLabel: 'inline rename');
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.name);
    final dot = widget.name.lastIndexOf('.');
    final stemEnd = dot > 0 ? dot : widget.name.length;
    _controller.selection = switch (widget.caret) {
      RenameCaret.stem => TextSelection(baseOffset: 0, extentOffset: stemEnd),
      RenameCaret.start => const TextSelection.collapsed(offset: 0),
      RenameCaret.end => TextSelection.collapsed(offset: widget.name.length),
    };
    _focus.addListener(_onFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _onFocus() {
    // Clicking elsewhere keeps what was typed, as Finder does.
    if (!_focus.hasFocus && !_done) _commit();
  }

  void _commit() {
    if (_done) return;
    _done = true;
    widget.onCommit(_controller.text);
  }

  void _cancel() {
    if (_done) return;
    _done = true;
    widget.onCancel();
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PanelTextGuard(
    shortcutMap: widget.shortcutMap,
    child: Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          _cancel();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) {
          _commit();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TextField(
        selectAllOnFocus: false,
        controller: _controller,
        focusNode: _focus,
        style: context.text.bodyMedium,
        // Opaque over the row, whatever fill the row had.
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: context.colors.surface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xxs,
          ),
        ),
        onEditingComplete: () {},
        onSubmitted: (_) => _commit(),
      ),
    ),
  );
}
