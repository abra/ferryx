import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

enum EntryKind { file, directory, symlink, other }

/// A file, folder or link as a panel shows it.
@immutable
class FileEntry extends Equatable {
  const FileEntry({
    required this.name,
    required this.path,
    required this.kind,
    required this.isDir,
    this.isParent = false,
    this.symlinkTarget,
    this.size,
    this.modified,
    this.created,
    this.accessed,
    this.added,
    this.mode = 0,
    this.uid = 0,
    this.gid = 0,
    this.owner = '',
    this.group = '',
    this.flags = 0,
    this.isHidden = false,
    this.extension = '',
    this.tags = const [],
  });

  final String name;

  /// The full path on disk, or the member's path inside its archive.
  final String path;
  final EntryKind kind;

  /// A folder, or a symlink that leads to one: Return goes inside.
  final bool isDir;

  /// The `..` row at the top of a listing.
  final bool isParent;
  final String? symlinkTarget;

  /// Bytes of a file; of a folder only once its size was calculated.
  final int? size;
  final DateTime? modified;
  final DateTime? created;
  final DateTime? accessed;

  /// When the item was added to its folder (macOS keeps it).
  final DateTime? added;

  /// Unix mode bits (type and permissions).
  final int mode;
  final int uid;
  final int gid;
  final String owner;
  final String group;

  /// BSD file flags; 0 elsewhere.
  final int flags;
  final bool isHidden;

  /// The extension without its dot, as spelled; empty when there is none.
  final String extension;

  /// Finder tag colours (indices into the tag palette).
  final List<int> tags;

  bool get isSymlink => kind == EntryKind.symlink;

  /// The name without its extension.
  String get stem => extension.isEmpty
      ? name
      : name.substring(0, name.length - extension.length - 1);

  /// The folder of a path on disk, as the row's parent.
  String get parentPath {
    final slash = path.lastIndexOf('/');
    return slash <= 0 ? '/' : path.substring(0, slash);
  }

  /// `rwxr-xr-x`, from the mode's permission bits.
  String get permissionsText {
    const letters = 'rwx';
    final buffer = StringBuffer();
    for (var shift = 8; shift >= 0; shift--) {
      final set = (mode >> shift) & 1 == 1;
      buffer.write(set ? letters[(8 - shift) % 3] : '-');
    }
    return buffer.toString();
  }

  /// Whether the item can be run from a shell (an executable bit set and
  /// not a folder).
  bool get isExecutable => !isDir && (mode & 0x49) != 0;

  FileEntry copyWith({int? size, List<int>? tags}) => FileEntry(
    name: name,
    path: path,
    kind: kind,
    isDir: isDir,
    isParent: isParent,
    symlinkTarget: symlinkTarget,
    size: size ?? this.size,
    modified: modified,
    created: created,
    accessed: accessed,
    added: added,
    mode: mode,
    uid: uid,
    gid: gid,
    owner: owner,
    group: group,
    flags: flags,
    isHidden: isHidden,
    extension: extension,
    tags: tags ?? this.tags,
  );

  @override
  List<Object?> get props => [
    name,
    path,
    kind,
    isDir,
    isParent,
    symlinkTarget,
    size,
    modified,
    created,
    accessed,
    added,
    mode,
    uid,
    gid,
    owner,
    group,
    flags,
    isHidden,
    extension,
    tags,
  ];
}
