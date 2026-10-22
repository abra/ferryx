import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Paints [widget] off screen at [size] (logical) and [pixelRatio], with
/// the theme, strings, text direction and media of [context]: a drag's
/// picture.
///
/// The widget gets a tree of its own, built, laid out and painted once
/// and thrown away; nothing reaches the screen.
Future<ui.Image> paintOffscreen(
  BuildContext context,
  Widget widget, {
  required Size size,
  required double pixelRatio,
}) async {
  final boundary = RenderRepaintBoundary();
  final view = RenderView(
    view: View.of(context),
    configuration: ViewConfiguration(
      logicalConstraints: BoxConstraints.tight(size),
      physicalConstraints: BoxConstraints.tight(size * pixelRatio),
      devicePixelRatio: pixelRatio,
    ),
    // Tight: the picture is [size] whatever the widget would take.
    child: boundary,
  );
  final pipeline = PipelineOwner()..rootNode = view;
  view.prepareInitialFrame();
  final focus = FocusManager();
  final build = BuildOwner(focusManager: focus);
  final themed = Directionality(
    textDirection: Directionality.of(context),
    child: InheritedTheme.captureAll(context, widget),
  );
  final content = MediaQuery(
    data: MediaQuery.of(context).copyWith(size: size),
    child: Localizations.maybeLocaleOf(context) == null
        ? themed
        : Localizations.override(context: context, child: themed),
  );
  final root = RenderObjectToWidgetAdapter<RenderBox>(
    container: boundary,
    child: content,
  ).attachToRenderTree(build);
  try {
    build
      ..buildScope(root)
      ..finalizeTree();
    pipeline
      ..flushLayout()
      ..flushCompositingBits()
      ..flushPaint();
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    return image;
  } finally {
    // An empty tree unmounts the widget's elements and their state.
    RenderObjectToWidgetAdapter<RenderBox>(
      container: boundary,
    ).attachToRenderTree(build, root);
    build
      ..buildScope(root)
      ..finalizeTree();
    pipeline
      ..rootNode = null
      ..dispose();
    focus.dispose();
  }
}
