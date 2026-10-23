import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'file_drag_request.dart';
import 'platform_capabilities.dart';
import 'platform_services.dart';
import 'quick_look.dart';
import 'system_file_drags.dart';

/// Windows and Linux: Quick Look and the share picker are not supported
/// (their commands are hidden, so these calls never come; they do nothing
/// if they do); files are dragged through the desktop's own session, as on
/// macOS.
class DesktopPlatformServices implements PlatformServices {
  DesktopPlatformServices({SystemFileDrags? drags})
    : _drags = drags ?? SystemFileDrags();

  final SystemFileDrags _drags;
  final _closed = ValueNotifier<bool>(false);
  final _latin = ValueNotifier<bool>(true);

  @override
  PlatformCapabilities get capabilities =>
      const PlatformCapabilities(fileDrags: true);

  @override
  ValueListenable<bool> get latinKeyboard => _latin;

  @override
  ValueListenable<bool> get quickLookOpen => _closed;

  @override
  Stream<QuickLookEvent> get quickLookEvents => const Stream.empty();

  @override
  Future<void> showQuickLook(QuickLookItems items) async {}

  @override
  Future<void> selectQuickLookItem(int index) async {}

  @override
  Future<void> closeQuickLook() async {}

  @override
  Future<void> share(List<String> paths, {required Rect anchor}) async {}

  @override
  Future<void> startFileDrag(BuildContext context, FileDragRequest request) =>
      _drags.start(context, request);

  @override
  Future<void> dispose() async {
    _closed.dispose();
    _latin.dispose();
  }
}
