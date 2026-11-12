import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:component_library/component_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Whether the area holding [label]'s field is the active one, as what it
/// holds reads it.
bool _active(WidgetTester tester, String label) => AppFocusArea.activeOf(
  tester.element(find.byKey(ValueKey('probe $label'))),
);

DecoratedBox _frameBox(WidgetTester tester, Finder frame) =>
    tester.widget<DecoratedBox>(
      find.descendant(of: frame, matching: find.byType(DecoratedBox)).last,
    );

/// The foreground outline of the area around [label].
Color _outline(WidgetTester tester, String label) {
  final area = find.ancestor(
    of: find.byKey(ValueKey('probe $label')),
    matching: find.byType(AppFocusArea),
  );
  final decoration = _frameBox(tester, area.first);
  final shape =
      (decoration.decoration as ShapeDecoration).shape
          as AppRoundedRectangleBorder;
  expect(decoration.position, DecorationPosition.foreground);
  expect(shape.side.width, 2);
  expect(shape.side.strokeAlign, BorderSide.strokeAlignInside);
  return shape.side.color;
}

Widget _field(String label, FocusNode node) => Builder(
  key: ValueKey('probe $label'),
  builder: (context) => TextField(
    focusNode: node,
    decoration: InputDecoration(hintText: label),
  ),
);

void main() {
  for (final brightness in Brightness.values) {
    for (final ratio in [1.0, 2.0]) {
      for (final left in [true, false]) {
        testWidgets(
          '${brightness.name} ${ratio}x: ${left ? 'left' : 'right'} window corner keeps the active outline after clipping',
          (tester) async {
            tester.view.devicePixelRatio = ratio;
            addTearDown(tester.view.reset);
            final node = FocusNode();
            addTearDown(node.dispose);
            final key = GlobalKey();
            final theme = AppTheme.of(AppPlatformStyle.macos, brightness);
            final accent = theme.extension<AppColorsExt>()!.accent.toARGB32();
            final radius = BorderRadius.only(
              topLeft: left ? const Radius.circular(16) : Radius.zero,
              topRight: left ? Radius.zero : const Radius.circular(16),
            );
            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                home: Center(
                  child: RepaintBoundary(
                    key: key,
                    child: SizedBox(
                      width: 120,
                      height: 80,
                      child: ClipRRect(
                        borderRadius: radius,
                        child: AppFocusArea(
                          borderRadius: radius,
                          child: Focus(
                            focusNode: node,
                            child: ColoredBox(color: theme.colorScheme.surface),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            node.requestFocus();
            await tester.pump();
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final result = (await tester.runAsync(() async {
              final image = await boundary.toImage(pixelRatio: ratio);
              final data = await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              );
              final width = image.width;
              image.dispose();
              return (width, data!);
            }))!;
            // Halfway around the curve: a rectangular frame has no blue here.
            final along = ((16 - 15 / math.sqrt2) * ratio).floor();
            final x = left ? along : result.$1 - 1 - along;
            final pixel = (along * result.$1 + x) * 4;
            expect(result.$2.getUint8(pixel), (accent >> 16) & 255);
            expect(result.$2.getUint8(pixel + 1), (accent >> 8) & 255);
            expect(result.$2.getUint8(pixel + 2), accent & 255);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets('the area around the focus draws the outline and takes the '
      'accent; the innermost wins, and a menu keeps the last one', (
    tester,
  ) async {
    final pages = FocusNode();
    final notes = FocusNode();
    final outer = FocusNode();
    final menu = FocusNode();
    addTearDown(pages.dispose);
    addTearDown(notes.dispose);
    addTearDown(outer.dispose);
    addTearDown(menu.dispose);
    final theme = AppTheme.light(AppPlatformStyle.macos);
    final accent = theme.extension<AppColorsExt>()!.accent;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Column(
            children: [
              _field('outside', menu),
              Expanded(
                child: AppFocusArea(
                  child: Column(
                    children: [
                      _field('pane', outer),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: AppFocusArea(
                                child: _field('pages', pages),
                              ),
                            ),
                            Expanded(
                              child: AppFocusArea(
                                child: _field('notes', notes),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final pagesField = find.descendant(
      of: find.byKey(const ValueKey('probe pages')),
      matching: find.byType(TextField),
    );
    final pagesState = tester.state(pagesField);
    final pagesRect = tester.getRect(pagesField);
    expect(_outline(tester, 'pages'), const Color(0x00000000));
    expect(_active(tester, 'outside'), isTrue, reason: 'outside every area');

    pages.requestFocus();
    await tester.pump();
    expect(_active(tester, 'pages'), isTrue);
    expect(_active(tester, 'notes'), isFalse);
    expect(_active(tester, 'pane'), isFalse, reason: 'the innermost wins');
    expect(_outline(tester, 'pages'), accent);
    expect(_outline(tester, 'notes'), const Color(0x00000000));
    expect(_outline(tester, 'pane'), const Color(0x00000000));

    notes.requestFocus();
    await tester.pump();
    expect(_active(tester, 'pages'), isFalse);
    expect(_active(tester, 'notes'), isTrue);
    expect(_outline(tester, 'notes'), accent);
    expect(_outline(tester, 'pages'), const Color(0x00000000));

    // A focus outside every area, as a menu's or a dialog's, leaves the
    // last area marked.
    menu.requestFocus();
    await tester.pump();
    expect(_active(tester, 'notes'), isTrue);
    expect(_outline(tester, 'notes'), accent);

    outer.requestFocus();
    await tester.pump();
    expect(_active(tester, 'pane'), isTrue);
    expect(_active(tester, 'notes'), isFalse);
    expect(_outline(tester, 'pane'), accent);
    expect(tester.getRect(pagesField), pagesRect);
    expect(tester.state(pagesField), same(pagesState));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an area mounted around the focus is active at once', (
    tester,
  ) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    Widget app({required bool area}) => MaterialApp(
      theme: AppTheme.light(AppPlatformStyle.macos),
      home: Scaffold(
        body: area
            ? AppFocusArea(child: _field('field', node))
            : _field('field', node),
      ),
    );
    await tester.pumpWidget(app(area: false));
    node.requestFocus();
    await tester.pump();
    await tester.pumpWidget(app(area: true));
    await tester.pump();
    expect(_active(tester, 'field'), isTrue);
  });

  testWidgets('a relocated frame keeps the whole focus area active, defers '
      'to a nested area, and changes bounds without moving content', (
    tester,
  ) async {
    final header = FocusNode();
    final files = FocusNode();
    final terminal = FocusNode();
    addTearDown(header.dispose);
    addTearDown(files.dispose);
    addTearDown(terminal.dispose);
    final frame = find.byKey(const ValueKey('content frame'));
    late StateSetter update;
    var inset = 20.0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return AppFocusArea(
                showOutline: false,
                child: Column(
                  children: [
                    _field('header', header),
                    Expanded(
                      child: AppFocusFrame(
                        key: const ValueKey('content frame'),
                        insets: EdgeInsets.only(top: inset),
                        child: _field('files', files),
                      ),
                    ),
                    AppFocusArea(child: _field('terminal', terminal)),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    Color color() =>
        ((_frameBox(tester, frame).decoration as ShapeDecoration).shape
                as AppRoundedRectangleBorder)
            .side
            .color;
    final accent = tester.element(frame).appColors.accent;
    final field = find.byKey(const ValueKey('probe files'));
    final fieldState = tester.state(
      find.descendant(of: field, matching: find.byType(TextField)),
    );
    final fieldBounds = tester.getRect(field);
    header.requestFocus();
    await tester.pump();
    expect(color(), accent, reason: 'header belongs to the same focus area');
    expect(
      _outline(tester, 'header').a,
      0,
      reason: 'the full-area frame is hidden',
    );
    expect(
      tester.getRect(find.byWidget(_frameBox(tester, frame))).top,
      tester.getRect(frame).top + inset,
    );

    terminal.requestFocus();
    await tester.pump();
    expect(color().a, 0);
    expect(_outline(tester, 'terminal'), accent);
    await tester.tap(field);
    await tester.pump();
    expect(
      files.hasFocus,
      isTrue,
      reason: 'the frame lets pointer input through',
    );
    expect(color(), accent);
    update(() => inset = 40);
    await tester.pump();
    expect(
      tester.getRect(find.byWidget(_frameBox(tester, frame))).top,
      tester.getRect(frame).top + inset,
    );
    expect(tester.getRect(field), fieldBounds);
    expect(
      tester.state(
        find.descendant(of: field, matching: find.byType(TextField)),
      ),
      same(fieldState),
    );
    expect(files.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });
}
