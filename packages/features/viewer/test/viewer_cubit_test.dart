import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_feature/viewer_feature.dart';
import 'package:viewer_feature/src/markdown_format.dart';
import 'package:viewer_feature/src/text_preview_data.dart';
import 'package:viewer_feature/src/text_preview_format.dart';
import 'package:viewer_feature/src/source_syntax.dart';

/// A file held in memory.
class FakeSource implements ViewerSource {
  FakeSource(this.bytes, {this.fail = false, this.name = 'file.txt'});

  final Uint8List bytes;
  final bool fail;
  final String name;
  int reads = 0;
  int sizeReads = 0;

  @override
  Future<int> size() async {
    sizeReads++;
    if (fail) throw const FerryxException(FerryxErrorKind.notFound, 'gone');
    return bytes.length;
  }

  @override
  Future<Uint8List> read(int offset, int length) async {
    reads++;
    final end = (offset + length).clamp(0, bytes.length);
    return Uint8List.sublistView(bytes, offset, end);
  }

  @override
  String get displayName => name;

  @override
  String get displayPath => '/tmp';

  @override
  bool get isNative => true;

  @override
  String? get nativePath => '/tmp/file.txt';
}

class DeferredSource extends FakeSource {
  DeferredSource(super.bytes, {super.name = 'book.epub'});

  final firstRead = Completer<Uint8List>();

  @override
  Future<Uint8List> read(int offset, int length) {
    if (reads == 0) {
      reads++;
      return firstRead.future;
    }
    return super.read(offset, length);
  }
}

class OversizedOfficeSource extends FakeSource {
  OversizedOfficeSource() : super(Uint8List(0), name: 'large.docx');
  @override
  Future<int> size() async => maxOfficePreviewBytes + 1;
}

Uint8List text(String s) => Uint8List.fromList(utf8.encode(s));

class ConvertedSource extends FakeSource implements ConvertedDocumentSource {
  ConvertedSource(super.bytes) : super(name: 'document.rtf');
  final converted = Completer<String>();
  var conversions = 0;
  @override
  Future<String> renderTextDocument(
    Uint8List bytes,
    TextDocumentFormat format,
  ) {
    conversions++;
    return converted.future;
  }
}

void main() {
  group('ViewerCubit', () {
    test(
      'oversized office sources are rejected before reading or conversion',
      () async {
        final source = OversizedOfficeSource();
        final cubit = ViewerCubit(
          source: source,
          wrap: true,
          mode: ViewerMode.preview,
        );
        await cubit.load();
        expect(source.reads, 0);
        expect(
          (cubit.state.textPreview! as FailedTextPreview).reason,
          TextPreviewFailure.limit,
        );
        await cubit.close();
      },
    );
    test('late conversion cannot replace Hex or start HTML preparation after closing', () async {
      for (final close in [false, true]) {
        final source = ConvertedSource(text(r'{\rtf1 body}'));
        final cubit = ViewerCubit(
          source: source,
          wrap: true,
          mode: ViewerMode.preview,
        );
        final pending = cubit.load();
        await Future<void>.delayed(Duration.zero);
        expect(source.conversions, 1);
        if (close) {
          await cubit.close();
        } else {
          cubit.setMode(ViewerMode.hex);
          await cubit.stream.firstWhere((state) => !state.loading);
        }
        source.converted.complete('<p>Late document</p>');
        await pending;
        expect(cubit.state.textPreview, isNull);
        if (!close) {
          expect(cubit.state.mode, ViewerMode.hex);
          await cubit.close();
        }
      }
    });

    test('native format failures keep a typed preview failure and leave Text available', () async {
      final source = ConvertedSource(text('broken RTF'));
      final cubit = ViewerCubit(
        source: source,
        wrap: true,
        mode: ViewerMode.preview,
      );
      addTearDown(cubit.close);
      final pending = cubit.load();
      await Future<void>.delayed(Duration.zero);
      source.converted.completeError(
        const FerryxException(FerryxErrorKind.unsupported, 'invalid RTF'),
      );
      await pending;
      expect(
        (cubit.state.textPreview as FailedTextPreview).reason,
        TextPreviewFailure.malformed,
      );
      cubit.setMode(ViewerMode.text);
      await cubit.stream.firstWhere((state) => !state.loading);
      expect(cubit.state.window.lines, ['broken RTF']);
    });

    test(
      'source highlighting skips large files without reducing the text window',
      () async {
        final source = FakeSource(
          Uint8List.fromList(List.filled(maxSyntaxBytes + 1, 0x61)),
          name: 'large.json',
        );
        var highlights = 0;
        final cubit = ViewerCubit(
          source: source,
          wrap: true,
          highlighter: (_, _) async {
            highlights++;
            return const [];
          },
        );
        addTearDown(cubit.close);
        await cubit.load();
        expect(cubit.state.bytes.length, maxSyntaxBytes + 1);
        expect(cubit.state.syntaxRevision, 0);
        expect(cubit.state.window.binary, isFalse);
        expect(highlights, 0);
        expect(source.reads, 1);
      },
    );
    test(
      'Markdown preview reads the complete bounded source and refreshes it',
      () async {
        final source = FakeSource(
          text('# Привет\n\n**Markdown**'),
          name: 'README.MD',
        );
        final cubit = ViewerCubit(
          source: source,
          wrap: true,
          mode: ViewerMode.preview,
        );
        addTearDown(cubit.close);
        await cubit.load();
        expect(cubit.state.markdown, '# Привет\n\n**Markdown**');
        expect(cubit.state.bytes, isEmpty);
        expect(source.reads, 1);
        await cubit.refresh();
        expect(source.reads, 2);
        expect(cubit.state.generation, 2);
        cubit.setMode(ViewerMode.text);
        await cubit.stream.firstWhere((state) => !state.loading);
        expect(cubit.state.window.lines.first, '# Привет');
        expect(source.reads, 3);
      },
    );

    test('oversized Markdown is not read until switching to Text', () async {
      final source = FakeSource(
        Uint8List(maxMarkdownPreviewBytes + 1),
        name: 'large.md',
      );
      final cubit = ViewerCubit(
        source: source,
        wrap: true,
        mode: ViewerMode.preview,
      );
      addTearDown(cubit.close);
      await cubit.load();
      expect(source.reads, 0);
      expect(cubit.state.size, maxMarkdownPreviewBytes + 1);
      expect(cubit.state.markdown, isEmpty);
      cubit.setMode(ViewerMode.text);
      await cubit.stream.firstWhere((state) => !state.loading);
      expect(source.reads, 1);
    });

    test('a late highlighter cannot replace a newer mode', () async {
      final highlighted = Completer<List<List<SourceToken>>>();
      final cubit = ViewerCubit(
        source: FakeSource(text('fn main() {}'), name: 'file.rs'),
        wrap: true,
        highlighter: (_, _) => highlighted.future,
      );
      addTearDown(cubit.close);
      await cubit.load();
      cubit.setMode(ViewerMode.hex);
      highlighted.complete([
        [const SourceToken(0, 2, 'keyword')],
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.mode, ViewerMode.hex);
      expect(cubit.state.syntaxRevision, 0);
      expect(cubit.state.syntax, isEmpty);
    });

    test('a late Markdown read cannot replace Text state', () async {
      final source = DeferredSource(text('# First'), name: 'notes.md');
      final cubit = ViewerCubit(
        source: source,
        wrap: true,
        mode: ViewerMode.preview,
      );
      addTearDown(cubit.close);
      final pending = cubit.load();
      await Future<void>.delayed(Duration.zero);
      cubit.setMode(ViewerMode.text);
      await cubit.stream.firstWhere((state) => !state.loading);
      source.firstRead.complete(text('# Late result'));
      await pending;
      expect(cubit.state.mode, ViewerMode.text);
      expect(cubit.state.window.lines, ['# First']);
      expect(cubit.state.markdown, isEmpty);
    });

    test('an empty Markdown file completes without a range read', () async {
      final source = FakeSource(Uint8List(0), name: 'empty.md');
      final cubit = ViewerCubit(
        source: source,
        wrap: true,
        mode: ViewerMode.preview,
      );
      addTearDown(cubit.close);
      await cubit.load();
      expect(source.reads, 0);
      expect(cubit.state.loading, isFalse);
    });

    test(
      'document preview leaves all file IO to its cancellable session',
      () async {
        final source = FakeSource(text('binary book'), name: 'book.epub');
        final cubit = ViewerCubit(
          source: source,
          wrap: true,
          mode: ViewerMode.preview,
        );
        addTearDown(cubit.close);
        await cubit.load();
        await cubit.refresh();
        expect(source.reads, 0);
        expect(source.sizeReads, 0);
        expect(cubit.state.bytes, isEmpty);
        expect(cubit.state.loading, isFalse);
        expect(cubit.state.generation, 2);
      },
    );

    test(
      'image preview only reads metadata; switching to Hex loads bytes',
      () async {
        final source = FakeSource(text('image bytes'), name: 'picture.png');
        final cubit = ViewerCubit(
          source: source,
          wrap: false,
          mode: ViewerMode.preview,
        );
        addTearDown(cubit.close);
        await cubit.load();
        expect(source.reads, 0);
        expect(cubit.state.size, source.bytes.length);
        cubit.setMode(ViewerMode.hex);
        await cubit.stream.firstWhere((state) => !state.loading);
        expect(source.reads, 1);
        expect(cubit.state.bytes, source.bytes);
      },
    );

    test(
      'a text read finishing after switching to Preview is discarded',
      () async {
        final source = DeferredSource(text('book contents'));
        final cubit = ViewerCubit(source: source, wrap: false);
        addTearDown(cubit.close);
        final pending = cubit.load();
        await Future<void>.delayed(Duration.zero);
        expect(source.reads, 1);
        cubit.setMode(ViewerMode.preview);
        final generation = cubit.state.generation;
        source.firstRead.complete(source.bytes);
        await pending;
        expect(cubit.state.mode, ViewerMode.preview);
        expect(cubit.state.bytes, isEmpty);
        expect(cubit.state.generation, generation);
        cubit.setMode(ViewerMode.text);
        await cubit.stream.firstWhere((state) => !state.loading);
        expect(source.reads, 2);
        expect(cubit.state.window.lines, ['book contents']);
      },
    );

    test('refreshing Preview invalidates the cached text window', () async {
      final source = FakeSource(text('book contents'), name: 'book.epub');
      final cubit = ViewerCubit(source: source, wrap: false);
      addTearDown(cubit.close);
      await cubit.load();
      cubit.showFind();
      cubit.setMode(ViewerMode.preview);
      expect(cubit.state.findShown, isFalse);
      await cubit.refresh();
      cubit.setMode(ViewerMode.text);
      await cubit.stream.firstWhere((state) => !state.loading);
      expect(source.reads, 2);
    });

    blocTest<ViewerCubit, ViewerState>(
      'reads the first window and splits it into lines',
      build: () =>
          ViewerCubit(source: FakeSource(text('one\ntwo\n')), wrap: true),
      act: (cubit) => cubit.load(),
      verify: (cubit) {
        final state = cubit.state;
        expect(state.loading, isFalse);
        expect(state.size, 8);
        expect(state.window.lines, ['one', 'two', '']);
        expect(state.windowed, isFalse);
        expect(state.generation, 1);
        expect(state.scroll, ViewerScroll.top);
      },
    );

    blocTest<ViewerCubit, ViewerState>(
      'a failure to read is kept in the state',
      build: () =>
          ViewerCubit(source: FakeSource(text('x'), fail: true), wrap: false),
      act: (cubit) => cubit.load(),
      verify: (cubit) {
        expect(cubit.state.loading, isFalse);
        expect(cubit.state.error?.kind, FerryxErrorKind.notFound);
      },
    );

    blocTest<ViewerCubit, ViewerState>(
      'large files come in windows, next and previous',
      build: () => ViewerCubit(
        source: FakeSource(text('aaaa\nbbbb\ncccc\n')),
        wrap: false,
        windowSize: 6,
      ),
      act: (cubit) async {
        await cubit.load();
        await cubit.loadNext();
        await cubit.loadNext();
        await cubit.loadNext();
        await cubit.loadPrevious();
      },
      verify: (cubit) {
        final state = cubit.state;
        expect(state.windowed, isTrue);
        expect(state.offset, 6);
        expect(state.windowEnd, 12);
        expect(state.scroll, ViewerScroll.bottom);
        expect(state.hasNext, isTrue);
        expect(state.hasPrevious, isTrue);
        expect(state.window.lines, ['bbb', 'cc']);
      },
    );

    blocTest<ViewerCubit, ViewerState>(
      'go to lands on a hex row in hex mode and loads the last window',
      build: () => ViewerCubit(
        source: FakeSource(Uint8List.fromList(List.generate(100, (i) => i))),
        wrap: false,
        windowSize: 32,
      ),
      act: (cubit) async {
        await cubit.load();
        cubit.setMode(ViewerMode.hex);
        await cubit.goTo(50);
        expect(cubit.state.offset, 48);
        await cubit.loadLast();
      },
      verify: (cubit) {
        expect(cubit.state.offset, 68);
        expect(cubit.state.hasNext, isFalse);
        expect(cubit.state.mode, ViewerMode.hex);
      },
    );

    blocTest<ViewerCubit, ViewerState>(
      'find walks the matches round the ends and follows the mode',
      build: () =>
          ViewerCubit(source: FakeSource(text('ab\nAB ab\nx')), wrap: false),
      act: (cubit) async {
        await cubit.load();
        cubit.showFind();
        cubit.setFindQuery('ab');
        expect(cubit.state.matches.length, 3);
        expect(cubit.state.currentMatch, 0);
        expect(cubit.state.scroll, ViewerScroll.match);
        cubit.findNext();
        cubit.findNext();
        expect(cubit.state.currentMatch, 2);
        cubit.findNext();
        expect(cubit.state.currentMatch, 0);
        cubit.findPrevious();
        expect(cubit.state.currentMatch, 2);
        cubit.setMode(ViewerMode.hex);
        expect(cubit.state.matches.length, 3);
        expect(cubit.state.matches.first.line, 0);
        cubit.setMode(ViewerMode.preview);
        expect(cubit.state.matches, isEmpty);
        cubit.setMode(ViewerMode.text);
        cubit.hideFind();
      },
      verify: (cubit) {
        expect(cubit.state.findShown, isFalse);
        expect(cubit.state.findQuery, '');
        expect(cubit.state.matches, isEmpty);
        expect(cubit.state.currentMatch, -1);
      },
    );

    blocTest<ViewerCubit, ViewerState>(
      'wrap toggles and refresh reads again',
      build: () => ViewerCubit(source: FakeSource(text('x')), wrap: true),
      act: (cubit) async {
        await cubit.load();
        cubit.toggleWrap();
        await cubit.refresh();
      },
      verify: (cubit) {
        expect(cubit.state.wrap, isFalse);
        expect(cubit.state.generation, 2);
        expect((cubit.source as FakeSource).reads, 2);
      },
    );
  });
}
