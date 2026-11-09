import 'dart:async';
import 'dart:typed_data';

import 'package:domain_models/domain_models.dart';
import 'package:file_repository/file_repository.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/all_formats.dart';
import 'package:viewer_feature/src/document_cubit.dart';
import 'package:viewer_feature/src/document_format.dart';
import 'package:viewer_feature/src/document_session.dart';
import 'package:viewer_feature/src/viewer_source.dart';

const appearance = DocumentAppearance(
  style: BookStyle(),
  fonts: BookFonts(),
  settings: TextPageSettings(),
  textScaler: TextScaler.noScaling,
);

Future<void> flush() => Future<void>.delayed(Duration.zero);

class Lease implements PreviewFileLease {
  Lease(this.name, this.events);
  final String name;
  final List<String> events;
  final result = Completer<String>();
  int closes = 0;
  @override
  Future<String> get path => result.future;
  @override
  Future<void> close() async {
    closes++;
    events.add('lease:$name');
  }
}

class Source implements DocumentFileSource {
  Source(this.lease, {this.displayName = 'book.pdf', this.failure});
  final Lease lease;
  final Object? failure;
  @override
  final String displayName;
  @override
  PreviewFileLease preparePreview() {
    if (failure != null) throw failure!;
    return lease;
  }

  @override
  String get displayPath => '/tmp';
  @override
  bool get isNative => false;
  @override
  String? get nativePath => null;
  @override
  Future<Uint8List> read(int offset, int length) => throw UnimplementedError();
  @override
  Future<int> size() => throw UnimplementedError();
}

class Session extends DocumentSession {
  Session(this.name, this.events);
  final String name;
  final List<String> events;
  int closes = 0;
  DocumentAppearance? appearance;
  @override
  TextPagesController? get textController => null;
  @override
  FixedPageSource? get fixedPages => null;
  @override
  int index = 0;
  @override
  int get count => 3;
  @override
  bool get ready => true;
  @override
  Object? error;
  @override
  bool get canPrevious => index > 0;
  @override
  bool get canNext => index < 2;
  @override
  List<DocumentContentsEntry> get contents => const [];
  @override
  Future<void> goTo(int index) async {
    this.index = index;
    notifyListeners();
  }

  @override
  Future<void> next() => goTo(index + 1);
  @override
  Future<void> previous() => goTo(index - 1);
  @override
  Future<void> first() => goTo(0);
  @override
  Future<void> last() => goTo(2);
  @override
  Future<void> goToContents(DocumentContentsEntry entry) => goTo(entry.index!);
  @override
  void updateAppearance(DocumentAppearance appearance) {
    this.appearance = appearance;
  }

  @override
  Future<void> close() async {
    closes++;
    events.add('session:$name');
    dispose();
  }
}

void main() {
  test(
    'appearance changed during an open reaches the arriving session',
    () async {
      final events = <String>[];
      final lease = Lease('a', events)..result.complete('/a.pdf');
      final pending = Completer<DocumentSession>();
      final session = Session('a', events);
      final cubit = DocumentCubit(opener: (_, _, _) => pending.future);
      final loading = cubit.open(Source(lease), appearance);
      await flush();
      const changed = DocumentAppearance(
        style: BookStyle(fontScale: 2),
        fonts: BookFonts(),
        settings: TextPageSettings(),
        textScaler: TextScaler.noScaling,
      );
      cubit.updateAppearance(changed);
      pending.complete(session);
      await loading;
      expect(session.appearance, same(changed));
      await cubit.close();
    },
  );

  test(
    'format matching requires an extension and accepts compound FB2 names',
    () {
      expect(documentFormatOf('BOOK.EPUB'), DocumentFormat.epub);
      expect(documentFormatOf('book.FB2.ZIP'), DocumentFormat.fb2);
      expect(documentFormatOf('book.fbz'), DocumentFormat.fb2);
      expect(documentFormatOf('book.azw3'), DocumentFormat.mobi);
      expect(documentFormatOf('book.djv'), DocumentFormat.djvu);
      for (final name in [
        'pdf',
        'epub',
        'folder',
        'book.cbr',
        'book.epub.bak',
      ]) {
        expect(isDocumentName(name), isFalse, reason: name);
      }
    },
  );

  test(
    'close cancels pending staging; a late path never opens a decoder',
    () async {
      final events = <String>[];
      final lease = Lease('a', events);
      var opens = 0;
      final cubit = DocumentCubit(
        opener: (_, _, _) async {
          opens++;
          return Session('a', events);
        },
      );
      final loading = cubit.open(Source(lease), appearance);
      await cubit.close();
      expect(lease.closes, 1);
      lease.result.complete('/a.pdf');
      await loading;
      expect(opens, 0);
      expect(cubit.isClosed, isTrue);
    },
  );

  test(
    'close during decoder open keeps the file until its late result closes',
    () async {
      final events = <String>[];
      final lease = Lease('a', events)..result.complete('/a.pdf');
      final pending = Completer<DocumentSession>();
      final session = Session('a', events);
      final cubit = DocumentCubit(opener: (_, _, _) => pending.future);
      final loading = cubit.open(Source(lease), appearance);
      await flush();
      final closing = cubit.close();
      await flush();
      expect(events, isEmpty, reason: 'a native opener still owns the file');
      pending.complete(session);
      await Future.wait([loading, closing]);
      expect(events, ['session:a', 'lease:a']);
      expect(session.closes, 1);
    },
  );

  test(
    'new opening wins; stale successful result closes its own lease only',
    () async {
      final events = <String>[];
      final a = Lease('a', events)..result.complete('/a.pdf');
      final b = Lease('b', events)..result.complete('/b.pdf');
      final pending = Completer<DocumentSession>();
      final first = Session('a', events);
      final second = Session('b', events);
      final cubit = DocumentCubit(
        opener: (path, _, _) async {
          return path == '/a.pdf' ? pending.future : second;
        },
      );
      final old = cubit.open(Source(a), appearance);
      await flush();
      await cubit.open(Source(b), appearance);
      expect(cubit.state.session, same(second));
      pending.complete(first);
      await old;
      await flush();
      expect(cubit.state.session, same(second));
      expect(events, ['session:a', 'lease:a']);
      await cubit.close();
      expect(events, ['session:a', 'lease:a', 'session:b', 'lease:b']);
    },
  );

  test('stale opening error cannot replace the current document', () async {
    final events = <String>[];
    final a = Lease('a', events)..result.complete('/a.pdf');
    final b = Lease('b', events)..result.complete('/b.pdf');
    final pending = Completer<DocumentSession>();
    final second = Session('b', events);
    final cubit = DocumentCubit(
      opener: (path, _, _) async {
        return path == '/a.pdf' ? pending.future : second;
      },
    );
    final old = cubit.open(Source(a), appearance);
    await flush();
    await cubit.open(Source(b), appearance);
    pending.completeError(const PagecraftException('broken'));
    await old;
    await flush();
    expect(cubit.state.session, same(second));
    expect(cubit.state.failure, isNull);
    expect(a.closes, 1);
    await cubit.close();
  });

  test(
    'published controller closes after the old view detaches, before lease',
    () async {
      final events = <String>[];
      final lease = Lease('a', events)..result.complete('/a.pdf');
      final detached = Completer<void>();
      final session = Session('a', events);
      final cubit = DocumentCubit(
        opener: (_, _, _) async => session,
        beforeRelease: () => detached.future,
      );
      await cubit.open(Source(lease), appearance);
      final closing = cubit.close();
      await flush();
      expect(events, isEmpty);
      detached.complete();
      await closing;
      expect(events, ['session:a', 'lease:a']);
    },
  );

  test('decoder errors leave loading and release the staged file', () async {
    final events = <String>[];
    final lease = Lease('a', events)..result.complete('/a.pdf');
    final cubit = DocumentCubit(
      opener: (_, _, _) async {
        throw const UnsupportedTextBookException(
          TextBookUnsupported.fixedLayout,
        );
      },
    );
    await cubit.open(Source(lease), appearance);
    expect(cubit.state.loading, isFalse);
    expect(cubit.state.failure?.kind, DocumentFailureKind.fixedLayout);
    await cubit.close();
    expect(lease.closes, 1);
  });

  test(
    'synchronous preparation failure is visible and retry can succeed',
    () async {
      final events = <String>[];
      final lease = Lease('a', events)..result.complete('/a.pdf');
      final session = Session('a', events);
      final cubit = DocumentCubit(opener: (_, _, _) async => session);
      const error = FerryxException(FerryxErrorKind.notFound, 'gone');
      await cubit.open(Source(lease, failure: error), appearance);
      expect(cubit.state.loading, isFalse);
      expect(cubit.state.failure?.fileError, same(error));
      await cubit.open(Source(lease), appearance);
      expect(cubit.state.failure, isNull);
      expect(cubit.state.session, same(session));
      await cubit.close();
    },
  );

  test(
    'navigation reports the actual position and controller error is typed',
    () async {
      final events = <String>[];
      final lease = Lease('a', events)..result.complete('/a.pdf');
      final session = Session('a', events);
      final cubit = DocumentCubit(opener: (_, _, _) async => session);
      await cubit.open(Source(lease), appearance);
      await cubit.next();
      expect(cubit.state.index, 1);
      expect(cubit.state.canPrevious, isTrue);
      await cubit.last();
      expect(cubit.state.index, 2);
      expect(cubit.state.canNext, isFalse);
      session.error = const UnsupportedTextBookException(
        TextBookUnsupported.verticalWriting,
      );
      session.notifyListeners();
      expect(cubit.state.failure?.kind, DocumentFailureKind.verticalWriting);
      expect(cubit.state.loading, isFalse);
      await cubit.close();
    },
  );
}
