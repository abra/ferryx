part of 'workspace_screen.dart';

/// Servers in the window: Connect to Server and Disconnect, a file on a
/// server opened from a copy, and the file commands with a server on one
/// side or both. What works only on this computer says so on a server.
extension _NetworkActions on _WorkspaceScreenState {
  NetworkService? get _network => widget.network?.service;

  /// What a command that works on this computer only says where it does
  /// not: on a server, in an archive.
  String _notHere(Location location) =>
      location.isRemote ? _l10n.networkNotOnServer : _l10n.noticeNotInArchive;

  /// Whether the active panel is on a server, where the command at hand
  /// does not work; a notice says so.
  bool _onServer() {
    final tab = _tab;
    if (tab == null || !tab.location.isRemote) return false;
    showAppNotice(context, _l10n.networkNotOnServer);
    return true;
  }

  Map<AppCommand, VoidCallback> _networkHandlers() => {
    AppCommand.connectToServer: () => unawaited(_connectToServer()),
    AppCommand.disconnectServer: () => unawaited(_disconnectServer()),
  };

  // ─── Connecting ───

  /// ⌘K, `:connect`: Connect to Server; the active panel goes to the
  /// folder the connection starts in.
  Future<void> _connectToServer() async {
    final network = widget.network;
    if (network == null) return;
    final panel = _active;
    final connection = await network.connectToServer(context);
    if (connection == null || !mounted) return;
    await _openConnection(connection, panel);
  }

  /// A saved server picked from Go To.
  Future<void> _connectProfile(ServerProfile server, PanelCubit panel) async {
    final network = widget.network;
    if (network == null) return;
    final connection = await network.connectProfile(context, server);
    if (connection == null || !mounted) return;
    await _openConnection(connection, panel);
  }

  /// An address typed (Go to Folder, `:connect`, `:cd`): connected to,
  /// then [panel] goes to its folder.
  Future<void> _connectAddress(String text, PanelCubit panel) async {
    final network = widget.network;
    if (network == null) {
      showAppNotice(context, _l10n.networkNotAnAddress(text));
      return;
    }
    final connection = await network.connectAddress(context, text);
    if (connection == null || !mounted) return;
    await _openConnection(connection, panel);
  }

  Future<void> _openConnection(
    ServerConnection connection,
    PanelCubit panel,
  ) async {
    await panel.open(
      Location.remote(server: connection.server, path: connection.home),
    );
    if (mounted) _focusPanel(panel.side);
  }

  /// Disconnect: the active panel's server; its tabs, in both panels, go
  /// back to the disk.
  Future<void> _disconnectServer() async {
    final server = _tab?.location.server;
    final network = _network;
    if (server == null || network == null) {
      showAppNotice(context, _l10n.networkNotRemote);
      return;
    }
    await _guarded(() async {
      await network.disconnect(server);
      if (!mounted) return;
      showAppNotice(
        context,
        _l10n.networkDisconnected(
          ServerKey.parse(server)?.displayRoot ?? server,
        ),
      );
    });
  }

  // ─── Opening ───

  /// A file on a server, opened: a copy comes to a folder of its own
  /// (with its card, as any copy), and the desktop opens that. What is
  /// changed in it stays there, as the notice says.
  Future<void> _openFromServer(OpenFileRequest request) async {
    final server = request.location.server;
    final network = _network;
    if (server == null || network == null) return;
    await _guarded(() async {
      final folder = await network.tempFolder(server);
      final id = await widget.operations.start(
        OperationRequest(
          kind: OpKind.copy,
          sources: [request.location.path],
          destination: folder,
          sourceServer: server,
          conflicts: ConflictPolicy.overwrite,
        ),
      );
      final done = await _whenFinished(id);
      if (!mounted || done.state != OpState.done) return;
      await widget.files.openDefault('$folder/${request.entry.name}');
      if (mounted) {
        showAppNotice(context, _l10n.networkOpenedCopy(request.entry.name));
      }
    });
  }

  // ─── Making and renaming ───

  /// A new folder or file on a server, under a free name, renamed in
  /// place at once.
  Future<void> _newOnServer(PanelTabState tab, {required bool folder}) =>
      _guarded(() async {
        final base = folder
            ? _l10n.newFolderDefaultName
            : _l10n.newFileDefaultName;
        final name = await widget.files.freeNameAt(tab.location, base);
        final at = tab.location.join(name);
        if (folder) {
          await widget.files.makeFolderAt(at);
        } else {
          await widget.files.makeFileAt(at);
        }
        await _active.open(tab.location, focusName: name);
        _active.startRenaming();
      });

  /// The folders of [name] (`a/b/c`; from the server's root when it
  /// starts with `/`) under [folder] on its server, the missing ones made.
  Future<void> _makeFoldersOnServer(Location folder, String name) async {
    var at = name.startsWith('/')
        ? Location.remote(server: folder.server!, path: '/')
        : folder;
    for (final part in name.split('/')) {
      if (part.isEmpty || part == '.') continue;
      at = part == '..' ? (at.parent ?? at) : at.join(part);
      if (part == '..') continue;
      if (await widget.files.statAt(at) == null) {
        await widget.files.makeFolderAt(at);
      }
    }
  }

  /// A file on a server, made empty at [name] under [folder].
  Future<void> _makeFileOnServer(Location folder, String name) =>
      widget.files.makeFileAt(
        name.startsWith('/')
            ? Location.remote(server: folder.server!, path: name)
            : folder.join(name),
      );

  // ─── Copying, moving, deleting ───

  /// Where a copy goes, as the dialog or a `:` line names it: a path on
  /// disk (`~` for home), or a server's address, connected to first when
  /// it is not. One of [known] is taken as it is: the folder the dialog
  /// offered, its text untouched.
  Future<Location?> _destinationOf(
    String text, {
    List<Location> known = const [],
  }) async {
    for (final location in known) {
      if (location.isRemote && text == location.display) return location;
    }
    if (!text.contains('://')) {
      final home = widget.files.standardFolders().home;
      return Location.native(
        text.startsWith('~') ? '$home${text.substring(1)}' : text,
      );
    }
    final network = widget.network;
    final ServerAddress address;
    try {
      if (network == null) {
        throw FerryxException(FerryxErrorKind.invalidName, text);
      }
      address = network.service.parse(text);
    } on FerryxException {
      showAppNotice(context, _l10n.networkNotAnAddress(text));
      return null;
    }
    var server = address.key;
    var path = address.path;
    if (!network.service.servers.containsKey(server)) {
      final connection = await network.connectAddress(context, text);
      if (connection == null) return null;
      server = connection.server;
      if (path.isEmpty) path = connection.home;
    }
    return Location.remote(server: server, path: path.isEmpty ? '/' : path);
  }

  /// F8 on a server: asked every time (it has no trash), deleted for good.
  Future<void> _deleteOnServer(
    PanelTabState tab,
    List<FileEntry> targets,
  ) async {
    final picked = await showDeleteDialog(
      context,
      names: [for (final t in targets) t.name],
      trashDefault: false,
      trashAvailable: false,
      note: _l10n.networkNoTrash,
    );
    if (picked == null) return;
    await widget.operations.start(
      OperationRequest(
        kind: OpKind.delete,
        sources: [for (final t in targets) t.path],
        sourceServer: tab.location.server,
      ),
    );
    _active.clearSelection();
  }

  /// What Copy Path says of [entry] in the active tab: its path on disk,
  /// its address on a server.
  String _shownPath(String path) {
    final server = _tab?.location.server;
    return server == null
        ? path
        : Location.remote(server: server, path: path).display;
  }

  // ─── Vim ───

  /// `:cd` on a server: a path under the folder shown, or from the
  /// server's root; `~` is still home on disk.
  Location _remoteTarget(Location here, String arg) {
    var at = arg.startsWith('/')
        ? Location.remote(server: here.server!, path: '/')
        : here;
    for (final part in arg.split('/')) {
      if (part.isEmpty || part == '.') continue;
      at = part == '..' ? (at.parent ?? at) : at.join(part);
    }
    return at;
  }

  /// `:cp` / `:mv` with an argument where a server is involved: into the
  /// folder it names (an address, or a path on the panel's server), or as
  /// the name it ends in.
  Future<void> _vimCopyOrMoveNetwork(
    PanelTabState tab,
    String arg, {
    required bool move,
  }) async {
    final targets = _targetsOrNotice();
    if (targets.isEmpty) return;
    final target = arg.contains('://') || !tab.location.isRemote
        ? await _destinationOf(arg.contains('://') ? arg : _vimPath(arg))
        : _remoteTarget(tab.location, arg);
    if (target == null || !mounted) return;
    await _guarded(() async {
      final there = await widget.files.statAt(target);
      final into = there == null || !there.isDir ? target.parent : target;
      if (into == null) return;
      await widget.operations.start(
        OperationRequest(
          kind: move ? OpKind.move : OpKind.copy,
          sources: [for (final t in targets) t.path],
          destination: into.path,
          newName: into == target ? null : target.name,
          preserveAttributes: _prefs.preserveAttributes,
          sourceServer: tab.location.server,
          destinationServer: into.server,
        ),
      );
      _active.clearSelection();
    });
  }
}
