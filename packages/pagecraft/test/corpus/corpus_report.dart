/// One book's timings in the corpus run.
class CorpusRow {
  CorpusRow({
    required this.name,
    required this.kind,
    required this.bytes,
    this.openMs,
    this.sectionsMs,
    this.sectionCount,
    this.textBytes,
    this.rssGrowthBytes,
    String? note,
  }) : notes = [?note];

  final String name;
  final String kind;
  final int bytes;
  final int? openMs;
  final int? sectionsMs;
  final int? sectionCount;
  final int? textBytes;

  /// Resident set growth across opening the book and loading every
  /// section: an upper bound on what the parsers keep.
  final int? rssGrowthBytes;
  final List<String> notes;

  /// Building a [ContentDocument] for every section, summed.
  int treeMs = 0;

  /// Loading and parsing every section's stylesheets and resolving the
  /// styles of every element, summed.
  int styleMs = 0;

  /// Building the boxes of every section from its styles, summed.
  int boxMs = 0;

  /// The text pipeline: preparing every section (isolate), laying it out
  /// and paginating it, summed; the slowest section's layout; pages.
  int prepareMs = 0;
  int layoutMs = 0;
  int worstLayoutMs = 0;
  int pages = 0;
  int sheets = 0;
  int rules = 0;
  int distinctStyles = 0;
  int styledNodes = 0;
}

/// The timing table of a corpus run, as Markdown.
class CorpusReport {
  final List<CorpusRow> rows = [];

  void add(CorpusRow row) => rows.add(row);

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln(
        '| Book | Kind | MB | Open ms | Sections | Sections ms | Tree ms | '
        'Style ms | Box ms | Prepare/layout ms | Worst layout ms | Pages | '
        'Sheets/rules | Styles/nodes | Text MB | RSS +MB | Note |',
      )
      ..writeln(
        '|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|',
      );
    String mb(int? bytes) =>
        bytes == null ? '' : (bytes / (1024 * 1024)).toStringAsFixed(1);
    for (final row in rows) {
      buffer.writeln(
        '| ${row.name} | ${row.kind} | ${mb(row.bytes)} | '
        '${row.openMs ?? ''} | ${row.sectionCount ?? ''} | '
        '${row.sectionsMs ?? ''} | ${row.treeMs} | '
        '${row.styleMs} | ${row.boxMs} | ${row.prepareMs}/${row.layoutMs} | '
        '${row.worstLayoutMs} | ${row.pages} | ${row.sheets}/${row.rules} | '
        '${row.distinctStyles}/${row.styledNodes} | '
        '${mb(row.textBytes)} | ${mb(row.rssGrowthBytes)} | '
        '${row.notes.join('; ')} |',
      );
    }
    final timed = rows.where((r) => r.openMs != null).toList();
    if (timed.isNotEmpty) {
      int max(Iterable<int> values) => values.reduce((a, b) => a > b ? a : b);
      int sum(Iterable<int> values) => values.fold(0, (a, b) => a + b);
      buffer
        ..writeln()
        ..writeln(
          '${timed.length} books; open max ${max(timed.map((r) => r.openMs!))} '
          'ms, total ${sum(timed.map((r) => r.openMs!))} ms; sections max '
          '${max(timed.map((r) => r.sectionsMs!))} ms; tree max '
          '${max(timed.map((r) => r.treeMs))} ms, total '
          '${sum(timed.map((r) => r.treeMs))} ms; style max '
          '${max(timed.map((r) => r.styleMs))} ms, total '
          '${sum(timed.map((r) => r.styleMs))} ms over '
          '${sum(timed.map((r) => r.rules))} rules; boxes max '
          '${max(timed.map((r) => r.boxMs))} ms, total '
          '${sum(timed.map((r) => r.boxMs))} ms; pipeline prepare total '
          '${sum(timed.map((r) => r.prepareMs))} ms, layout total '
          '${sum(timed.map((r) => r.layoutMs))} ms, worst section layout '
          '${max(timed.map((r) => r.worstLayoutMs))} ms, '
          '${sum(timed.map((r) => r.pages))} pages; RSS growth max '
          '${mb(max(timed.map((r) => r.rssGrowthBytes ?? 0)))} MB.',
        );
    }
    final refused = rows.length - timed.length;
    if (refused > 0) buffer.writeln('$refused books refused.');
    return buffer.toString();
  }
}
