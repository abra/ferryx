import 'dart:async';

import 'package:domain_models/domain_models.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../panel/panel_side.dart';

class WorkspacePreviewState extends Equatable {
  const WorkspacePreviewState({
    this.source,
    this.location,
    this.fullWindow = false,
    this.startInPreview = false,
  });

  final PanelSide? source;
  final Location? location;
  final bool fullWindow;
  final bool startInPreview;
  bool get shown => source != null;

  @override
  List<Object?> get props => [source, location, fullWindow, startInPreview];
}

/// Follows only the source pane. Fast cursor moves publish the last file;
/// selection and other changes to the same file do not reopen the viewer.
class WorkspacePreviewCubit extends Cubit<WorkspacePreviewState> {
  WorkspacePreviewCubit({
    this.followDelay = const Duration(milliseconds: 150),
  }) : super(const WorkspacePreviewState());

  final Duration followDelay;
  StreamSubscription<Location?>? _following;
  Timer? _timer;
  Location? _pending;

  void show({
    required PanelSide source,
    required Location? location,
    required Stream<Location?> changes,
    required bool fullWindow,
    bool startInPreview = true,
  }) {
    _stopFollowing();
    _pending = location;
    emit(
      WorkspacePreviewState(
        source: source,
        location: location,
        fullWindow: fullWindow,
        startInPreview: startInPreview,
      ),
    );
    _following = changes.listen(_follow);
  }

  void _follow(Location? location) {
    if (!state.shown || location == _pending) return;
    _pending = location;
    _timer?.cancel();
    if (location == state.location) return;
    _timer = Timer(followDelay, () {
      emit(
        WorkspacePreviewState(
          source: state.source,
          location: location,
          fullWindow: state.fullWindow,
          startInPreview: state.startInPreview,
        ),
      );
    });
  }

  void setFullWindow(bool fullWindow) {
    if (!state.shown || state.fullWindow == fullWindow) return;
    emit(
      WorkspacePreviewState(
        source: state.source,
        location: state.location,
        fullWindow: fullWindow,
        startInPreview: state.startInPreview,
      ),
    );
  }

  void hide() {
    _stopFollowing();
    emit(const WorkspacePreviewState());
  }

  void _stopFollowing() {
    _timer?.cancel();
    _timer = null;
    unawaited(_following?.cancel());
    _following = null;
    _pending = null;
  }

  @override
  Future<void> close() {
    _stopFollowing();
    return super.close();
  }
}
