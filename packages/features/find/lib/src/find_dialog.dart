import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:operations_service/operations_service.dart';
import 'package:preferences_service/preferences_service.dart';

import 'find_cubit.dart';
import 'find_results.dart';
import 'saved_searches.dart';

/// Find Files under [root]: a name mask, text the files hold, a size;
/// the hits as they come. Answers the path of a hit to go to, or `null`.
/// [onView] opens a hit in the viewer while the dialog stays. With
/// [spotlight] (the core says the desktop has the Spotlight index) the
/// form offers to search through it.
Future<String?> showFindDialog(
  BuildContext context, {
  required String root,
  required FindService find,
  required Future<void> Function(Location location) onView,
  bool spotlight = false,
  FindRequest? initial,
  SavedProfiles<FindRequest>? savedSearches,
  Future<void> Function(FindRequest request)? onResults,
}) async {
  FindRequest? panelRequest;
  final result = await showAppDialog<String>(
    context,
    (context) => BlocProvider(
      create: (_) => FindCubit(service: find),
      child: _FindDialog(
        root: root,
        onView: onView,
        spotlight: spotlight,
        initial: initial,
        savedSearches: savedSearches,
        onResults: onResults == null
            ? null
            : (request) {
                panelRequest = request;
                Navigator.of(context).pop();
              },
      ),
    ),
  );
  if (panelRequest != null && onResults != null) await onResults(panelRequest!);
  return result;
}

/// The size units the dialog offers, as multipliers of a byte.
const _units = [1, 1024, 1024 * 1024, 1024 * 1024 * 1024];

class _FindDialog extends StatefulWidget {
  const _FindDialog({
    required this.root,
    required this.onView,
    required this.spotlight,
    this.initial,
    this.savedSearches,
    this.onResults,
  });

  final String root;
  final Future<void> Function(Location location) onView;
  final bool spotlight;
  final FindRequest? initial;
  final SavedProfiles<FindRequest>? savedSearches;
  final ValueChanged<FindRequest>? onResults;

  @override
  State<_FindDialog> createState() => _FindDialogState();
}

class _FindDialogState extends State<_FindDialog> {
  late final TextEditingController _root = TextEditingController(
    text: widget.root,
  );
  final _name = TextEditingController();
  final _content = TextEditingController();
  final _sizeValue = TextEditingController();
  late final _nameFocus = FocusNode(
    debugLabel: 'find name',
    onKeyEvent: _downToHits,
  );
  late final _contentFocus = FocusNode(
    debugLabel: 'find content',
    onKeyEvent: _downToHits,
  );

  /// Asks the hit the keys rest on for the focus, each time it grows.
  int _focusHits = 0;
  bool _regex = false;
  bool _caseSensitive = false;
  bool _wholePhrase = true;
  bool _notContaining = false;
  SizeOp? _sizeOp;
  int _unit = _units[1];
  bool _includeHidden = false;
  bool _includeFolders = true;
  bool _useSpotlight = false;
  int? _modifiedWithinDays;

  /// The hit the keys or the pointer rest on.
  int? _selected;

  FindCubit get _cubit => context.read<FindCubit>();

  @override
  void initState() {
    super.initState();
    if (widget.initial case final request?) _apply(request);
  }

  void _apply(FindRequest request) {
    _root.text = request.root;
    _name.text = request.name;
    _content.text = request.content?.text ?? '';
    _regex = request.nameIsRegex;
    _caseSensitive = request.content?.caseSensitive ?? false;
    _wholePhrase = request.content?.wholePhrase ?? true;
    _notContaining = request.content?.notContaining ?? false;
    _sizeOp = request.size?.op;
    _unit = 1;
    _sizeValue.text = request.size?.bytes.toString() ?? '';
    _includeHidden = request.includeHidden;
    _useSpotlight = request.useSpotlight;
    _includeFolders = request.includeFolders;
    _modifiedWithinDays = request.modifiedWithinDays;
  }

  Future<void> _saved() async {
    final catalog = widget.savedSearches;
    if (catalog == null) return;
    final picked = await showSavedSearchesDialog(
      context,
      catalog: catalog,
      current: _request(),
    );
    if (!mounted || picked == null) return;
    setState(() => _apply(picked.value));
    await _start();
  }

  @override
  void dispose() {
    _root.dispose();
    _name.dispose();
    _content.dispose();
    _sizeValue.dispose();
    _nameFocus.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  /// ↓ in the name or the text field goes down into the hits, as from a
  /// search field into its list: the hit the keys rest on, else the first.
  KeyEventResult _downToHits(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent ||
        event.logicalKey != LogicalKeyboardKey.arrowDown ||
        _cubit.state.hits.isEmpty) {
      return KeyEventResult.ignored;
    }
    setState(() {
      _selected ??= 0;
      _focusHits++;
    });
    return KeyEventResult.handled;
  }

  FindRequest _request() {
    final content = _content.text;
    final size = int.tryParse(_sizeValue.text.trim());
    return FindRequest(
      root: _root.text.trim().isEmpty ? widget.root : _root.text.trim(),
      name: _name.text.trim(),
      nameIsRegex: _regex,
      content: content.isEmpty
          ? null
          : ContentQuery(
              text: content,
              caseSensitive: _caseSensitive,
              wholePhrase: _wholePhrase,
              notContaining: _notContaining,
            ),
      size: _sizeOp == null || size == null
          ? null
          : SizeCondition(op: _sizeOp!, bytes: size * _unit),
      includeHidden: _includeHidden,
      includeFolders: _includeFolders && content.isEmpty && _sizeOp == null,
      useSpotlight: widget.spotlight && _useSpotlight,
      modifiedWithinDays: _modifiedWithinDays,
    );
  }

  /// Starts the search over with what the form says now.
  Future<void> _start() async {
    setState(() => _selected = null);
    await _cubit.start(_request());
  }

  /// The button: starts, or stops a search under way.
  Future<void> _toggle() async {
    if (_cubit.state.running) {
      await _cubit.stop();
    } else {
      await _start();
    }
  }

  void _goTo(int index) {
    final hits = _cubit.state.hits;
    if (index < 0 || index >= hits.length) return;
    Navigator.of(context).pop(hits[index].path);
  }

  Future<void> _view(int index) async {
    final hits = _cubit.state.hits;
    if (index < 0 || index >= hits.length) return;
    await widget.onView(Location.native(hits[index].path));
  }

  Future<void> _rowMenu(int index, Rect anchor) async {
    final l10n = context.l10n;
    final picked = await showAppMenu<String>(
      context: context,
      anchor: anchor,
      entries: [
        AppMenuAction(
          value: 'go',
          label: l10n.findGoTo,
          icon: AppIcons.folderOpen,
        ),
        AppMenuAction(
          value: 'view',
          label: l10n.findView,
          icon: AppIcons.preview,
        ),
      ],
    );
    if (!mounted) return;
    switch (picked) {
      case 'go':
        _goTo(index);
      case 'view':
        await _view(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocConsumer<FindCubit, FindState>(
      listenWhen: (before, after) =>
          after.spotlightFailed && !before.spotlightFailed,
      listener: (context, state) =>
          showAppNotice(context, l10n.findSpotlightFailed),
      builder: (context, state) {
        final hasSelection =
            _selected != null && _selected! < state.hits.length;
        return AppDialog(
          title: l10n.findTitle,
          width: AppSizes.panelDialogWidth,
          body: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Form(
                root: _root,
                name: _name,
                nameFocus: _nameFocus,
                contentFocus: _contentFocus,
                content: _content,
                sizeValue: _sizeValue,
                regex: _regex,
                caseSensitive: _caseSensitive,
                wholePhrase: _wholePhrase,
                notContaining: _notContaining,
                sizeOp: _sizeOp,
                unit: _unit,
                includeHidden: _includeHidden,
                includeFolders: _includeFolders,
                onIncludeFolders: (value) =>
                    setState(() => _includeFolders = value),
                spotlight: widget.spotlight,
                useSpotlight: _useSpotlight,
                onUseSpotlight: (v) => setState(() => _useSpotlight = v),
                onRegex: (v) => setState(() => _regex = v),
                onCaseSensitive: (v) => setState(() => _caseSensitive = v),
                onWholePhrase: (v) => setState(() => _wholePhrase = v),
                onNotContaining: (v) => setState(() => _notContaining = v),
                onSizeOp: (v) => setState(() => _sizeOp = v),
                onUnit: (v) => setState(() => _unit = v),
                onIncludeHidden: (v) => setState(() => _includeHidden = v),
                onSubmit: () => unawaited(_start()),
                modifiedWithinDays: _modifiedWithinDays,
                onModifiedWithinDays: (days) =>
                    setState(() => _modifiedWithinDays = days),
              ),
              const SizedBox(height: AppSpacing.md),
              Flexible(
                child: FindResults(
                  state: state,
                  selected: _selected,
                  focusRequest: _focusHits,
                  onSelect: (index) => setState(() => _selected = index),
                  onGoTo: _goTo,
                  onMenu: (index, anchor) => unawaited(_rowMenu(index, anchor)),
                ),
              ),
            ],
          ),
          // Find (or Stop) is the default; Return in a field starts the
          // search over, never stops it.
          actions: [
            if (widget.savedSearches != null)
              OutlinedButton(
                onPressed: () => unawaited(_saved()),
                child: Text(l10n.savedSearchesTitle),
              ),
            if (widget.onResults case final onResults?)
              OutlinedButton(
                onPressed: () => onResults(_request()),
                child: Text(l10n.searchOpenTab),
              ),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.actionClose),
            ),
            OutlinedButton(
              onPressed: hasSelection
                  ? () => unawaited(_view(_selected!))
                  : null,
              child: Text(l10n.findView),
            ),
            OutlinedButton(
              onPressed: hasSelection ? () => _goTo(_selected!) : null,
              child: Text(l10n.findGoTo),
            ),
            FilledButton.icon(
              onPressed: () => unawaited(_toggle()),
              icon: Icon(
                state.running ? AppIcons.cancel : AppIcons.search,
                size: AppIconSize.sm,
              ),
              label: Text(state.running ? l10n.findStop : l10n.findStart),
            ),
          ],
        );
      },
    );
  }
}

/// The conditions: the folder, the name, the contents, the size.
class _Form extends StatelessWidget {
  const _Form({
    required this.root,
    required this.name,
    required this.nameFocus,
    required this.contentFocus,
    required this.content,
    required this.sizeValue,
    required this.regex,
    required this.caseSensitive,
    required this.wholePhrase,
    required this.notContaining,
    required this.sizeOp,
    required this.unit,
    required this.includeHidden,
    required this.includeFolders,
    required this.onIncludeFolders,
    required this.spotlight,
    required this.useSpotlight,
    required this.onUseSpotlight,
    required this.onRegex,
    required this.onCaseSensitive,
    required this.onWholePhrase,
    required this.onNotContaining,
    required this.onSizeOp,
    required this.onUnit,
    required this.onIncludeHidden,
    required this.onSubmit,
    required this.modifiedWithinDays,
    required this.onModifiedWithinDays,
  });

  final TextEditingController root;
  final TextEditingController name;
  final FocusNode nameFocus;
  final FocusNode contentFocus;
  final TextEditingController content;
  final TextEditingController sizeValue;
  final bool regex;
  final bool caseSensitive;
  final bool wholePhrase;
  final bool notContaining;
  final SizeOp? sizeOp;
  final int unit;
  final bool includeHidden;
  final bool includeFolders;
  final ValueChanged<bool> onIncludeFolders;

  /// The desktop has the Spotlight index: the option shows.
  final bool spotlight;
  final bool useSpotlight;
  final ValueChanged<bool> onUseSpotlight;
  final ValueChanged<bool> onRegex;
  final ValueChanged<bool> onCaseSensitive;
  final ValueChanged<bool> onWholePhrase;
  final ValueChanged<bool> onNotContaining;
  final ValueChanged<SizeOp?> onSizeOp;
  final ValueChanged<int> onUnit;
  final ValueChanged<bool> onIncludeHidden;
  final VoidCallback onSubmit;
  final int? modifiedWithinDays;
  final ValueChanged<int?> onModifiedWithinDays;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldWithOption(
          field: _Field(
            label: l10n.findIn,
            controller: root,
            monospace: true,
            onSubmitted: onSubmit,
          ),
          option: AppCheckbox(
            label: l10n.findIncludeHidden,
            value: includeHidden,
            onChanged: onIncludeHidden,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _FieldWithOption(
          field: _Field(
            label: l10n.findName,
            hint: l10n.findNameHint,
            controller: name,
            focusNode: nameFocus,
            autofocus: true,
            monospace: true,
            onSubmitted: onSubmit,
          ),
          option: AppCheckbox(
            label: l10n.findRegex,
            value: regex,
            onChanged: onRegex,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _Field(
          label: l10n.findContent,
          controller: content,
          focusNode: contentFocus,
          onSubmitted: onSubmit,
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.sm,
          children: [
            AppCheckbox(
              label: l10n.findIncludeFolders,
              value: includeFolders,
              onChanged: onIncludeFolders,
            ),
            AppCheckbox(
              label: l10n.findCaseSensitive,
              value: caseSensitive,
              onChanged: onCaseSensitive,
            ),
            AppCheckbox(
              label: l10n.findWholePhrase,
              value: wholePhrase,
              onChanged: onWholePhrase,
            ),
            AppCheckbox(
              label: l10n.findNotContaining,
              value: notContaining,
              onChanged: onNotContaining,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          spacing: context.metrics.toolbarSpacing,
          children: [
            Text(l10n.findSize, style: context.text.labelMedium),
            AppPopupButton<SizeOp?>(
              value: sizeOp,
              items: [
                (null, l10n.findSizeAny),
                (SizeOp.less, l10n.findSizeLess),
                (SizeOp.equal, l10n.findSizeEqual),
                (SizeOp.greater, l10n.findSizeGreater),
              ],
              onChanged: onSizeOp,
            ),
            SizedBox(
              width: AppSizes.settingsNumberFieldWidth,
              child: AppTextField(
                controller: sizeValue,
                enabled: sizeOp != null,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.end,
                onSubmitted: (_) => onSubmit(),
              ),
            ),
            AppPopupButton<int>(
              value: unit,
              enabled: sizeOp != null,
              items: [
                (_units[0], l10n.findUnitBytes),
                (_units[1], l10n.findUnitKilobytes),
                (_units[2], l10n.findUnitMegabytes),
                (_units[3], l10n.findUnitGigabytes),
              ],
              onChanged: onUnit,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        AppControlRow(
          label: l10n.findModified,
          control: AppPopupButton<int?>(
            value: modifiedWithinDays,
            items: [
              (null, l10n.findSizeAny),
              for (final days in {1, 7, 30, 365, ?modifiedWithinDays})
                (days, l10n.findModifiedDays(days)),
            ],
            onChanged: onModifiedWithinDays,
          ),
        ),
        if (spotlight) ...[
          const SizedBox(height: AppSpacing.md),
          _SpotlightOption(value: useSpotlight, onChanged: onUseSpotlight),
        ],
      ],
    );
  }
}

/// "Use the Spotlight index", and what Spotlight does not see.
class _SpotlightOption extends StatelessWidget {
  const _SpotlightOption({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCheckbox(
          label: l10n.findSpotlight,
          value: value,
          onChanged: onChanged,
        ),
        const SizedBox(height: AppSpacing.xxs),
        // Under the label, as a check box's note stands.
        Padding(
          padding: EdgeInsetsDirectional.only(
            start: checkboxExtent(context) + AppSpacing.sm,
          ),
          child: Text(
            l10n.findSpotlightNote,
            style: context.text.bodySmall?.copyWith(
              color: context.appColors.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}

/// A field with an option beside its box: the option sits level with the
/// box, under the field's label, by sharing the box's height at the end
/// of the row.
class _FieldWithOption extends StatelessWidget {
  const _FieldWithOption({required this.field, required this.option});

  final Widget field;
  final Widget option;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(child: field),
      const SizedBox(width: AppSpacing.lg),
      SizedBox(
        height: context.metrics.controlHeight,
        child: Row(mainAxisSize: MainAxisSize.min, children: [option]),
      ),
    ],
  );
}

/// A labelled field of the form; Return starts the search.
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.onSubmitted,
    this.hint,
    this.focusNode,
    this.autofocus = false,
    this.monospace = false,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onSubmitted;
  final String? hint;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool monospace;

  @override
  Widget build(BuildContext context) => AppFormField(
    label: label,
    child: AppTextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      monospace: monospace,
      hintText: hint,
      onSubmitted: (_) => onSubmitted(),
    ),
  );
}
