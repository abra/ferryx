import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

@immutable
class Volume extends Equatable {
  const Volume({
    required this.name,
    required this.mountPoint,
    required this.totalBytes,
    required this.availableBytes,
    required this.fileSystem,
    required this.removable,
    required this.isRoot,
  });

  final String name;
  final String mountPoint;
  final int totalBytes;
  final int availableBytes;
  final String fileSystem;
  final bool removable;

  /// The boot volume.
  final bool isRoot;

  @override
  List<Object?> get props => [
    name,
    mountPoint,
    totalBytes,
    availableBytes,
    fileSystem,
    removable,
    isRoot,
  ];
}

/// The folders the Go menu names.
@immutable
class StandardFolders extends Equatable {
  const StandardFolders({
    required this.home,
    required this.desktop,
    required this.documents,
    required this.downloads,
    required this.applications,
    required this.utilities,
    required this.library,
    required this.root,
    required this.temporary,
    required this.userName,
  });

  final String home;
  final String desktop;
  final String documents;
  final String downloads;
  final String applications;
  final String utilities;
  final String library;
  final String root;
  final String temporary;
  final String userName;

  @override
  List<Object?> get props => [
    home,
    desktop,
    documents,
    downloads,
    applications,
    utilities,
    library,
    root,
    temporary,
    userName,
  ];
}
