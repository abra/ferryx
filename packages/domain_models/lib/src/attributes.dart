import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

/// The BSD file flags the attributes dialog offers (macOS).
abstract final class FileFlags {
  static const int noDump = 0x1;
  static const int userImmutable = 0x2;
  static const int userAppend = 0x4;
  static const int opaque = 0x8;
  static const int hidden = 0x8000;
  static const int archived = 0x10000;
  static const int systemImmutable = 0x20000;
  static const int systemAppend = 0x40000;
}

/// Permission bits by role.
abstract final class Permissions {
  static const int ownerRead = 0x100;
  static const int ownerWrite = 0x80;
  static const int ownerExecute = 0x40;
  static const int groupRead = 0x20;
  static const int groupWrite = 0x10;
  static const int groupExecute = 0x8;
  static const int othersRead = 0x4;
  static const int othersWrite = 0x2;
  static const int othersExecute = 0x1;
  static const int setUid = 0x800;
  static const int setGid = 0x400;
  static const int sticky = 0x200;

  static const List<int> all = [
    ownerRead,
    ownerWrite,
    ownerExecute,
    groupRead,
    groupWrite,
    groupExecute,
    othersRead,
    othersWrite,
    othersExecute,
    setUid,
    setGid,
    sticky,
  ];
}

@immutable
class FileAttributes extends Equatable {
  const FileAttributes({
    required this.path,
    required this.permissions,
    required this.uid,
    required this.gid,
    required this.owner,
    required this.group,
    required this.flags,
    required this.isDir,
    this.supportsFlags = false,
    this.modified,
    this.accessed,
    this.created,
  });

  final String path;

  /// The low 12 bits of the mode.
  final int permissions;
  final int uid;
  final int gid;
  final String owner;
  final String group;
  final int flags;

  /// The file system keeps BSD flags (locked, hidden), set or not.
  final bool supportsFlags;
  final bool isDir;
  final DateTime? modified;
  final DateTime? accessed;
  final DateTime? created;

  @override
  List<Object?> get props => [
    path,
    permissions,
    uid,
    gid,
    owner,
    group,
    flags,
    supportsFlags,
    isDir,
    modified,
    accessed,
    created,
  ];
}

/// What to change; bits to set and to clear, so a selection of several
/// items can change some bits and leave each item's others.
@immutable
class AttributeChanges extends Equatable {
  const AttributeChanges({
    this.permissionsSet = 0,
    this.permissionsClear = 0,
    this.uid,
    this.gid,
    this.flagsSet = 0,
    this.flagsClear = 0,
    this.modified,
    this.accessed,
  });

  final int permissionsSet;
  final int permissionsClear;
  final int? uid;
  final int? gid;
  final int flagsSet;
  final int flagsClear;
  final DateTime? modified;
  final DateTime? accessed;

  bool get isEmpty => this == const AttributeChanges();

  @override
  List<Object?> get props => [
    permissionsSet,
    permissionsClear,
    uid,
    gid,
    flagsSet,
    flagsClear,
    modified,
    accessed,
  ];
}
