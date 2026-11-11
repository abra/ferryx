import 'dart:async';

import 'package:domain_models/domain_models.dart';
import 'package:flutter/widgets.dart';

/// Presentation ranges for the filesystem's date added to this folder.
enum RecentEntryAge {
  hour(Duration(hours: 1)),
  threeHours(Duration(hours: 3)),
  day(Duration(days: 1));

  const RecentEntryAge(this.upperBound);

  /// Exclusive upper age, shared by classification and clock scheduling.
  final Duration upperBound;
}

RecentEntryAge? recentEntryAge(FileEntry entry, DateTime now) {
  final added = entry.added;
  if (entry.isParent || added == null) return null;
  final age = now.difference(added);
  if (age.isNegative) return null;
  for (final range in RecentEntryAge.values) {
    if (age < range.upperBound) return range;
  }
  return null;
}

/// One clock for the visible rows. Entry timestamps are inspected only when
/// the listing changes. Boundary updates are batched to minute precision,
/// without reading the directory or rebuilding the panel's other controls.
class RecentEntriesClock extends StatefulWidget {
  const RecentEntriesClock({
    required this.entries,
    required this.child,
    this.now = DateTime.now,
    super.key,
  });

  final List<FileEntry> entries;
  final Widget child;
  final DateTime Function() now;

  static DateTime nowOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_RecentTime>()?.now ??
      DateTime.now();

  @override
  State<RecentEntriesClock> createState() => _RecentEntriesClockState();
}

class _RecentEntriesClockState extends State<RecentEntriesClock>
    with WidgetsBindingObserver {
  Timer? _timer;
  late DateTime _now;
  List<DateTime> _dates = const [];
  bool _suspended = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _readDates();
  }

  @override
  void didUpdateWidget(RecentEntriesClock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.entries, oldWidget.entries) ||
        widget.now != oldWidget.now) {
      _readDates();
    }
  }

  void _readDates() {
    _now = widget.now();
    _dates = [
      for (final entry in widget.entries)
        if (recentEntryAge(entry, _now) != null) entry.added!,
    ];
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (_suspended) return;
    DateTime? next;
    _dates.removeWhere(
      (date) => _now.difference(date) >= RecentEntryAge.day.upperBound,
    );
    for (final added in _dates) {
      final elapsed = _now.difference(added);
      final range = RecentEntryAge.values.firstWhere(
        (range) => elapsed < range.upperBound,
      );
      final deadline = added.add(range.upperBound);
      if (next == null || deadline.isBefore(next)) next = deadline;
    }
    if (next == null) return;
    const minute = Duration(minutes: 1);
    final delay = next.difference(_now).inMicroseconds;
    final minutes =
        (delay + minute.inMicroseconds - 1) ~/ minute.inMicroseconds;
    _timer = Timer(Duration(minutes: minutes), () {
      setState(() => _now = widget.now());
      _schedule();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _suspended = false;
      setState(_readDates);
    } else if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _suspended = true;
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _RecentTime(now: _now, child: widget.child);
}

class _RecentTime extends InheritedWidget {
  const _RecentTime({required this.now, required super.child});

  final DateTime now;

  @override
  bool updateShouldNotify(_RecentTime oldWidget) => now != oldWidget.now;
}
