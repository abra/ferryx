/// Opening a MOBI file: the PDB container, record 0, then a `Mobi6Book`
/// or a `Kf8Book` depending on the part the file holds (`MOBI.open`).
library;

import '../../pagecraft_exception.dart';
import 'kf8_book.dart';
import 'mobi6_book.dart';
import 'mobi_container.dart';
import 'pdb.dart';

/// Either kind of MOBI book.
sealed class MobiBook {
  const MobiBook();

  /// Opens [path]: a KF8 book for version 8 files and combined files
  /// with a KF8 part, a MOBI 6 book otherwise.
  static Future<MobiBook> open(String path) async {
    final pdb = await PdbFile.open(path);
    MobiContainer? container;
    try {
      if (!pdb.isMobi) throw const PagecraftException('Not a MOBI file');
      container = await MobiContainer.open(pdb);
      return container.isKf8
          ? MobiKf8(await Kf8Book.load(container))
          : MobiLegacy(await Mobi6Book.load(container));
    } catch (_) {
      try {
        if (container != null) {
          await container.close();
        } else {
          await pdb.close();
        }
      } catch (_) {
        // Preserve the opening error after attempting both resource releases.
      }
      rethrow;
    }
  }

  Future<void> close();
}

class MobiKf8 extends MobiBook {
  const MobiKf8(this.book);

  final Kf8Book book;

  @override
  Future<void> close() => book.close();
}

class MobiLegacy extends MobiBook {
  const MobiLegacy(this.book);

  final Mobi6Book book;

  @override
  Future<void> close() => book.close();
}
