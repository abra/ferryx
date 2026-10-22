import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Letters used for hint labels, home row first so the likeliest targets
/// get the easiest keys. Labels map to physical keys, so they work in any
/// keyboard layout.
const String hintAlphabet = 'asdfghjklqwertyuiopzxcvbnm';

/// Labels for [count] targets: single letters while they suffice, otherwise
/// two letters each so every label has the same length.
List<String> hintLabels(int count) {
  final letters = hintAlphabet.split('');
  if (count <= letters.length) return letters.take(count).toList();
  final labels = <String>[];
  for (final first in letters) {
    for (final second in letters) {
      if (labels.length == count) return labels;
      labels.add('$first$second');
    }
  }
  return labels;
}

/// A clickable widget registered for hint mode.
class HintEntry {
  HintEntry({
    required this.context,
    required this.onActivate,
    this.onActivateAlt,
  });

  final BuildContext context;
  final VoidCallback onActivate;

  /// Shift+label: usually "open in the right pane".
  final VoidCallback? onActivateAlt;
}

/// A hint ready to draw: where it is and what it does.
@immutable
class HintAnchor {
  const HintAnchor({
    required this.rect,
    required this.onActivate,
    this.onActivateAlt,
  });

  /// Global coordinates until [HintRegistry.collect] converts them.
  final Rect rect;
  final VoidCallback onActivate;
  final VoidCallback? onActivateAlt;

  HintAnchor shifted(Offset delta) => HintAnchor(
    rect: rect.shift(delta),
    onActivate: onActivate,
    onActivateAlt: onActivateAlt,
  );
}

/// Supplies hints that have no widget of their own (links inside text).
typedef HintAnchorProvider = List<HintAnchor> Function();

/// Where hintable widgets register; one per window, see [HintScope].
///
/// Besides them, hint mode labels every control on screen that the
/// keyboard presses (a focusable widget answering [ActivateIntent]: push
/// buttons, toggles, check boxes, rows), so a dialog, the settings or the
/// review screen need no registration of their own. Only the topmost
/// route's targets are labelled: a dialog's, not the window's under it.
class HintRegistry {
  final _entries = <HintEntry>{};
  final _providers = <HintAnchorProvider>{};

  /// Where the focus was when hint mode opened, for a target that takes the
  /// focus on purpose (a panel edge) and gives it back later.
  FocusNode? focusBefore;

  void register(HintEntry entry) => _entries.add(entry);

  void unregister(HintEntry entry) => _entries.remove(entry);

  void addProvider(HintAnchorProvider provider) => _providers.add(provider);

  void removeProvider(HintAnchorProvider provider) =>
      _providers.remove(provider);

  /// Visible targets in reading order, with rects in [overlay]'s
  /// coordinates.
  List<HintAnchor> collect(RenderBox overlay) {
    final bounds = overlay.localToGlobal(Offset.zero) & overlay.size;
    final anchors = <HintAnchor>[];
    for (final entry in _entries) {
      if (!entry.context.mounted || !_onTopRoute(entry.context)) continue;
      final object = entry.context.findRenderObject();
      if (object is! RenderBox || !object.attached || !object.hasSize) {
        continue;
      }
      final rect = visibleGlobalRect(object);
      if (rect == null) continue;
      anchors.add(
        HintAnchor(
          rect: rect,
          onActivate: entry.onActivate,
          onActivateAlt: entry.onActivateAlt,
        ),
      );
    }
    for (final provider in _providers) {
      anchors.addAll(provider());
    }
    anchors.addAll(_controls(anchors));
    final origin = -bounds.topLeft;
    return anchors
        .where((a) => a.rect.overlaps(bounds))
        .map((a) => a.shifted(origin))
        .toList()
      ..sort(_readingOrder);
  }

  /// Pressable controls nobody registered, from the focus tree: those a
  /// registered target covers already ([labelled]) are left out.
  static List<HintAnchor> _controls(List<HintAnchor> labelled) {
    final found = <HintAnchor>[];
    for (final node in FocusManager.instance.rootScope.descendants) {
      final context = node.context;
      if (context == null ||
          !context.mounted ||
          !node.canRequestFocus ||
          !_onTopRoute(context) ||
          // A text field is reached by Tab or its own key; its row may
          // answer the activation keys, the field does not.
          context.findAncestorStateOfType<EditableTextState>() != null) {
        continue;
      }
      final action = Actions.maybeFind<ActivateIntent>(context);
      if (action == null || !action.isEnabled(const ActivateIntent())) {
        continue;
      }
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final rect = visibleGlobalRect(box);
      if (rect == null ||
          labelled.any((a) => a.rect.contains(rect.center)) ||
          found.any((a) => a.rect.contains(rect.center))) {
        continue;
      }
      found.add(
        HintAnchor(
          rect: rect,
          onActivate: () {
            // As a click would: the control takes the focus and is pressed.
            node.requestFocus();
            Actions.invoke(context, const ActivateIntent());
          },
        ),
      );
    }
    return found;
  }

  /// Whether [context] is on the route the user sees on top (the window
  /// itself, or the dialog over it).
  static bool _onTopRoute(BuildContext context) =>
      ModalRoute.of(context)?.isCurrent ?? true;

  static int _readingOrder(HintAnchor a, HintAnchor b) {
    // Targets within the same 8 px band count as one line.
    final rowA = (a.rect.top / 8).floor();
    final rowB = (b.rect.top / 8).floor();
    if (rowA != rowB) return rowA.compareTo(rowB);
    return a.rect.left.compareTo(b.rect.left);
  }
}

/// Global rect of [box] clipped by every scroll viewport above it, or
/// `null` when it is scrolled out of view.
Rect? visibleGlobalRect(RenderBox box) {
  var rect = box.localToGlobal(Offset.zero) & box.size;
  RenderObject? parent = box.parent;
  while (parent != null) {
    if (parent is RenderAbstractViewport && parent is RenderBox) {
      final viewport = parent as RenderBox;
      rect = rect.intersect(
        viewport.localToGlobal(Offset.zero) & viewport.size,
      );
      if (rect.isEmpty) return null;
    }
    parent = parent.parent;
  }
  return rect;
}

/// Provides the window's [HintRegistry] to descendants.
class HintScope extends InheritedWidget {
  const HintScope({required this.registry, required super.child, super.key});

  final HintRegistry registry;

  static HintRegistry? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HintScope>()?.registry;

  @override
  bool updateShouldNotify(HintScope oldWidget) =>
      oldWidget.registry != registry;
}

/// Marks [child] as clickable for hint mode (⌘J). Outside a [HintScope] it
/// is transparent.
class HintTarget extends StatefulWidget {
  const HintTarget({
    required this.onActivate,
    required this.child,
    this.onActivateAlt,
    this.enabled = true,
    super.key,
  });

  final VoidCallback? onActivate;
  final VoidCallback? onActivateAlt;
  final bool enabled;
  final Widget child;

  @override
  State<HintTarget> createState() => _HintTargetState();
}

class _HintTargetState extends State<HintTarget> {
  HintRegistry? _registry;
  HintEntry? _entry;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final registry = HintScope.maybeOf(context);
    if (registry != _registry) {
      _unregister();
      _registry = registry;
    }
    _sync();
  }

  @override
  void didUpdateWidget(HintTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _unregister();
    super.dispose();
  }

  void _sync() {
    _unregister();
    final registry = _registry;
    if (registry == null || !widget.enabled || widget.onActivate == null) {
      return;
    }
    final entry = HintEntry(
      context: context,
      onActivate: () => widget.onActivate?.call(),
      onActivateAlt: widget.onActivateAlt == null
          ? null
          : () => widget.onActivateAlt?.call(),
    );
    registry.register(entry);
    _entry = entry;
  }

  void _unregister() {
    final entry = _entry;
    if (entry != null) {
      _registry?.unregister(entry);
      _entry = null;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
