import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:material_ui/material_ui.dart';

class PreviewSearchHit {
  const PreviewSearchHit(this.anchor, this.excerpt);
  final Object anchor;
  final String excerpt;
}

abstract interface class PreviewSearchTarget {
  Stream<List<PreviewSearchHit>> search(String query);
  Future<void> reveal(PreviewSearchHit hit);
}

/// Preview results are locations in rendered content, never byte offsets.
class PreviewSearchController extends ChangeNotifier {
  static const maxMatches = 1000;
  PreviewSearchTarget? _target;
  Object? _owner;
  StreamSubscription<List<PreviewSearchHit>>? _subscription;
  Future<void> _cancelling = Future.value();
  Timer? _debounce;
  int _generation = 0;
  bool _disposed = false;
  bool shown = false, loading = false, failed = false, capped = false;
  String query = '';
  List<PreviewSearchHit> hits = const [];
  int current = -1;

  void attach(Object owner, PreviewSearchTarget? target) {
    if (_disposed || identical(_owner, owner) && identical(_target, target)) {
      return;
    }
    _owner = owner;
    _target = target;
    _restart();
  }

  void detach(Object owner) {
    if (_disposed || !identical(owner, _owner)) return;
    _owner = null;
    _target = null;
    _restart();
  }

  void show() {
    shown = true;
    notifyListeners();
  }

  void hide() {
    shown = false;
    setQuery('');
  }

  void setQuery(String value) {
    query = value;
    _stop();
    hits = const [];
    current = -1;
    failed = false;
    capped = false;
    loading = value.trim().isNotEmpty && _target != null;
    notifyListeners();
    _debounce = Timer(const Duration(milliseconds: 180), _start);
  }

  void _restart() {
    _stop();
    hits = const [];
    current = -1;
    failed = false;
    capped = false;
    loading = query.trim().isNotEmpty && _target != null;
    notifyListeners();
    unawaited(_start());
  }

  void _stop() {
    _generation++;
    _debounce?.cancel();
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      _cancelling = Future.wait([_cancelling, subscription.cancel()]);
    }
  }

  Future<void> _start() async {
    final generation = _generation;
    final target = _target;
    await _cancelling;
    if (_disposed || generation != _generation || target == null) return;
    _subscription = target
        .search(query.trim())
        .listen(
          (batch) {
            if (_disposed || generation != _generation) return;
            final first = hits.isEmpty;
            final room = maxMatches - hits.length;
            capped = capped || batch.length > room;
            hits = List.unmodifiable([...hits, ...batch.take(room)]);
            if (first && hits.isNotEmpty) {
              current = 0;
              unawaited(_reveal(target, hits.first));
            }
            if (capped) {
              loading = false;
              final sub = _subscription;
              _subscription = null;
              if (sub != null) _cancelling = sub.cancel();
            }
            notifyListeners();
          },
          onError: (Object _, StackTrace _) {
            if (_disposed || generation != _generation) return;
            loading = false;
            failed = true;
            notifyListeners();
          },
          onDone: () {
            if (_disposed || generation != _generation) return;
            loading = false;
            notifyListeners();
          },
        );
  }

  void next(int delta) {
    if (!shown) {
      show();
      return;
    }
    if (hits.isEmpty) return;
    current = (current + delta) % hits.length;
    notifyListeners();
    final target = _target;
    if (target != null) unawaited(_reveal(target, hits[current]));
  }

  Future<void> _reveal(PreviewSearchTarget target, PreviewSearchHit hit) async {
    final generation = _generation;
    try {
      await target.reveal(hit);
    } on Object {
      if (!_disposed && generation == _generation) {
        failed = true;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _stop();
    super.dispose();
  }
}

class PreviewSearchScope extends InheritedWidget {
  const PreviewSearchScope({
    required this.controller,
    required super.child,
    super.key,
  });
  final PreviewSearchController controller;
  static PreviewSearchController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PreviewSearchScope>()
      ?.controller;
  @override
  bool updateShouldNotify(PreviewSearchScope oldWidget) =>
      controller != oldWidget.controller;
}

/// Binds only after layout; a document can finish opening during a build.
class PreviewSearchBinding extends StatefulWidget {
  const PreviewSearchBinding({
    required this.target,
    required this.child,
    super.key,
  });
  final PreviewSearchTarget? target;
  final Widget child;
  @override
  State<PreviewSearchBinding> createState() => _PreviewSearchBindingState();
}

class _PreviewSearchBindingState extends State<PreviewSearchBinding> {
  PreviewSearchController? _controller;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bind();
  }

  @override
  void didUpdateWidget(PreviewSearchBinding oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bind();
  }

  void _bind() {
    final controller = PreviewSearchScope.maybeOf(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_controller != controller) _controller?.detach(this);
      _controller = controller;
      controller?.attach(this, widget.target);
    });
  }

  @override
  void dispose() {
    final controller = _controller;
    // A mode change disposes during the parent's build.
    scheduleMicrotask(() => controller?.detach(this));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class PreviewFindBar extends StatefulWidget {
  const PreviewFindBar({
    required this.controller,
    required this.onClose,
    super.key,
  });
  final PreviewSearchController controller;
  final VoidCallback onClose;
  @override
  State<PreviewFindBar> createState() => _PreviewFindBarState();
}

class _PreviewFindBarState extends State<PreviewFindBar> {
  late final _text = TextEditingController(text: widget.controller.query);
  final _focus = FocusNode(debugLabel: 'preview search');
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final search = widget.controller;
      final l10n = context.l10n;
      final status = search.failed
          ? l10n.previewSearchFailed
          : search.loading
          ? l10n.previewSearching
          : search.hits.isEmpty
          ? l10n.viewerNoMatch
          : l10n.viewerMatches(search.current + 1, search.hits.length);
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: context.appColors.surfaceRaised,
          border: AppBorder(bottom: BorderSide(color: context.appColors.line)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              spacing: context.metrics.toolbarSpacing,
              children: [
                Expanded(
                  child: AppSearchField(
                    controller: _text,
                    focusNode: _focus,
                    hintText: l10n.viewerFindHint,
                    onChanged: search.setQuery,
                    onSubmitted: (_) => search.next(1),
                  ),
                ),
                AppIconButton(
                  icon: AppIcons.chevronUp,
                  tooltip: l10n.cmdViewerFindPrevious,
                  onPressed: search.hits.isEmpty ? null : () => search.next(-1),
                ),
                AppIconButton(
                  icon: AppIcons.chevronDown,
                  tooltip: l10n.cmdViewerFindNext,
                  onPressed: search.hits.isEmpty ? null : () => search.next(1),
                ),
                AppIconButton(
                  icon: AppIcons.close,
                  tooltip: l10n.actionClose,
                  onPressed: widget.onClose,
                ),
              ],
            ),
            if (search.query.isNotEmpty)
              Text(
                search.capped ? l10n.previewSearchCapped(status) : status,
                style: context.text.bodySmall,
              ),
            if (search.current >= 0)
              Text(
                search.hits[search.current].excerpt,
                style: context.text.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      );
    },
  );
}
