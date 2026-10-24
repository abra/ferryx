import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'app_identity.dart';
import 'focus_ring.dart';
import 'pixel_snap.dart';
import 'popup_focus.dart';

import 'theme/app_button_styles.dart';
import 'theme/app_platform_style.dart';
import 'theme/extensions/build_context_ext.dart';
import 'theme/tokens/app_sizes.dart';
import 'theme/tokens/app_spacing.dart';
import 'theme/hairlines.dart';

/// Dialog shell in the platform's form: a macOS alert or sheet, a Fluent
/// ContentDialog with its footer band, a libadwaita alert. Return runs the
/// default action (the last of [actions]) whatever has the focus, as the
/// platforms' default button works; Space presses the focused control;
/// Esc and ⌘. dismiss. A field keeps Return for its own submit. When
/// nothing else asks for the focus, the default action holds it.
///
/// Pass [actions] dismissive first, affirmative last, which is the order
/// macOS and GNOME show; on Windows the dialog puts the affirmative first,
/// as Fluent's do. [alert] is a short question with no form (a centred
/// layout on macOS and GNOME). A [destructive] affirmative is never the
/// default: Return goes to the dismissive action instead.
class AppDialog extends StatelessWidget {
  const AppDialog({
    required this.title,
    required this.actions,
    this.body,
    this.width = AppSizes.dialogWidth,
    this.alert = false,
    this.destructive = false,
    super.key,
  });

  final String title;
  final Widget? body;
  final List<Widget> actions;
  final double width;
  final bool alert;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final style = context.metrics.style;
    final radius = context.metrics.radius;
    final themed = DialogTheme.of(context).shape;
    final shape = switch (themed) {
      final RoundedRectangleBorder shape when alert => shape.copyWith(
        borderRadius: BorderRadius.circular(radius.alert),
      ),
      _ => themed,
    };
    return Dialog(
      // The content is clipped inside the edge, not the dialog as a whole:
      // the dialog's own clip would take its edge away with the content.
      clipBehavior: Clip.none,
      shape: shape,
      // The platform's narrowest: NSAlert 260, ContentDialog 320,
      // AdwAlertDialog 300 (Material's 280 otherwise).
      constraints: BoxConstraints(
        minWidth: switch (style) {
          AppPlatformStyle.macos => alert ? 260 : 280,
          AppPlatformStyle.windows => 320,
          AppPlatformStyle.gnome => alert ? 300 : 280,
        },
      ),
      // On whole pixels, so the edge, the fill and the clip agree.
      child: CentredOnPixels(
        child: ClipInsideEdge(
          shape: shape,
          child: _DialogKeys(
            actions: actions,
            destructive: destructive,
            child: PixelSnap(
              child: switch (style) {
                AppPlatformStyle.macos => _Standard(
                  dialog: this,
                  centered: alert,
                  // NSAlert on macOS 15: 260 wide, the app's icon 20 from the
                  // top, its buttons large, 12 apart and 18 in, 16 from the
                  // bottom; a sheet's content 20 in, its buttons 12 apart.
                  maxWidth: alert ? 260 : width,
                  icon: alert ? AppIdentity.iconOf(context) : null,
                  padding: alert
                      ? const EdgeInsets.fromLTRB(18, 20, 18, 16)
                      : EdgeInsets.all(context.metrics.contentMargin),
                  titleStyle: context.text.titleSmall,
                  bodyStyle: alert
                      ? context.text.bodySmall
                      : context.text.bodyMedium,
                  bodyColor: context.colors.onSurface,
                  stretchActions: alert,
                  actionGap: AppSpacing.md,
                  actionHeight: alert
                      ? context.metrics.controlHeightLarge
                      : null,
                ),
                AppPlatformStyle.windows => _ContentDialog(dialog: this),
                AppPlatformStyle.gnome => _Standard(
                  dialog: this,
                  centered: alert,
                  // AdwAlertDialog: 300–372 wide, its buttons 44 high, 12 apart.
                  maxWidth: alert ? 372 : width,
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                  titleStyle: alert
                      ? context.text.titleLarge
                      : context.text.titleMedium,
                  bodyStyle: context.text.bodyMedium,
                  bodyColor: context.appColors.textMuted,
                  stretchActions: alert,
                  actionGap: AppSpacing.md,
                  actionHeight: alert
                      ? context.metrics.controlHeightLarge
                      : null,
                ),
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Asks for one line of text; resolves to the trimmed value, or `null`
  /// when cancelled or left empty. The dialog owns its controller, so the
  /// closing animation never touches a disposed one.
  static Future<String?> prompt(
    BuildContext context, {
    required String title,
    required String confirmLabel,
    required String cancelLabel,
    String initialValue = '',
  }) => _showReturningSelection<String>(
    context,
    (context) => _PromptDialog(
      title: title,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      initialValue: initialValue,
    ),
  );

  /// Shows a yes/no question; resolves to `true` on confirm. A
  /// [destructive] action is an [AppDestructiveButton].
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String confirmLabel,
    required String cancelLabel,
    String? message,
    bool destructive = false,
  }) async {
    final result = await _showReturningSelection<bool>(
      context,
      (context) {
        void confirm() => Navigator.of(context).pop(true);
        final Widget affirmative = !destructive
            ? FilledButton(onPressed: confirm, child: Text(confirmLabel))
            : AppDestructiveButton(label: confirmLabel, onPressed: confirm);
        return AppDialog(
          title: title,
          alert: true,
          destructive: destructive,
          body: message == null ? null : Text(message),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(cancelLabel),
            ),
            affirmative,
          ],
        );
      },
    );
    return result ?? false;
  }
}

/// The affirmative action of a [AppDialog.destructive] dialog, read as one
/// the platform's way: red text on macOS, Fluent's accent button on
/// Windows (it has no red button), the red destructive button on GNOME.
/// Never the default: Return goes to the dismissive action.
class AppDestructiveButton extends StatelessWidget {
  const AppDestructiveButton({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return switch (context.metrics.style) {
      AppPlatformStyle.macos => OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(foregroundColor: colors.danger),
        child: Text(label),
      ),
      AppPlatformStyle.windows => FilledButton(
        onPressed: onPressed,
        child: Text(label),
      ),
      AppPlatformStyle.gnome => FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: colors.danger,
          foregroundColor: Colors.white,
        ),
        child: Text(label),
      ),
    };
  }
}

/// macOS and GNOME: title, body and the actions in one column; centred
/// with full-width buttons for alerts, left-aligned with trailing buttons
/// for forms.
class _Standard extends StatelessWidget {
  const _Standard({
    required this.dialog,
    required this.centered,
    required this.maxWidth,
    required this.padding,
    required this.titleStyle,
    required this.bodyStyle,
    required this.bodyColor,
    required this.stretchActions,
    required this.actionGap,
    this.actionHeight,
    this.icon,
  });

  final AppDialog dialog;

  /// Above the title, 64 square: a macOS alert's app icon.
  final ImageProvider? icon;
  final bool centered;
  final double maxWidth;
  final EdgeInsets padding;
  final TextStyle? titleStyle;
  final TextStyle? bodyStyle;
  final Color bodyColor;
  final bool stretchActions;
  final double actionGap;

  /// An alert's buttons: the platform's large size.
  final double? actionHeight;

  @override
  Widget build(BuildContext context) {
    final align = centered ? TextAlign.center : TextAlign.start;
    final actions = dialog.actions;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (icon case final icon?) ...[
              Center(
                child: Image(
                  image: icon,
                  width: 64,
                  height: 64,
                  filterQuality: FilterQuality.medium,
                  excludeFromSemantics: true,
                ),
              ),
              SizedBox(height: context.metrics.contentMargin),
            ],
            Text(dialog.title, style: titleStyle, textAlign: align),
            if (dialog.body != null) ...[
              const SizedBox(height: AppSpacing.sm),
              DefaultTextStyle.merge(
                style: bodyStyle?.copyWith(color: bodyColor),
                textAlign: align,
                child: dialog.body!,
              ),
            ],
            SizedBox(
              height: centered ? AppSpacing.lg : context.metrics.contentMargin,
            ),
            if (stretchActions && actions.length <= 2)
              _AlertActionShape(
                child: _AlertButtons(
                  gap: actionGap,
                  children: [
                    for (final action in actions)
                      _TallAction(minHeight: actionHeight, child: action),
                  ],
                ),
              )
            else if (stretchActions)
              _AlertActionShape(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = actions.length - 1; i >= 0; i--) ...[
                      if (i < actions.length - 1) SizedBox(height: actionGap),
                      _TallAction(minHeight: actionHeight, child: actions[i]),
                    ],
                  ],
                ),
              )
            else
              // More buttons than the width takes go to a row above, the
              // default (the last) staying at the end.
              Wrap(
                alignment: WrapAlignment.end,
                spacing: actionGap,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final action in actions)
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: AppSizes.dialogButtonMinWidth,
                      ),
                      child: action,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// An alert's button: the platform's large height at least ([minHeight]),
/// taller as its label grows with the text size.
class _TallAction extends StatelessWidget {
  const _TallAction({required this.minHeight, required this.child});

  /// `null`: the button's own height.
  final double? minHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) => switch (minHeight) {
    null => child,
    final height => ConstrainedBox(
      constraints: BoxConstraints(minHeight: height),
      child: child,
    ),
  };
}

/// Fluent's ContentDialog: the content on the surface, the buttons on a
/// footer band in the window colour, equal widths, affirmative first.
class _ContentDialog extends StatelessWidget {
  const _ContentDialog({required this.dialog});

  final AppDialog dialog;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final actions = dialog.actions.reversed.toList(growable: false);
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: 320,
        maxWidth: dialog.width.clamp(320, 548).toDouble(),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(dialog.title, style: context.text.titleLarge),
                if (dialog.body != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  DefaultTextStyle.merge(
                    style: context.text.bodyMedium,
                    child: dialog.body!,
                  ),
                ],
              ],
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.window,
              border: AppBorder(top: BorderSide(color: colors.line)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Row(
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: AppSpacing.sm),
                    Expanded(child: actions[i]),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens the dialog [builder] makes the platform's way: the theme's
/// barrier, no dismissal by a click beside it (a sheet stays until a
/// button or Esc), and the focus back where it was once it closes. The
/// dialog's own keys (Return, Esc, ⌘.) come from [AppDialog].
Future<T?> showAppDialog<T>(
  BuildContext context,
  WidgetBuilder builder, {
  bool dismissible = false,
}) => pushReturningFocus(
  context,
  DialogRoute<T>(
    context: context,
    builder: builder,
    barrierDismissible: dismissible,
    barrierColor: DialogTheme.of(context).barrierColor,
  ),
);

/// [showDialog], then the focus back where it was with a text field's
/// selection as it was ([focusWithSelection]): the navigator's own return
/// would leave a single-line field all selected.
Future<T?> _showReturningSelection<T>(
  BuildContext context,
  WidgetBuilder builder,
) async {
  final opener = FocusManager.instance.primaryFocus;
  final value = fieldValueOf(opener);
  final result = await showDialog<T>(context: context, builder: builder);
  if (opener != null &&
      opener.context?.mounted == true &&
      opener.canRequestFocus) {
    focusWithSelection(opener, value?.selection, text: value?.text);
  }
  return result;
}

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.title,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.initialValue,
  });

  final String title;
  final String confirmLabel;
  final String cancelLabel;
  final String initialValue;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    Navigator.of(context).pop(value.isEmpty ? null : value);
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    title: widget.title,
    width: AppSizes.compactDialogWidth,
    body: TextField(
      controller: _controller,
      autofocus: true,
      onEditingComplete: () {},
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      OutlinedButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(widget.cancelLabel),
      ),
      FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
    ],
  );
}

/// Rounds the push buttons under it by the platform's alert buttons'
/// radius (AdwAlertDialog's are rounder than its other buttons).
class _AlertActionShape extends StatelessWidget {
  const _AlertActionShape({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final radius = metrics.radius;
    final mac = metrics.style == AppPlatformStyle.macos;
    if (!mac && radius.alertAction == radius.control) return child;
    final theme = Theme.of(context);
    final shape = FocusRing.ringedShape(
      AppRoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius.alertAction),
        insetFill: true,
      ),
      FocusRing.ringOf(metrics, context.appColors, theme.colorScheme.surface),
    );
    // NSAlert's buttons keep 8 beside their labels, so "Move to Trash"
    // still fits beside "Cancel" in 260.
    final padding = mac
        ? WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppButtonStyles.labelRoom(context),
            ),
          )
        : null;
    ButtonStyle? rounded(ButtonStyle? style) =>
        style?.copyWith(shape: shape, padding: padding);
    final colors = context.appColors;
    // A macOS alert's other buttons are grey plates, without a bezel.
    final plate = theme.brightness == Brightness.dark
        ? colors.controlFill
        : Colors.black.withValues(alpha: 0.12);
    final outlined = mac
        ? rounded(theme.outlinedButtonTheme.style)?.copyWith(
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.disabled)
                  ? plate.withValues(alpha: plate.a / 2)
                  : plate,
            ),
            side: const WidgetStatePropertyAll(BorderSide.none),
          )
        : rounded(theme.outlinedButtonTheme.style);
    return Theme(
      data: theme.copyWith(
        filledButtonTheme: FilledButtonThemeData(
          style: rounded(theme.filledButtonTheme.style),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(style: outlined),
        textButtonTheme: TextButtonThemeData(
          style: rounded(theme.textButtonTheme.style),
        ),
      ),
      child: child,
    );
  }
}

/// An alert's one or two buttons as NSAlert sets them: side by side and
/// equally wide while both labels fit so, else one above the other, the
/// last (the default) on top, each the alert's width.
class _AlertButtons extends MultiChildRenderObjectWidget {
  const _AlertButtons({required this.gap, required super.children});

  final double gap;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderAlertButtons(gap: gap);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderAlertButtons renderObject,
  ) => renderObject.gap = gap;
}

class _AlertButtonsData extends ContainerBoxParentData<RenderBox> {}

class _RenderAlertButtons extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _AlertButtonsData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _AlertButtonsData> {
  _RenderAlertButtons({required this._gap});

  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _AlertButtonsData) {
      child.parentData = _AlertButtonsData();
    }
  }

  List<RenderBox> get _buttons {
    final out = <RenderBox>[];
    var child = firstChild;
    while (child != null) {
      out.add(child);
      child = childAfter(child);
    }
    return out;
  }

  @override
  void performLayout() {
    final buttons = _buttons;
    final width = constraints.maxWidth;
    final share = (width - _gap * (buttons.length - 1)) / buttons.length;
    // No slack: a label a fraction of a pixel wider than its share wraps.
    final fits = buttons.every(
      (b) => b.getMaxIntrinsicWidth(double.infinity) <= share + 1e-9,
    );
    if (fits) {
      var x = 0.0;
      var height = 0.0;
      for (final b in buttons) {
        b.layout(BoxConstraints.tightFor(width: share), parentUsesSize: true);
        (b.parentData! as _AlertButtonsData).offset = Offset(x, 0);
        x += share + _gap;
        height = height > b.size.height ? height : b.size.height;
      }
      size = constraints.constrain(Size(width, height));
      return;
    }
    var y = 0.0;
    for (final b in buttons.reversed) {
      b.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
      (b.parentData! as _AlertButtonsData).offset = Offset(0, y);
      y += b.size.height + _gap;
    }
    size = constraints.constrain(Size(width, y - _gap));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// Return runs the default action whatever has the focus, Esc and ⌘.
/// leave. A field keeps Return for its own submit
/// ([_DefaultAction.isEnabled]). When nothing in the dialog asked for the
/// focus, the dialog itself holds it, so the keys reach these bindings.
class _DialogKeys extends StatefulWidget {
  const _DialogKeys({
    required this.actions,
    required this.destructive,
    required this.child,
  });

  final List<Widget> actions;
  final bool destructive;
  final Widget child;

  /// The action Return runs: the affirmative, or the dismissive one when
  /// the affirmative destroys something.
  static Widget? defaultOf(List<Widget> actions, {required bool destructive}) {
    if (actions.isEmpty) return null;
    return destructive ? actions.first : actions.last;
  }

  @override
  State<_DialogKeys> createState() => _DialogKeysState();
}

class _DialogKeysState extends State<_DialogKeys> {
  final _node = FocusNode(debugLabel: 'dialog keys', skipTraversal: true);

  @override
  void initState() {
    super.initState();
    // After the frame, and after the focus manager has applied the
    // autofocus requests of that frame (a field's), which it does in a
    // microtask of its own.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduleMicrotask(() {
        if (!mounted) return;
        final scope = _node.enclosingScope;
        if (scope != null && scope.focusedChild == null) _node.requestFocus();
      });
    });
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.enter): _DefaultIntent(),
      SingleActivator(LogicalKeyboardKey.numpadEnter): _DefaultIntent(),
      SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      SingleActivator(LogicalKeyboardKey.period, meta: true): DismissIntent(),
    },
    child: Actions(
      actions: {
        _DefaultIntent: _DefaultAction(
          _DialogKeys.defaultOf(
            widget.actions,
            destructive: widget.destructive,
          ),
        ),
        DismissIntent: CallbackAction<DismissIntent>(
          onInvoke: (_) {
            Navigator.of(context).maybePop();
            return null;
          },
        ),
      },
      child: Focus(focusNode: _node, child: widget.child),
    ),
  );
}

class _DefaultIntent extends Intent {
  const _DefaultIntent();
}

class _DefaultAction extends Action<_DefaultIntent> {
  _DefaultAction(this.target);

  final Widget? target;

  VoidCallback? get _press => switch (target) {
    ButtonStyleButton(:final onPressed) => onPressed,
    _ => null,
  };

  /// Not while a field has the focus: Return is its submit.
  @override
  bool isEnabled(_DefaultIntent intent) =>
      _press != null &&
      FocusManager.instance.primaryFocus?.context
              ?.findAncestorStateOfType<EditableTextState>() ==
          null;

  @override
  Object? invoke(_DefaultIntent intent) {
    _press?.call();
    return null;
  }
}

/// The most a dialog's body may take of the window's height: the window
/// less the dialog's inset, its margins, its title and its buttons (grown
/// with the text). A tall body (a table of results) held to it shrinks
/// instead of pushing the buttons off a low window.
double appDialogBodyMaxHeight(BuildContext context) {
  final metrics = context.metrics;
  final inset =
      DialogTheme.of(context).insetPadding ??
      const EdgeInsets.symmetric(horizontal: 40, vertical: 24);
  final scale = MediaQuery.textScalerOf(context).scale(1);
  final chrome =
      inset.vertical +
      3 * metrics.contentMargin +
      2 * metrics.topBarHeight * scale;
  return math.max(
    AppSizes.pickerListMaxHeight,
    MediaQuery.sizeOf(context).height - chrome,
  );
}

/// A dialog's body that scrolls in a low window: [child] held to
/// [maxHeight] ([appDialogBodyMaxHeight] by default). It clips above and
/// below only: the focus ring of a field along its sides is painted
/// outside the field, where a scroll view's own clip would cut it off.
class AppDialogScrollBody extends StatelessWidget {
  const AppDialogScrollBody({required this.child, this.maxHeight, super.key});

  final Widget child;
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: maxHeight ?? appDialogBodyMaxHeight(context),
      ),
      child: ClipRect(
        clipper: _OpenSides(
          metrics.focusRingWidth + math.max(0, metrics.focusRingGap),
        ),
        child: SingleChildScrollView(clipBehavior: Clip.none, child: child),
      ),
    );
  }
}

class _OpenSides extends CustomClipper<Rect> {
  const _OpenSides(this.room);

  final double room;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(-room, 0, size.width + room, size.height);

  @override
  bool shouldReclip(_OpenSides oldClipper) => oldClipper.room != room;
}

/// Clips [child] to the inside of [shape]'s edge (its fill), so a surface
/// that draws its edge round its content, as a window does, keeps it: a
/// [Material]'s own clip covers the edge too. Without a shape, no clip.
class ClipInsideEdge extends StatelessWidget {
  const ClipInsideEdge({required this.shape, required this.child, super.key});

  final ShapeBorder? shape;
  final Widget child;

  @override
  Widget build(BuildContext context) => switch (shape) {
    null => child,
    final shape => ClipPath(
      clipper: ShapeBorderClipper(
        shape: shape,
        textDirection: Directionality.maybeOf(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    ),
  };
}
