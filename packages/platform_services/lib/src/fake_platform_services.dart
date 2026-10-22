import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'file_drag_request.dart';
import 'platform_capabilities.dart';
import 'platform_services.dart';
import 'quick_look.dart';

/// [PlatformServices] for tests: it records what the window asked for and
/// lets a test play the desktop's part (the user closing Quick Look,
/// pressing ↓ on it).
class FakePlatformServices implements PlatformServices {
  FakePlatformServices({
    this.capabilities = const PlatformCapabilities(
      quickLook: true,
      share: true,
      fileDrags: true,
    ),
  });

  @override
  final PlatformCapabilities capabilities;

  /// Every list Quick Look was opened on or turned to, in order.
  final quickLooks = <QuickLookItems>[];

  /// Every item the open panel was turned to.
  final selections = <int>[];

  /// How many times the window closed the panel.
  int closes = 0;

  /// Every share picker opened: the files and where it pointed.
  final shares = <({List<String> paths, Rect anchor})>[];

  /// Every drag started.
  final drags = <FileDragRequest>[];

  final _open = ValueNotifier<bool>(false);
  final _events = StreamController<QuickLookEvent>.broadcast();

  /// What the open panel shows, with the last item it was turned to.
  QuickLookItems? get shown {
    if (!_open.value || quickLooks.isEmpty) return null;
    final items = quickLooks.last;
    return selections.isEmpty
        ? items
        : QuickLookItems(items.paths, index: selections.last);
  }

  /// The user closed the panel (its button, or Esc while it had the keys).
  void userClosesQuickLook() {
    if (!_open.value) return;
    _open.value = false;
    _events.add(const QuickLookClosed());
  }

  /// ↑ (−1) or ↓ (+1) pressed while the panel had the keys.
  void userStepsQuickLook(int delta) => _events.add(QuickLookStep(delta));

  @override
  ValueListenable<bool> get quickLookOpen => _open;

  @override
  Stream<QuickLookEvent> get quickLookEvents => _events.stream;

  @override
  Future<void> showQuickLook(QuickLookItems items) async {
    if (items.isEmpty) return closeQuickLook();
    quickLooks.add(items);
    selections.clear();
    _open.value = true;
  }

  @override
  Future<void> selectQuickLookItem(int index) async {
    if (_open.value) selections.add(index);
  }

  @override
  Future<void> closeQuickLook() async {
    if (!_open.value) return;
    closes++;
    _open.value = false;
  }

  @override
  Future<void> share(List<String> paths, {required Rect anchor}) async {
    shares.add((paths: List.unmodifiable(paths), anchor: anchor));
  }

  @override
  Future<void> startFileDrag(
    BuildContext context,
    FileDragRequest request,
  ) async {
    drags.add(request);
  }

  @override
  Future<void> dispose() async {
    await _events.close();
    _open.dispose();
  }
}
