import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'file_drag_request.dart';
import 'monospace_fonts.dart';
import 'platform_capabilities.dart';
import 'platform_services.dart';
import 'quick_look.dart';
import 'system_file_drags.dart';

/// macOS: Quick Look and the share picker through the runner's channel
/// (`macos/Runner/NativeServices.swift`), files dragged through the
/// desktop's session.
///
/// The channel, both ways:
/// - `fonts.monospaceFamilies` (installed monospace family names),
///   `quickLook.show {paths, index}`, `quickLook.select {index}`,
///   `quickLook.close`, `share {paths, rect: [left, top, width, height]}`,
///   `keyboard.latin` (whether the layout is ASCII-capable);
/// - from the runner: `quickLook.closed`, `quickLook.step {delta}`,
///   `keyboard.changed {latin}` as the layout changes.
class ChannelPlatformServices implements PlatformServices {
  ChannelPlatformServices({MethodChannel? channel, SystemFileDrags? drags})
    : _channel = channel ?? const MethodChannel(channelName),
      _drags = drags ?? SystemFileDrags() {
    _channel.setMethodCallHandler(_onCall);
    unawaited(_readKeyboard());
  }

  static const channelName = 'ferryx/platform';

  final MethodChannel _channel;
  final SystemFileDrags _drags;
  final _open = ValueNotifier<bool>(false);
  final _events = StreamController<QuickLookEvent>.broadcast();
  final _latin = ValueNotifier<bool>(true);

  @override
  PlatformCapabilities get capabilities => const PlatformCapabilities(
    quickLook: true,
    share: true,
    fileDrags: true,
  );

  Future<Object?> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'quickLook.closed':
        // A close asked for here is known already.
        if (!_open.value) return null;
        _open.value = false;
        _events.add(const QuickLookClosed());
      case 'quickLook.step':
        final delta = (call.arguments as Map?)?['delta'];
        if (_open.value && delta is int && delta != 0) {
          _events.add(QuickLookStep(delta));
        }
      case 'keyboard.changed':
        final latin = (call.arguments as Map?)?['latin'];
        if (latin is bool) _latin.value = latin;
    }
    return null;
  }

  // A runner without the call leaves the layout Latin.
  Future<void> _readKeyboard() async {
    try {
      final latin = await _channel.invokeMethod<bool>('keyboard.latin');
      if (latin != null) _latin.value = latin;
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  @override
  ValueListenable<bool> get latinKeyboard => _latin;

  @override
  Future<List<String>> monospaceFontFamilies() =>
      readMonospaceFontFamilies(_channel);

  // ─── Quick Look ───

  @override
  ValueListenable<bool> get quickLookOpen => _open;

  @override
  Stream<QuickLookEvent> get quickLookEvents => _events.stream;

  @override
  Future<void> showQuickLook(QuickLookItems items) async {
    if (items.isEmpty) return closeQuickLook();
    await _channel.invokeMethod<void>('quickLook.show', {
      'paths': items.paths,
      'index': items.index,
    });
    _open.value = true;
  }

  @override
  Future<void> selectQuickLookItem(int index) async {
    if (!_open.value) return;
    await _channel.invokeMethod<void>('quickLook.select', {'index': index});
  }

  @override
  Future<void> closeQuickLook() async {
    if (!_open.value) return;
    _open.value = false;
    await _channel.invokeMethod<void>('quickLook.close');
  }

  // ─── Share ───

  @override
  Future<void> share(List<String> paths, {required Rect anchor}) async {
    if (paths.isEmpty) return;
    await _channel.invokeMethod<void>('share', {
      'paths': paths,
      'rect': [anchor.left, anchor.top, anchor.width, anchor.height],
    });
  }

  // ─── Drag and drop ───

  @override
  Future<void> startFileDrag(BuildContext context, FileDragRequest request) =>
      _drags.start(context, request);

  @override
  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    await _events.close();
    _open.dispose();
    _latin.dispose();
  }
}
