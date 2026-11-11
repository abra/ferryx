import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_feature/src/file_diff.dart';
import 'package:viewer_feature/src/file_diff_cubit.dart';
import 'package:viewer_feature/src/viewer_source.dart';

class _Source implements ViewerSource {
  _Source(this.length, {this.pending});
  final int length;
  final Completer<Uint8List>? pending;
  int reads = 0;
  @override
  Future<int> size() async => length;
  @override
  Future<Uint8List> read(int offset, int length) async {
    reads++;
    return pending?.future ?? Uint8List.fromList([65]);
  }

  @override
  String get displayName => 'file';
  @override
  String get displayPath => '/';
  @override
  bool get isNative => false;
  @override
  String? get nativePath => null;
}

void main() {
  test('rejects oversized source before any read', () async {
    final a = _Source(FileDiff.maxBytes + 1),
        b = _Source(1),
        cubit = FileDiffCubit();
    await cubit.open(a, b);
    expect(cubit.state.result!.failure, FileDiffFailure.tooLarge);
    expect(a.reads + b.reads, 0);
    await cubit.close();
  });
  test('a retired read cannot overwrite a newer comparison', () async {
    final job = Completer<Uint8List>();
    final slow = _Source(1, pending: job),
        fast = _Source(1),
        cubit = FileDiffCubit();
    final old = cubit.open(slow, fast);
    await Future<void>.delayed(Duration.zero);
    await cubit.open(fast, fast);
    final newest = cubit.state.result;
    job.complete(Uint8List.fromList([66]));
    await old;
    expect(identical(cubit.state.result, newest), isTrue);
    expect(newest!.identicalBytes, isTrue);
    await cubit.close();
  });
}
