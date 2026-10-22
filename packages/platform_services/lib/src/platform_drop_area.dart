import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:flutter/widgets.dart';
import 'package:super_clipboard/super_clipboard.dart' show DataReader;
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import 'system_file_drags.dart';

/// The window as a place files can be dropped on: one drop region of the
/// desktop's drag session over everything, which hands each drag to the
/// [FileDropTarget] under the pointer (the innermost) and turns its answer
/// into the drag's feedback. Features see only the targets; the plugin
/// stays here.
///
/// Per move it hit-tests for the target and asks it; another
/// application's first file is read once per drag, as the desktop makes
/// it available, and every file on the drop.
class PlatformDropArea extends StatefulWidget {
  const PlatformDropArea({
    required this.enabled,
    required this.child,
    super.key,
  });

  /// The desktop has file drags (`PlatformCapabilities.fileDrags`); fixed
  /// for the app's life, so the child is never reparented.
  final bool enabled;
  final Widget child;

  @override
  State<PlatformDropArea> createState() => _PlatformDropAreaState();
}

class _PlatformDropAreaState extends State<PlatformDropArea> {
  FileDropTarget? _hovered;
  DropSession? _session;
  String? _firstPath;
  bool _readingFirst = false;

  FileDropOperation _lastAnswer = FileDropOperation.none;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return DropRegion(
      formats: [Formats.fileUri],
      hitTestBehavior: HitTestBehavior.translucent,
      onDropOver: _onOver,
      onDropLeave: (_) => _moveTo(null),
      onPerformDrop: _onDrop,
      onDropEnded: (event) => _end(event.session),
      child: widget.child,
    );
  }

  DropOperation _onOver(DropOverEvent event) {
    final session = event.session;
    if (!identical(session, _session)) _begin(session);
    final target = FileDropTarget.at(context, event.position.global);
    _moveTo(target);
    if (target == null) return DropOperation.none;
    _readFirstPath(session);
    _lastAnswer = target.onOver(_info(session, _knownPaths()));
    return switch (_lastAnswer) {
      FileDropOperation.forbidden => DropOperation.forbidden,
      final answer => toRawOperation(answer) ?? DropOperation.none,
    };
  }

  Future<void> _onDrop(PerformDropEvent event) async {
    final target =
        FileDropTarget.at(context, event.position.global) ?? _hovered;
    final session = event.session;
    final operation = _lastAnswer;
    _moveTo(null);
    if (target == null) return;
    final paths = await _readAllPaths(session);
    if (!mounted) return;
    target.onDrop(_info(session, paths), operation);
  }

  void _begin(DropSession session) {
    _session = session;
    _firstPath = null;
    _readingFirst = false;
  }

  void _end(DropSession session) {
    if (identical(session, _session)) {
      _moveTo(null);
      _session = null;
      _firstPath = null;
    }
  }

  /// The drag left [_hovered] for [target] (or for nowhere).
  void _moveTo(FileDropTarget? target) {
    final previous = _hovered;
    if (previous?.id == target?.id) {
      _hovered = target;
      return;
    }
    _hovered = target;
    previous?.onLeave();
  }

  List<String> _knownPaths() => [?_firstPath];

  FileDragInfo _info(DropSession session, List<String> paths) {
    final items = session.items;
    return FileDragInfo(
      allowed: {
        for (final operation in session.allowedOperations) ?_fromRaw(operation),
      },
      paths: paths,
      local: items.isEmpty ? null : items.first.localData,
      itemCount: items.length,
    );
  }

  /// Another application's first file, to tell its volume while the drag
  /// hangs: read once the desktop offers it.
  void _readFirstPath(DropSession session) {
    if (_readingFirst || _firstPath != null) return;
    final item = session.items.firstOrNull;
    if (item == null || item.localData != null) return;
    final reader = item.dataReader;
    if (reader == null || !reader.canProvide(Formats.fileUri)) return;
    _readingFirst = true;
    unawaited(
      _pathOf(reader).then((path) {
        if (identical(session, _session)) _firstPath = path;
      }),
    );
  }

  Future<List<String>> _readAllPaths(DropSession session) async {
    final paths = await Future.wait([
      for (final item in session.items)
        if (item.dataReader case final DataReader reader
            when reader.canProvide(Formats.fileUri))
          _pathOf(reader),
    ]);
    return [for (final path in paths) ?path];
  }

  static Future<String?> _pathOf(DataReader reader) {
    final done = Completer<String?>();
    final progress = reader.getValue<Uri>(
      Formats.fileUri,
      (uri) {
        if (!done.isCompleted) {
          done.complete(
            uri != null && uri.isScheme('file') ? uri.toFilePath() : null,
          );
        }
      },
      onError: (_) {
        if (!done.isCompleted) done.complete(null);
      },
    );
    if (progress == null && !done.isCompleted) done.complete(null);
    return done.future;
  }

  static FileDropOperation? _fromRaw(DropOperation operation) =>
      switch (operation) {
        DropOperation.copy => FileDropOperation.copy,
        DropOperation.move => FileDropOperation.move,
        DropOperation.link => FileDropOperation.link,
        _ => null,
      };
}
