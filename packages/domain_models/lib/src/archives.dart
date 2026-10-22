import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

/// What an archive holds, before it is extracted: Extract To decides by
/// it whether the archive wants a folder of its own and a password.
@immutable
class ArchiveInfo extends Equatable {
  const ArchiveInfo({
    required this.format,
    this.topLevelCount = 0,
    this.singleTopLevel,
    this.fileCount = 0,
    this.unpackedBytes = 0,
    this.encrypted = false,
    this.needsPassword = false,
    this.hasPassword = false,
  });

  /// `zip`, `tar.gz`, `7z`, `rar`, `iso`, `gz`…
  final String format;

  /// The members at the archive's root.
  final int topLevelCount;

  /// The name of the one member at the root, when there is one.
  final String? singleTopLevel;
  final int fileCount;
  final int unpackedBytes;

  /// Some member's data is encrypted.
  final bool encrypted;

  /// The member list itself is encrypted and no password opened it yet.
  final bool needsPassword;

  /// A password was given for the archive and opened it.
  final bool hasPassword;

  /// The archive unpacks to more than one item: it wants a folder of its
  /// own, as Archive Utility gives it.
  bool get wantsFolder => needsPassword || topLevelCount != 1;

  /// A password must be asked for before it is read.
  bool get asksPassword => (encrypted || needsPassword) && !hasPassword;

  @override
  List<Object?> get props => [
    format,
    topLevelCount,
    singleTopLevel,
    fileCount,
    unpackedBytes,
    encrypted,
    needsPassword,
    hasPassword,
  ];
}
