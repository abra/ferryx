import 'dart:async';

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
    this.onFocusLost,
    super.key,
  });

  final ShortcutMap shortcutMap;

  /// Lines run before, the latest last.
  final List<String> history;
  final ValueChanged<String> onRun;
  final VoidCallback onCancel;
  final VoidCallback? onFocusLost;

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
  bool _loadingCompletions = false, _internalEdit = false;
  int _completionRevision = 0, _completionSteps = 0;
  String _lastText = '', _draft = '';

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
    if (!_focus.hasFocus && !_done) _cancel(focusLost: true);
  }

  void _onEdit() {
    final text = _controller.text;
    if (_lastText == text) return;
    _lastText = text;
    if (_internalEdit) return;
    _historyAt = null;
    _invalidateCompletions();
  }

  void _invalidateCompletions() {
    _completionRevision++;
    _completionSteps = 0;
    _completions = null;
    _completionAt = -1;
  }

  void _run() {
    if (_done) return;
    final line = _controller.text.trim();
    _done = true;
    widget.onRun(line);
  }

  void _cancel({bool focusLost = false}) {
    if (_done) return;
    _done = true;
    (focusLost ? widget.onFocusLost ?? widget.onCancel : widget.onCancel)();
  }

  void _history(int step) {
    final history = widget.history;
    if (history.isEmpty) return;
    if (_historyAt == null) _draft = _controller.text;
    final at = ((_historyAt ?? history.length) + step).clamp(0, history.length);
    _historyAt = at == history.length ? null : at;
    _invalidateCompletions();
    _set(at == history.length ? _draft : history[at]);
  }

  void _complete(int step) {
    final options = _completions;
    if (options != null && options.isNotEmpty) {
      _completionAt = (_completionAt + step) % options.length;
      _set(options[_completionAt]);
      return;
    }
    _completionSteps += step;
    if (!_loadingCompletions) unawaited(_loadCompletions());
  }

  Future<void> _loadCompletions() async {
    final revision = _completionRevision;
    final query = _controller.text;
    _loadingCompletions = true;
    try {
      final options = await widget.complete(query);
      if (!mounted ||
          _done ||
          revision != _completionRevision ||
          options.isEmpty) {
        return;
      }
      final steps = _completionSteps;
      if (steps == 0) return;
      _completions = List.unmodifiable(options);
      _completionAt = (steps > 0 ? steps - 1 : steps) % options.length;
      _set(options[_completionAt]);
    } on Object {
      if (mounted && !_done && revision == _completionRevision) {
        showAppNotice(context, context.l10n.vimCompletionFailed);
      }
    } finally {
      _loadingCompletions = false;
      if (mounted &&
          !_done &&
          revision != _completionRevision &&
          _completionSteps != 0) {
        unawaited(_loadCompletions());
      } else if (revision == _completionRevision) {
        _completionSteps = 0;
      }
    }
  }

  void _set(String text) {
    _internalEdit = true;
    try {
      _controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    } finally {
      _internalEdit = false;
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isMetaPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed) {
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
      _complete(keyboard.isShiftPressed ? -1 : 1);
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
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: AppTextField(
                  selectAllOnFocus: false,
                  controller: _controller,
                  focusNode: _focus,
                  style: style,
                  appearance: AppTextFieldAppearance.embedded,
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
