import 'dart:async';

import 'package:domain_models/domain_models.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';
import 'package:operations_service/operations_service.dart';

/// A search as the dialog follows it: what was asked, what came back.
@immutable
class FindState extends Equatable {
  const FindState({
    this.request,
    this.findId,
    this.running = false,
    this.hits = const [],
    this.current,
    this.scanned = 0,
    this.done = false,
    this.error,
    this.capped = false,
  });

  final FindRequest? request;
  final int? findId;
  final bool running;
  final List<FindHit> hits;

  /// The folder being looked in, while running.
  final String? current;
  final int scanned;

  /// A search ended, with or without hits.
  final bool done;

  /// Why the search could not run (a bad expression).
  final String? error;

  /// The list holds [FindCubit.maxHits]; the search was stopped there.
  final bool capped;

  FindState copyWith({
    FindRequest? request,
    int? findId,
    bool clearFindId = false,
    bool? running,
    List<FindHit>? hits,
    String? current,
    bool clearCurrent = false,
    int? scanned,
    bool? done,
    String? error,
    bool clearError = false,
    bool? capped,
  }) => FindState(
    request: request ?? this.request,
    findId: clearFindId ? null : (findId ?? this.findId),
    running: running ?? this.running,
    hits: hits ?? this.hits,
    current: clearCurrent ? null : (current ?? this.current),
    scanned: scanned ?? this.scanned,
    done: done ?? this.done,
    error: clearError ? null : (error ?? this.error),
    capped: capped ?? this.capped,
  );

  @override
  List<Object?> get props => [
    request,
    findId,
    running,
    hits,
    current,
    scanned,
    done,
    error,
    capped,
  ];
}

/// Runs one search at a time through the core and gathers its hits.
class FindCubit extends Cubit<FindState> {
  FindCubit({required FindService service})
    : _service = service,
      super(const FindState()) {
    _subscription = service.updates.listen(_onUpdate);
  }

  /// More hits than this are not kept: the search stops there.
  static const int maxHits = 10000;

  final FindService _service;
  StreamSubscription<FindUpdate>? _subscription;

  /// Starts [request], ending a search under way first.
  Future<void> start(FindRequest request) async {
    await stop();
    emit(
      FindState(request: request, running: true),
    );
    final id = await _service.start(request);
    if (isClosed) return;
    // The search may have been stopped while the core took the request.
    if (!state.running || state.request != request) return;
    emit(state.copyWith(findId: id));
  }

  /// Ends the search under way; what it found stays.
  Future<void> stop() async {
    final id = state.findId;
    if (!state.running) return;
    emit(state.copyWith(running: false, done: true, clearCurrent: true));
    if (id != null) await _service.cancel(id);
  }

  void _onUpdate(FindUpdate update) {
    if (update.findId != state.findId || !state.running) return;
    if (update.done) {
      emit(
        state.copyWith(
          running: false,
          done: true,
          scanned: update.scanned,
          error: update.error,
          clearCurrent: true,
        ),
      );
      return;
    }
    var hits = state.hits;
    var capped = state.capped;
    if (update.hits.isNotEmpty && !capped) {
      final room = maxHits - hits.length;
      if (update.hits.length <= room) {
        hits = [...hits, ...update.hits];
      } else {
        hits = [...hits, ...update.hits.take(room)];
        capped = true;
      }
    }
    final newlyCapped = capped && !state.capped;
    emit(
      state.copyWith(
        hits: hits,
        capped: capped,
        current: update.current,
        scanned: update.scanned,
      ),
    );
    if (newlyCapped) {
      // Enough: the rest would never be shown.
      unawaited(stop());
    }
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    final id = state.findId;
    if (state.running && id != null) {
      unawaited(_service.cancel(id));
    }
    return super.close();
  }
}
