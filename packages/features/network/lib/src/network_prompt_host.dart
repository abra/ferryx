import 'dart:async';
import 'dart:collection';

import 'package:domain_models/domain_models.dart';
import 'package:material_ui/material_ui.dart';
import 'package:network_service/network_service.dart';

import 'prompt_dialogs.dart';

/// Asks the user what connections ask, wherever they come from (Connect
/// to Server, a panel connecting again, an operation whose connection
/// dropped): one dialog at a time over [child], in order. A question
/// withdrawn (its connection given up) closes its dialog or leaves the
/// queue unasked; a dialog closed without an answer is a Cancel.
class NetworkPromptHost extends StatefulWidget {
  const NetworkPromptHost({
    required this.service,
    required this.child,
    super.key,
  });

  final NetworkService service;
  final Widget child;

  @override
  State<NetworkPromptHost> createState() => _NetworkPromptHostState();
}

class _NetworkPromptHostState extends State<NetworkPromptHost> {
  final _queue = Queue<NetworkQuestion>();
  final _withdrawn = ValueNotifier<Set<int>>(const {});
  final _subscriptions = <StreamSubscription<Object?>>[];
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    _subscriptions
      ..add(widget.service.questions.listen(_onQuestion))
      ..add(widget.service.withdrawn.listen(_onWithdrawn));
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _withdrawn.dispose();
    super.dispose();
  }

  void _onQuestion(NetworkQuestion question) {
    _queue.add(question);
    unawaited(_next());
  }

  void _onWithdrawn(int id) {
    _queue.removeWhere((q) => q.id == id);
    _withdrawn.value = {..._withdrawn.value, id};
  }

  Future<void> _next() async {
    if (_asking || _queue.isEmpty || !mounted) return;
    _asking = true;
    final question = _queue.removeFirst();
    try {
      final answer = await showNetworkQuestion(
        context,
        question,
        withdrawn: _withdrawn,
      );
      if (!_withdrawn.value.contains(question.id)) {
        widget.service.answer(
          question.id,
          answer ?? const NetworkAnswer.cancel(),
        );
      }
    } finally {
      _asking = false;
    }
    unawaited(_next());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
