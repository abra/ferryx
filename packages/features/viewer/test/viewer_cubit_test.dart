import 'dart:convert';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_feature/viewer_feature.dart';

/// A file held in memory.
class FakeSource implements ViewerSource {
  FakeSource(this.bytes, {this.fail = false});

  final Uint8List bytes;
  final bool fail;
  int reads = 0;

  @override
  Future<int> size() async {
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
  String get displayName => 'file.txt';

  @override
  String get displayPath => '/tmp';

  @override
  bool get isNative => true;

  @override
  String? get nativePath => '/tmp/file.txt';
}

Uint8List text(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  group('ViewerCubit', () {
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
