import 'dart:async';

import 'package:flutter/widgets.dart';

import 'preferences.dart';
import 'preferences_service.dart';

/// Builds from one value of the preferences ([select]), and again only when
/// that value changes: a view far from the settings follows one choice
/// (the PDF keys panel) without being rebuilt by every other one, as a
/// dependency on [PreferencesScope] would.
class PreferenceBuilder<T> extends StatefulWidget {
  const PreferenceBuilder({
    required this.service,
    required this.select,
    required this.builder,
    super.key,
  });

  final PreferencesService service;
  final T Function(Preferences preferences) select;
  final Widget Function(BuildContext context, T value) builder;

  @override
  State<PreferenceBuilder<T>> createState() => _PreferenceBuilderState<T>();
}

class _PreferenceBuilderState<T> extends State<PreferenceBuilder<T>> {
  late T _value = widget.select(widget.service.current);
  StreamSubscription<Preferences>? _subscription;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(PreferenceBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.service, widget.service)) {
      _value = widget.select(widget.service.current);
      _listen();
    }
  }

  void _listen() {
    _subscription?.cancel();
    _subscription = widget.service.stream.listen((next) {
      final value = widget.select(next);
      if (value != _value && mounted) setState(() => _value = value);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}
