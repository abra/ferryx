import 'dart:async';

import 'package:domain_models/domain_models.dart';
import 'package:file_repository/file_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pagecraft/all_formats.dart';

import 'document_format.dart';
import 'document_session.dart';
import 'viewer_source.dart';

enum DocumentFailureKind {
  read,
  password,
  fixedLayout,
  verticalWriting,
  unsupported,
}

class DocumentFailure {
  const DocumentFailure(this.kind, {this.fileError});
  final DocumentFailureKind kind;
  final FerryxException? fileError;

  factory DocumentFailure.from(Object error) => switch (error) {
    PdfPasswordRequiredException() => const DocumentFailure(
      DocumentFailureKind.password,
    ),
    UnsupportedTextBookException(:final reason) => DocumentFailure(
      reason == TextBookUnsupported.fixedLayout
          ? DocumentFailureKind.fixedLayout
          : DocumentFailureKind.verticalWriting,
    ),
    FerryxException() => DocumentFailure(
      DocumentFailureKind.read,
      fileError: error,
    ),
    _ => const DocumentFailure(DocumentFailureKind.read),
  };
}

class DocumentState {
  const DocumentState({
    this.session,
    this.loading = true,
    this.failure,
    this.index = 0,
    this.count = 0,
    this.canPrevious = false,
    this.canNext = false,
    this.zoom = 1,
  });

  final DocumentSession? session;
  final bool loading;
  final DocumentFailure? failure;
  final int index;
  final int count;
  final bool canPrevious;
  final bool canNext;
  final double zoom;
  bool get fixed => session?.fixedPages != null;
}

/// Owns one opening attempt, including its temporary file and late result.
class DocumentCubit extends Cubit<DocumentState> {
  DocumentCubit({
    this.opener = openDocumentSession,
    Future<void> Function()? beforeRelease,
  }) : _beforeRelease = beforeRelease ?? _immediate,
       super(const DocumentState());

  final DocumentOpener opener;
  final Future<void> Function() _beforeRelease;
  final _retiring = <Future<void>>{};
  _DocumentLoad? _load;
  DocumentAppearance? _appearance;
  Future<void>? _closing;
  bool _stopped = false;

  static Future<void> _immediate() async {}

  Future<void> open(
    DocumentFileSource source,
    DocumentAppearance appearance,
  ) async {
    if (_stopped) return;
    _appearance = appearance;
    final old = _load;
    _load = null;
    emit(const DocumentState());
    if (old != null) _retire(old);
    final format = documentFormatOf(source.displayName);
    if (format == null) {
      emit(
        const DocumentState(
          loading: false,
          failure: DocumentFailure(DocumentFailureKind.unsupported),
        ),
      );
      return;
    }
    _DocumentLoad? load;
    try {
      load = _DocumentLoad(source.preparePreview(), _beforeRelease);
      _load = load;
      final session = await load.open(opener, format, appearance);
      if (_stopped || _load != load) return;
      if (!identical(_appearance, appearance)) {
        session.updateAppearance(_appearance!);
      }
      load.published = true;
      session.addListener(_changed);
      _changed();
    } catch (error) {
      if (_stopped || (load != null && _load != load)) return;
      _load = null;
      emit(DocumentState(loading: false, failure: DocumentFailure.from(error)));
      if (load != null) _retire(load);
    }
  }

  void _changed() {
    if (_stopped) return;
    final session = _load?.session;
    if (session == null) return;
    final error = session.error;
    emit(
      DocumentState(
        session: session,
        loading: !session.ready && error == null,
        failure: error == null ? null : DocumentFailure.from(error),
        index: session.index,
        count: session.count,
        canPrevious: session.canPrevious,
        canNext: session.canNext,
        zoom: state.index == session.index ? state.zoom : 1,
      ),
    );
  }

  void updateAppearance(DocumentAppearance appearance) {
    if (_stopped) return;
    _appearance = appearance;
    _load?.session?.updateAppearance(appearance);
  }

  Future<void> previous() => _navigate((session) => session.previous());
  Future<void> next() => _navigate((session) => session.next());
  Future<void> first() => _navigate((session) => session.first());
  Future<void> last() => _navigate((session) => session.last());
  Future<void> goTo(int index) => _navigate((session) => session.goTo(index));
  Future<void> goToContents(DocumentContentsEntry entry) =>
      _navigate((session) => session.goToContents(entry));

  Future<String?> followLink(TextSectionLayout section, int link) async {
    final load = _load;
    final controller = load?.session?.textController;
    if (_stopped || controller == null) return null;
    try {
      final target = await resolveTextLink(
        controller.source,
        section.prepared,
        link,
      );
      if (_stopped || _load != load) return null;
      switch (target) {
        case InternalTextLink(:final target):
          await controller.goToTarget(target);
        case ExternalTextLink(:final href):
          return href;
        case null:
          break;
      }
    } catch (error, stack) {
      if (!_stopped && _load == load) addError(error, stack);
    }
    return null;
  }

  Future<void> _navigate(Future<void> Function(DocumentSession) action) async {
    final load = _load;
    final session = load?.session;
    if (_stopped || session == null || !session.ready) return;
    try {
      await action(session);
    } catch (error, stack) {
      if (_stopped || _load != load) return;
      addError(error, stack);
      emit(
        DocumentState(
          session: session,
          loading: false,
          failure: DocumentFailure.from(error),
        ),
      );
    }
  }

  void zoomTo(double zoom) {
    if (_stopped || !state.fixed) return;
    emit(
      DocumentState(
        session: state.session,
        loading: state.loading,
        failure: state.failure,
        index: state.index,
        count: state.count,
        canPrevious: state.canPrevious,
        canNext: state.canNext,
        zoom: zoom.clamp(1, 4),
      ),
    );
  }

  void _retire(_DocumentLoad load) {
    load.session?.removeListener(_changed);
    late final Future<void> retired;
    retired = load
        .release()
        .catchError((Object error, StackTrace stack) {
          addError(error, stack);
        })
        .whenComplete(() => _retiring.remove(retired));
    _retiring.add(retired);
  }

  @override
  Future<void> close() async {
    await (_closing ??= _close());
    await super.close();
  }

  Future<void> _close() async {
    _stopped = true;
    final load = _load;
    _load = null;
    if (load != null) _retire(load);
    await Future.wait(_retiring.toList());
  }
}

class _DocumentLoad {
  _DocumentLoad(this.lease, this.beforeRelease);
  final PreviewFileLease lease;
  final Future<void> Function() beforeRelease;
  DocumentSession? session;
  bool published = false;
  bool _cancelled = false;
  Future<DocumentSession>? _opening;
  Future<void>? _release;

  Future<DocumentSession> open(
    DocumentOpener opener,
    DocumentFormat format,
    DocumentAppearance appearance,
  ) async {
    final path = await lease.path;
    if (_cancelled) throw const _Cancelled();
    _opening = opener(path, format, appearance);
    return session = await _opening!;
  }

  Future<void> release() => _release ??= _close();

  Future<void> _close() async {
    _cancelled = true;
    try {
      final pending = _opening;
      if (pending != null) {
        DocumentSession? opened;
        try {
          opened = await pending;
        } catch (_) {
          // The opening caller reports the original error.
        }
        if (opened != null) {
          if (published) await beforeRelease();
          await opened.close();
        }
      }
    } finally {
      await lease.close();
    }
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}
