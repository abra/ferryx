import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'app_dialog.dart';
import 'app_form_field.dart';
import 'app_row_list.dart';
import 'app_middle_ellipsis.dart';
import 'app_text_field.dart';
import 'theme/extensions/build_context_ext.dart';
import 'theme/tokens/app_sizes.dart';
import 'theme/tokens/app_spacing.dart';

class AppNamedItem {
  const AppNamedItem(this.name, {this.detail});
  final String name;
  final String? detail;
}

class AppNamedItemsLabels {
  const AppNamedItemsLabels({
    required this.title,
    required this.name,
    required this.empty,
    required this.create,
    required this.update,
    required this.rename,
    required this.remove,
    required this.open,
    required this.close,
    required this.failure,
  });
  final String title, name, empty, create, update, rename, remove, open, close;
  final String failure;
}

/// A named collection editor with explicit create, replace, rename and remove
/// actions. Persistence and name validation stay with its caller.
class AppNamedItemsDialog extends StatefulWidget {
  const AppNamedItemsDialog({
    required this.items,
    required this.labels,
    required this.validateName,
    this.onCreate,
    required this.onRename,
    required this.onRemove,
    this.onUpdate,
    this.onError,
    super.key,
  });
  final List<AppNamedItem> items;
  final AppNamedItemsLabels labels;
  final String? Function(String name, String? replacing) validateName;
  final Future<void> Function(String name)? onCreate;
  final Future<void> Function(String name, String replacement) onRename;
  final Future<void> Function(String name) onRemove;
  final Future<void> Function(String name)? onUpdate;
  final void Function(Object, StackTrace)? onError;

  @override
  State<AppNamedItemsDialog> createState() => _AppNamedItemsDialogState();
}

class _AppNamedItemsDialogState extends State<AppNamedItemsDialog> {
  late final _rows = AppRowListController(widget.items.length)
    ..addListener(_selectionChanged);
  final _name = TextEditingController();
  String? _selected;
  String? _error;
  bool _busy = false;

  @override
  void didUpdateWidget(AppNamedItemsDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selected != null &&
        !widget.items.any((item) => item.name == _selected)) {
      _selected = null;
    }
    _rows.count = widget.items.length;
  }

  void _selectionChanged() {
    if (_rows.lead < 0) return;
    final item = widget.items.elementAtOrNull(_rows.lead);
    if (item == null || _busy) return;
    setState(() {
      _selected = item.name;
      _name.text = item.name;
      _error = null;
    });
  }

  Future<void> _change(Future<void> Function() change) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await change();
    } catch (error, stack) {
      widget.onError?.call(error, stack);
      if (mounted) setState(() => _error = widget.labels.failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _saveName({required bool rename}) {
    final name = _name.text.trim();
    final selected = _selected;
    final error = widget.validateName(name, rename ? selected : null);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    unawaited(
      _change(() async {
        if (rename && selected != null) {
          await widget.onRename(selected, name);
        } else {
          await widget.onCreate?.call(name);
        }
        if (mounted) setState(() => _selected = name);
      }),
    );
  }

  @override
  void dispose() {
    _rows.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final labels = widget.labels;
    final selected = _selected;
    return AppDialog(
      title: labels.title,
      width: AppSizes.panelDialogWidth,
      body: AppDialogScrollBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: AppSizes.pickerListMaxHeight,
              child: AppRowList(
                controller: _rows,
                autofocus: true,
                itemExtent: AppRowList.extentOf(context),
                empty: Center(child: Text(labels.empty)),
                onActivate: _busy
                    ? null
                    : (index) =>
                          Navigator.of(context).pop(widget.items[index].name),
                itemBuilder: (context, index, state) => Row(
                  children: [
                    Expanded(
                      child: AppMiddleEllipsis(
                        widget.items[index].name,
                        style: DefaultTextStyle.of(context).style,
                      ),
                    ),
                    if (widget.items[index].detail case final detail?) ...[
                      const SizedBox(width: AppSpacing.md),
                      Flexible(
                        child: AppMiddleEllipsis(
                          detail,
                          style: context.text.bodySmall!.copyWith(
                            color: context.appColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppFormField(
              label: labels.name,
              child: AppTextField(
                controller: _name,
                readOnly: _busy,
                errorText: _error,
                onChanged: (_) => setState(() => _error = null),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: context.metrics.toolbarSpacing,
              runSpacing: context.metrics.toolbarSpacing,
              children: [
                OutlinedButton(
                  onPressed: _busy || widget.onCreate == null
                      ? null
                      : () => _saveName(rename: false),
                  child: Text(labels.create),
                ),
                if (widget.onUpdate case final update?)
                  OutlinedButton(
                    onPressed: _busy || selected == null
                        ? null
                        : () => _change(() => update(selected)),
                    child: Text(labels.update),
                  ),
                OutlinedButton(
                  onPressed: _busy || selected == null
                      ? null
                      : () => _saveName(rename: true),
                  child: Text(labels.rename),
                ),
                OutlinedButton(
                  onPressed: _busy || selected == null
                      ? null
                      : () => _change(() => widget.onRemove(selected)),
                  child: Text(labels.remove),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(labels.close),
        ),
        FilledButton(
          onPressed: _busy || selected == null
              ? null
              : () => Navigator.of(context).pop(selected),
          child: Text(labels.open),
        ),
      ],
    );
  }
}
