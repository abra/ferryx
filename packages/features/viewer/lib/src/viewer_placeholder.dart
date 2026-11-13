import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shortcuts/shortcuts.dart';

import 'viewer_footer.dart';

/// Keeps preview navigation available when the file cursor is on a folder.
class ViewerPlaceholder extends StatefulWidget {
  const ViewerPlaceholder({
    required this.focusScope,
    required this.shortcutMap,
    required this.windowDecor,
    required this.fullWindow,
    required this.onClose,
    required this.onFocusFiles,
    required this.onToggleFullWindow,
    super.key,
  });

  final FocusScopeNode focusScope;
  final ShortcutMap shortcutMap;
  final WindowDecor windowDecor;
  final bool fullWindow;
  final VoidCallback onClose;
  final VoidCallback onFocusFiles;
  final VoidCallback onToggleFullWindow;

  @override
  State<ViewerPlaceholder> createState() => _ViewerPlaceholderState();
}

class _ViewerPlaceholderState extends State<ViewerPlaceholder> {
  final _focus = FocusNode(debugLabel: 'empty preview');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final decor = widget.windowDecor;
    return FocusScope(
      node: widget.focusScope,
      onFocusChange: (focused) {
        if (focused && widget.focusScope.hasPrimaryFocus) _focus.requestFocus();
      },
      child: CommandShortcuts(
        shortcuts: {
          ...widget.shortcutMap.toShortcuts(
            context.platform,
            scopes: const {CommandScope.viewer, CommandScope.dialogs},
          ),
          for (final chord in widget.shortcutMap.chordsFor(
            AppCommand.switchPanel,
          ))
            chord.toShortcutActivator(context.platform): const CommandIntent(
              AppCommand.switchPanel,
            ),
        },
        child: CommandHandlers(
          handlers: {
            AppCommand.dismiss: widget.onClose,
            AppCommand.switchPanel: widget.onFocusFiles,
            AppCommand.viewerToggleFullWindow: widget.onToggleFullWindow,
          },
          child: Focus(
            focusNode: _focus,
            child: Material(
              color: context.colors.surface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  decor.dragArea(
                    Container(
                      height: context.metrics.topBarHeight,
                      decoration: BoxDecoration(
                        color: context.appColors.windowChrome,
                        border: AppBorder(
                          bottom: BorderSide(color: context.appColors.line),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                      ),
                      child: AppTopBarRow(
                        leftInset: decor.leadingInset,
                        rightInset: decor.trailingInset,
                        title: Text(
                          l10n.viewerModePreview,
                          style: context.text.titleSmall,
                        ),
                        forms: const [[]],
                        trailing: [
                          AppIconButton(
                            icon: widget.fullWindow
                                ? AppIcons.dualPane
                                : AppIcons.fillWindow,
                            tooltip: widget.fullWindow
                                ? l10n.viewerAdjacent
                                : l10n.viewerExpand,
                            onPressed: widget.onToggleFullWindow,
                          ),
                          AppIconButton(
                            icon: AppIcons.close,
                            tooltip: l10n.actionClose,
                            shortcut: widget.shortcutMap.labelOf(
                              AppCommand.dismiss,
                              context.platform,
                            ),
                            onPressed: widget.onClose,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: AppEmptyState(
                      title: l10n.viewerSelectFile,
                      icon: AppIcons.file,
                    ),
                  ),
                  ViewerFooter(
                    status: l10n.viewerModePreview,
                    shortcutMap: widget.shortcutMap,
                    showFiles: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
