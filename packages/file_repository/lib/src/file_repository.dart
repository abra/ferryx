import 'dart:async';
import 'dart:typed_data';

import 'package:domain_models/domain_models.dart';
import 'package:ferryx_backend/ferryx_backend.dart' as rust;
import 'package:monitoring/monitoring.dart';

/// Folders and their rows, single items, the volumes and the desktop's
/// folders. Every listing a panel shows is opened here under an id of the
/// panel's own and watched until closed; [directoryChanges] names the
/// listing whose folder changed on disk.
class FileRepository {
  FileRepository({required rust.FerryxBackend backend, required this.logger}) {
    _subscription = backend.events.listen(_onEvent);
  }

  final Logger logger;
  final _changes = StreamController<String>.broadcast();
  StreamSubscription<rust.AppEvent>? _subscription;

  /// Ids of listings whose folders changed, one per burst of changes.
  Stream<String> get directoryChanges => _changes.stream;

  void _onEvent(rust.AppEvent event) {
    if (event.kind == rust.AppEventKind.directoryChanged) {
      final id = event.listingId;
      if (id != null) _changes.add(id);
    }
  }

  // ─── Listings ───

  Future<Listing> openListing(
    String listingId,
    Location location,
    ListingOptions options,
  ) => rust.FerryxBackend.guard(() async {
    final view = await rust.openListing(
      listingId: listingId,
      location: rust.locationToView(location),
      options: rust.listingOptionsToView(options),
    );
    return rust.listingFromView(view);
  });

  /// Reads the listing's folder again (after a change on disk, or ⌘R).
  Future<Listing> refreshListing(String listingId) =>
      rust.FerryxBackend.guard(() async {
        final view = await rust.refreshListing(listingId: listingId);
        return rust.listingFromView(view);
      });

  /// Sorts or filters the rows already read, under new [options].
  Future<Listing> resortListing(String listingId, ListingOptions options) =>
      rust.FerryxBackend.guard(() async {
        final view = await rust.resortListing(
          listingId: listingId,
          options: rust.listingOptionsToView(options),
        );
        return rust.listingFromView(view);
      });

  Future<void> closeListing(String listingId) async {
    try {
      await rust.closeListing(listingId: listingId);
    } on Object catch (error, stackTrace) {
      logger.warn(
        'closing listing $listingId failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// The rows of [location] once, unwatched: for a dialog's completion.
  Future<List<FileEntry>> peek(
    Location location, {
    bool showHidden = false,
  }) => rust.FerryxBackend.guard(() async {
    final views = await rust.peekListing(
      location: rust.locationToView(location),
      showHidden: showHidden,
    );
    return views.map(rust.entryFromView).toList(growable: false);
  });

  /// Whether [path] is a folder one can enter (a symlink to one too).
  bool isDirectory(String path) => rust.isDirectory(path: path);

  /// Whether [path] is an archive the panels can enter.
  bool isArchive(String path) => rust.isArchive(path: path);

  // ─── Items ───

  Future<FileEntry> stat(String path) => rust.FerryxBackend.guard(
    () async => rust.entryFromView(await rust.stat(path: path)),
  );

  /// Up to [length] bytes of the file at [location] from [offset].
  Future<Uint8List> readRange(Location location, int offset, int length) =>
      rust.FerryxBackend.guard(
        () => rust.readFileRange(
          location: rust.locationToView(location),
          offset: offset,
          len: length,
        ),
      );

  Future<int> fileSize(Location location) => rust.FerryxBackend.guard(
    () => rust.fileSize(location: rust.locationToView(location)),
  );

  /// Extracts an archive member to a temporary folder, for opening or
  /// viewing; answers the path written.
  Future<String> extractToTemp(String archive, String inner) =>
      rust.FerryxBackend.guard(
        () => rust.extractToTemp(archivePath: archive, inner: inner),
      );

  /// Makes the folder at [path] and every missing one above it.
  Future<void> createDirectory(String path) =>
      rust.FerryxBackend.guard(() => rust.createDirectory(path: path));

  Future<void> createFile(String path) =>
      rust.FerryxBackend.guard(() => rust.createFile(path: path));

  /// Renames the item at [path]; answers its new path.
  Future<String> rename(String path, String newName) =>
      rust.FerryxBackend.guard(
        () => rust.renameItem(path: path, newName: newName),
      );

  Future<void> createSymlink({required String target, required String link}) =>
      rust.FerryxBackend.guard(
        () => rust.createSymlink(target: target, link: link),
      );

  Future<void> createHardlink({
    required String target,
    required String link,
  }) => rust.FerryxBackend.guard(
    () => rust.createHardlink(target: target, link: link),
  );

  Future<void> editSymlink({required String link, required String target}) =>
      rust.FerryxBackend.guard(
        () => rust.editSymlink(link: link, target: target),
      );

  Future<String> readSymlink(String link) =>
      rust.FerryxBackend.guard(() => rust.readSymlink(link: link));

  /// [path] with every symlink followed.
  Future<String> resolvePath(String path) =>
      rust.FerryxBackend.guard(() => rust.resolvePath(path: path));

  /// The first free name in [dir] for a new item: [name], else `name 2`…
  String freeName(String dir, String name) =>
      rust.freeName(dir: dir, name: name);

  // ─── The system ───

  Future<List<Volume>> volumes() => rust.FerryxBackend.guard(() async {
    final views = await rust.listVolumes();
    return views.map(rust.volumeFromView).toList(growable: false);
  });

  StandardFolders standardFolders() =>
      rust.standardFoldersFromView(rust.standardFolders());

  Future<int?> freeSpace(String path) =>
      rust.FerryxBackend.guard(() => rust.freeSpace(path: path));

  /// Opens the item as a double click in the desktop's file manager would.
  Future<void> openDefault(String path) =>
      rust.FerryxBackend.guard(() => rust.openDefault(path: path));

  Future<void> openWith(String path, String app) =>
      rust.FerryxBackend.guard(() => rust.openWith(path: path, app: app));

  /// Shows the item in Finder, Explorer or the desktop's files app.
  Future<void> reveal(String path) =>
      rust.FerryxBackend.guard(() => rust.revealInFileManager(path: path));

  Future<void> eject(String mountPoint) => rust.FerryxBackend.guard(
    () => rust.ejectVolume(mountPoint: mountPoint),
  );

  /// Applications that open files like [path] (macOS; empty elsewhere).
  Future<List<String>> applicationsFor(String path) =>
      rust.FerryxBackend.guard(() => rust.applicationsFor(path: path));

  // ─── Attributes ───

  Future<FileAttributes> readAttributes(String path) =>
      rust.FerryxBackend.guard(
        () async => rust.attributesFromView(
          await rust.readAttributes(path: path),
        ),
      );

  /// Applies [changes] to every path; answers the items that failed.
  Future<List<RenameFailure>> applyAttributes(
    List<String> paths,
    AttributeChanges changes, {
    bool recursive = false,
  }) => rust.FerryxBackend.guard(() async {
    final failures = await rust.applyAttributes(
      paths: paths,
      changes: rust.attributeChangesToView(changes),
      recursive: recursive,
    );
    return failures.map(rust.renameFailureFromView).toList(growable: false);
  });

  Future<int?> lookupUser(String name) =>
      rust.FerryxBackend.guard(() => rust.lookupUser(name: name));

  Future<int?> lookupGroup(String name) =>
      rust.FerryxBackend.guard(() => rust.lookupGroup(name: name));

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _changes.close();
  }
}
