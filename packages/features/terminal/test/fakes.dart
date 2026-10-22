import 'dart:async';
import 'dart:convert';

import 'package:domain_models/domain_models.dart';
import 'package:terminal_service/terminal_service.dart';

/// A session that records what the cubit asks of it.
class FakeSession implements TerminalSession {
  final controller = StreamController<TerminalUpdate>();
  final written = <int>[];
  final resizes = <(int, int)>[];
  final directories = <String>[];
  var acks = 0;
  var closed = false;
  var changeAnswers = true;
  var current = const TerminalShellState();

  String get text => utf8.decode(written);

  @override
  Stream<TerminalUpdate> get updates => controller.stream;

  @override
  void write(List<int> bytes) => written.addAll(bytes);

  @override
  void resize(int cols, int rows) => resizes.add((cols, rows));

  @override
  void ack() => acks++;

  @override
  TerminalShellState state() => current;

  @override
  Future<bool> changeDirectory(String folder) async {
    directories.add(folder);
    return changeAnswers;
  }

  @override
  Future<void> close() async {
    closed = true;
    unawaited(controller.close());
  }

  void emit(TerminalUpdate update) => controller.add(update);
}
