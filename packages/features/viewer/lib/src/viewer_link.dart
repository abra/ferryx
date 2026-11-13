import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

Future<void> showViewerLink(BuildContext context, String href) =>
    showAppDialog<void>(
      context,
      (context) => AppDialog(
        title: context.l10n.viewerLinkTitle,
        body: AppDialogScrollBody(child: SelectableText(href)),
        actions: [
          OutlinedButton(
            onPressed: () =>
                unawaited(Clipboard.setData(ClipboardData(text: href))),
            child: Text(context.l10n.actionCopy),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.actionDone),
          ),
        ],
      ),
    );

/// A document link with the application's keyboard and hint behaviour.
class ViewerLink extends StatelessWidget {
  const ViewerLink({
    required this.href,
    required this.label,
    this.style,
    this.child,
    this.onActivate,
    super.key,
  });
  final String href;
  final String label;
  final TextStyle? style;
  final Widget? child;
  final VoidCallback? onActivate;

  @override
  Widget build(BuildContext context) {
    void activate() => onActivate != null
        ? onActivate!()
        : unawaited(showViewerLink(context, href));
    return AppTooltip(
      message: href,
      child: HintTarget(
        onActivate: activate,
        child: TextButton(
          onPressed: activate,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: child ?? Text(label, style: style),
        ),
      ),
    );
  }
}
