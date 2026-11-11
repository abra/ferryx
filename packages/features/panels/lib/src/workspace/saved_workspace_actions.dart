part of 'workspace_screen.dart';

extension _SavedWorkspaceActions on _WorkspaceScreenState {
  Future<SavedProfiles<SavedWorkspace>?> _workspaceCatalog() async {
    try {
      return await (_savedWorkspaces ??= SavedProfiles.load<SavedWorkspace>(
        widget.sideStorage ?? InMemorySideStorage(),
        key: 'ferryx.workspaces',
        encode: (workspace) => workspace.toJson(),
        decode: SavedWorkspace.fromJson,
      ));
    } catch (error, stack) {
      _savedWorkspaces = null;
      widget.logger.warn('load workspaces', error: error, stackTrace: stack);
      if (mounted) showAppNotice(context, _l10n.savedProfileFailure);
      return null;
    }
  }

  SavedWorkspace _captureWorkspace() => SavedWorkspace(
    left: _left.saved(),
    right: _right.saved(),
    active: _workspace.state.active,
    singlePane: _workspace.state.singlePane,
    splitFraction: _workspace.state.splitFraction,
    arrangement: _prefs.panelArrangement,
    terminal: _dock.state,
  );

  Future<void> _manageWorkspaces() async {
    final catalog = await _workspaceCatalog();
    if (!mounted || catalog == null) return;
    final l10n = _l10n;
    final selected = await showAppDialog<String>(
      context,
      (_) => ListenableBuilder(
        listenable: catalog,
        builder: (context, _) => AppNamedItemsDialog(
          items: [for (final item in catalog.items) AppNamedItem(item.name)],
          labels: AppNamedItemsLabels(
            title: l10n.workspacesTitle,
            name: l10n.savedProfileName,
            empty: l10n.workspacesEmpty,
            create: l10n.workspaceSaveCurrent,
            update: l10n.workspaceUpdateCurrent,
            rename: l10n.actionRename,
            remove: l10n.actionRemove,
            open: l10n.actionOpen,
            close: l10n.actionClose,
            failure: l10n.savedProfileFailure,
          ),
          validateName: (name, replacing) {
            if (!SavedProfiles.validName(name)) {
              return l10n.savedProfileInvalidName;
            }
            if (catalog.contains(name) &&
                name.toLowerCase() != replacing?.toLowerCase()) {
              return l10n.savedProfileExists;
            }
            if (replacing == null &&
                catalog.items.length >= SavedProfiles.maxItems) {
              return l10n.savedProfileLimit;
            }
            return null;
          },
          onCreate: (name) => catalog.save(name, _captureWorkspace()),
          onUpdate: (name) =>
              catalog.save(name, _captureWorkspace(), replace: true),
          onRename: catalog.rename,
          onRemove: catalog.remove,
          onError: (error, stack) => widget.logger.warn(
            'saved workspace',
            error: error,
            stackTrace: stack,
          ),
        ),
      ),
    );
    if (!mounted || selected == null) return;
    final workspace = catalog.items
        .where((item) => item.name == selected)
        .firstOrNull;
    if (workspace != null) await _restoreWorkspace(workspace.value);
  }

  Future<void> _restoreWorkspace(SavedWorkspace saved) async {
    if (_restoringWorkspace) return;
    _setRestoringWorkspace(true);
    _closePreview();
    try {
      await Future.wait([
        _left.restore(saved.left, widget.fallbackLocation),
        _right.restore(saved.right, widget.fallbackLocation),
      ]);
      if (!mounted) return;
      _workspace.restoreLayout(
        active: saved.active,
        singlePane: saved.singlePane,
        splitFraction: saved.splitFraction,
      );
      await widget.preferences.update(
        (prefs) => prefs.copyWith(
          panelArrangement: saved.arrangement,
        ),
      );
      if (!mounted) return;
      _dock.restore(saved.terminal);
      // ExcludeFocus must release the restored panel/terminal before focusing it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _dockChanged(
          focusTerminal:
              saved.terminal.visible &&
              (!saved.terminal.panelsShown ||
                  saved.terminal.mode == TerminalPlace.panelTab &&
                      saved.terminal.tabSelected),
        );
      });
    } catch (error, stack) {
      widget.logger.warn('restore workspace', error: error, stackTrace: stack);
      if (mounted) showAppNotice(context, _l10n.savedProfileFailure);
    } finally {
      if (mounted) {
        _setRestoringWorkspace(false);
        _scheduleSnapshot();
      } else {
        _restoringWorkspace = false;
      }
    }
  }

  Future<void> _vimWorkspace(String name, {bool save = false}) async {
    if (name.isEmpty) return _manageWorkspaces();
    final catalog = await _workspaceCatalog();
    if (!mounted || catalog == null) return;
    if (save) {
      if (!SavedProfiles.validName(name) ||
          catalog.contains(name) ||
          catalog.items.length >= SavedProfiles.maxItems) {
        showAppNotice(context, _l10n.savedProfileExists);
        return;
      }
      try {
        await catalog.save(name, _captureWorkspace());
      } catch (error, stack) {
        widget.logger.warn('save workspace', error: error, stackTrace: stack);
        if (mounted) showAppNotice(context, _l10n.savedProfileFailure);
      }
      return;
    }
    final item = catalog.items
        .where((item) => item.name.toLowerCase() == name.toLowerCase())
        .firstOrNull;
    if (item == null) {
      showAppNotice(context, _l10n.savedProfileMissing);
    } else {
      await _restoreWorkspace(item.value);
    }
  }
}
