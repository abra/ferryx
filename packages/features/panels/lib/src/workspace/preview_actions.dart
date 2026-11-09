part of 'workspace_screen.dart';

extension _PreviewActions on _WorkspaceScreenState {
  WindowDecor _previewDecor(
    Preferences preferences,
    WorkspacePreviewState preview,
  ) {
    final decor = widget.windowDecor;
    if (preview.fullWindow) return decor;
    final side = preview.source?.opposite;
    final stacked = _panelsStacked(preferences, MediaQuery.sizeOf(context));
    if (stacked) return side == PanelSide.left ? decor : WindowDecor.none;
    return WindowDecor(
      integrated: decor.integrated,
      leadingInset: side == PanelSide.left ? decor.leadingInset : 0,
      trailingInset: side == PanelSide.right ? decor.trailingInset : 0,
      dragArea: decor.dragArea,
    );
  }

  Location? _previewLocation(PanelState state) {
    final tab = state.active;
    final row = tab?.focused;
    return tab == null || row == null || row.isDir || row.isParent
        ? null
        : tab.locationOf(row);
  }

  Future<void> _showPreview({
    required bool fullWindow,
    required bool startInPreview,
  }) async {
    if (_previewController.state.shown) {
      if (fullWindow) {
        _previewController.setFullWindow(true);
        _focusPreview();
      } else {
        _closePreview();
      }
      return;
    }
    final side = _workspace.state.active;
    final source = _cubitOf(side);
    final location = _previewLocation(source.state);
    if (fullWindow && location == null) return;
    final archive = location?.archive;
    if (archive != null && !await _ensureArchivePassword(archive)) return;
    if (!mounted) return;
    _previewController.show(
      source: side,
      location: _previewLocation(source.state),
      changes: source.stream.map(_previewLocation),
      fullWindow: fullWindow,
      startInPreview: startInPreview,
    );
    if (fullWindow) _focusPreview();
  }

  void _focusPreview() {
    _afterPreviewFrame(() {
      if (_previewController.state.shown) {
        _previewFocus.requestFocus();
      }
    });
  }

  void _focusPreviewFiles() {
    final side = _previewController.state.source;
    if (side == null) return;
    _previewController.setFullWindow(false);
    _afterPreviewFrame(() => _focusPanel(side));
  }

  void _togglePreviewWindow() {
    _previewController.setFullWindow(!_previewController.state.fullWindow);
    _focusPreview();
  }

  void _closePreview() {
    final side = _previewController.state.source;
    if (side == null) return;
    _previewController.hide();
    _afterPreviewFrame(() => _focusPanel(side));
  }

  void _afterPreviewFrame(VoidCallback action) {
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      if (mounted) action();
    });
    // Tab can change only focus, without a rebuild to schedule this frame.
    binding.scheduleFrame();
  }

  bool _escapePreview() {
    if (_escapeQuickLook()) return true;
    if (!_previewController.state.shown) return false;
    _closePreview();
    return true;
  }
}
