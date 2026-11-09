/// CFIs for sections that have no spine item of their own: comic pages,
/// PDF pages, MOBI chapters. The same strings foliate-js writes
/// (`CFI.fake`), so positions saved by either reader open in the other.
///
/// Section `n` is `epubcfi(/6/(n+1)*2)`: the even step a spine item would
/// have under a package document's `<spine>`.
library;

final _fakeCfi = RegExp(r'^epubcfi\(/6/(\d+)');

String fakeCfiFromIndex(int index) {
  if (index < 0) throw RangeError.range(index, 0, null, 'index');
  return 'epubcfi(/6/${(index + 1) * 2})';
}

/// The section index a fake CFI names, or null when [cfi] is not one.
///
/// Anything after the spine step (an indirection into the section, a text
/// assertion) is ignored, as foliate-js ignores it.
int? fakeCfiToIndex(String cfi) {
  final match = _fakeCfi.firstMatch(cfi);
  if (match == null) return null;
  final step = int.parse(match.group(1)!);
  if (step < 2 || step.isOdd) return null;
  return step ~/ 2 - 1;
}
