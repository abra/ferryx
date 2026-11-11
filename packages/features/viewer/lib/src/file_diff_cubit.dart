import 'package:domain_models/domain_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'file_diff.dart';
import 'viewer_source.dart';

class FileDiffState {
  const FileDiffState({this.result, this.error, this.loading = true});
  final FileDiff? result;
  final FerryxException? error;
  final bool loading;
}

class FileDiffCubit extends Cubit<FileDiffState> {
  FileDiffCubit() : super(const FileDiffState());
  int _generation = 0;

  Future<void> open(ViewerSource left, ViewerSource right) async {
    final generation = ++_generation;
    emit(const FileDiffState());
    try {
      final sizes = await Future.wait([left.size(), right.size()]);
      if (isClosed || generation != _generation) return;
      if (sizes.any((size) => size > FileDiff.maxBytes)) {
        emit(
          const FileDiffState(
            loading: false,
            result: FileDiff(
              rows: [],
              changes: [],
              identicalBytes: false,
              failure: FileDiffFailure.tooLarge,
            ),
          ),
        );
        return;
      }
      Future<Uint8List> read(ViewerSource source) async {
        // One extra byte catches a file that grew after stat.
        final bytes = await source.read(0, FileDiff.maxBytes + 1);
        return bytes;
      }

      final bytes = await Future.wait([read(left), read(right)]);
      if (isClosed || generation != _generation) return;
      final result = await compute(compareFileBytes, (bytes[0], bytes[1]));
      if (!isClosed && generation == _generation) {
        emit(FileDiffState(loading: false, result: result));
      }
    } on Object catch (error, stack) {
      if (isClosed || generation != _generation) return;
      addError(error, stack);
      emit(
        FileDiffState(
          loading: false,
          error: error is FerryxException
              ? error
              : FerryxException(FerryxErrorKind.io, error.toString()),
        ),
      );
    }
  }
}
