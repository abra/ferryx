import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter/widgets.dart';

/// The composition root supplies the viewer without a feature dependency.
class WorkspacePreview {
  const WorkspacePreview({required this.builder});

  final Widget Function(BuildContext context, WorkspacePreviewView view)
  builder;
}

/// The same viewer moves between the opposite pane and the whole window.
class WorkspacePreviewView {
  const WorkspacePreviewView({
    required this.location,
    required this.focusScope,
    required this.fullWindow,
    required this.startInPreview,
    required this.decor,
    required this.onClose,
    required this.onFocusFiles,
    required this.onToggleFullWindow,
  });

  /// No file when the cursor is on a folder, `..`, or an empty listing.
  final Location? location;

  /// Mount this scope without autofocus. A request with no focused child
  /// should focus the viewer's content, rather than a toolbar control.
  final FocusScopeNode focusScope;
  final bool fullWindow;
  final bool startInPreview;
  final WindowDecor decor;
  final VoidCallback onClose;
  final VoidCallback onFocusFiles;
  final VoidCallback onToggleFullWindow;
}
