import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shortcuts/shortcuts.dart';

import 'panel_text_guard.dart';

/// Vim's `:` line, in the panel's footer: Return runs the line, Esc leaves,
/// ↑ and ↓ walk the lines run before, Tab completes a path.
class VimCommandLine extends StatefulWidget {
  const VimCommandLine({
    required this.shortcutMap,
    required this.history,
    required this.onRun,
    required this.onCancel,
    required this.complete,
    super.key,
  });

  final ShortcutMap shortcutMap;

  /// Lines run before, the latest last.
  final List<String> history;
  final ValueChanged<String> onRun;
  final VoidCallback onCancel;

  /// The completions of the line so far (whole lines), for Tab.
  final Future<List<String>> Function(String line) complete;

  @override
  State<VimCommandLine> createState() => _VimCommandLineState();
}

class _VimCommandLineState extends State<VimCommandLine> {
  final _controller = TextEditingController();
  final _focus = FocusNode(debugLabel: 'vim command line');
  int? _historyAt;
  List<String>? _completions;
  int _completionAt = -1;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
    _controller.addListener(_onEdit);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _onFocus() {
    if (!_focus.hasFocus && !_done) _cancel();
  }

  void _onEdit() {
    // Typing drops the completions; Tab builds them anew.
    if (_completions != null && _completionAt >= 0) {
      final current = _completions![_completionAt];
      if (_controller.text != current) {
        _completions = null;
        _completionAt = -1;
      }
    }
  }

  void _run() {
    if (_done) return;
    final line = _controller.text.trim();
    _done = true;
    widget.onRun(line);
  }

  void _cancel() {
    if (_done) return;
    _done = true;
    widget.onCancel();
  }

  void _history(int step) {
    final history = widget.history;
    if (history.isEmpty) return;
    final at = ((_historyAt ?? history.length) + step).clamp(0, history.length);
    _historyAt = at;
    _set(at == history.length ? '' : history[at]);
  }

  Future<void> _complete() async {
    var options = _completions;
    if (options == null) {
      options = await widget.complete(_controller.text);
      if (!mounted || options.isEmpty) return;
      _completions = options;
      _completionAt = -1;
    }
    _completionAt = (_completionAt + 1) % options.length;
    _set(options[_completionAt]);
  }

  void _set(String text) {
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _cancel();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _run();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _history(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _history(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab) {
      _complete();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _controller.removeListener(_onEdit);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final style = context.mono.copyWith(
      fontSize: context.text.bodySmall?.fontSize,
    );
    return PanelTextGuard(
      shortcutMap: widget.shortcutMap,
      child: Focus(
        onKeyEvent: _onKey,
        child: Row(
          children: [
            Text(':', style: style.copyWith(color: colors.textMuted)),
            Expanded(
              child: TextField(
                selectAllOnFocus: false,
                controller: _controller,
                focusNode: _focus,
                style: style,
                decoration: InputDecoration(
                  isDense: true,
                  isCollapsed: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                  ),
                  hintText: context.l10n.vimCommandHint,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
