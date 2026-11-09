import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Repaints a listener's widget when its model changes, even mid-frame.
///
/// The app drives selection models from widget lifecycle hooks (a colour
/// preview starts in a popup's `initState` and ends in its `dispose`), so
/// a change can arrive while the tree is building or being torn down,
/// when `setState` is forbidden. The model still changes in call order;
/// only the repaint waits for the end of the frame.
mixin RepaintAfterBuild<T extends StatefulWidget> on State<T> {
  bool _repaintScheduled = false;

  void repaint() {
    if (!mounted) return;
    final binding = SchedulerBinding.instance;
    if (binding.schedulerPhase != SchedulerPhase.persistentCallbacks) {
      setState(() {});
      return;
    }
    if (_repaintScheduled) return;
    _repaintScheduled = true;
    binding.addPostFrameCallback((_) {
      _repaintScheduled = false;
      if (mounted) setState(() {});
    });
  }
}
