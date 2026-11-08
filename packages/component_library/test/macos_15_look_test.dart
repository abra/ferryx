import 'dart:convert';
import 'dart:ui' as ui;

import 'package:component_library/component_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// What macOS 15 draws, measured beside AppKit at one pixel per point:
/// Finder's list, NSTextField, NSPopUpButton, NSMenu, NSAlert and a sheet.
/// macOS 26 keeps its own look where it differs.
void main() {
  final sequoia = AppMetrics.of(AppPlatformStyle.macos);
  final tahoe = AppMetrics.of(
    AppPlatformStyle.macos,
    generation: MacGeneration.tahoe,
  );

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    MacGeneration generation = MacGeneration.sequoia,
    AppPlatformStyle style = AppPlatformStyle.macos,
    Brightness brightness = Brightness.light,
  }) => tester.pumpWidget(
    MaterialApp(
      themeAnimationDuration: Duration.zero,
      theme: AppTheme.of(style, brightness, generation: generation),
      builder: (context, child) => AppIdentity(icon: _icon, child: child!),
      home: Scaffold(body: Center(child: child)),
    ),
  );

  test('a table\'s highlight spans the row, square; elsewhere and on macOS '
      '26 it is a list row\'s, inset and rounded', () {
    expect(sequoia.tableRowInset, 0);
    expect(sequoia.radius.tableRow, 0);
    expect(sequoia.radius.tableFrame, 0);
    // A sidebar, a menu and a picker keep the inset, rounded highlight.
    expect(sequoia.rowInset, greaterThan(0));
    expect(sequoia.radius.row, greaterThan(0));
    // A source list's selection stands 10 from the sidebar's edges, its
    // icon 16.
    expect(sequoia.navRowMargin, 10);
    expect(sequoia.navRowMargin + sequoia.navRowPadding, 16);
    expect(tahoe.tableRowInset, tahoe.rowInset);
    expect(tahoe.radius.tableRow, tahoe.radius.row);
    final windows = AppMetrics.of(AppPlatformStyle.windows);
    expect(windows.tableRowInset, windows.rowInset);
  });

  testWidgets('a text field is square, its text 4 from the edge, its lower '
      'edge shaded; a search field stays rounded', (tester) async {
    await pump(
      tester,
      const SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(),
            AppSearchField(hintText: 'Search'),
          ],
        ),
      ),
    );
    final theme = Theme.of(tester.element(find.byType(TextField).first));
    final border =
        theme.inputDecorationTheme.enabledBorder! as AppOutlineInputBorder;
    expect(border.borderRadius, BorderRadius.zero);
    expect(border.shade, isNotNull);
    final field = tester.getRect(find.byType(TextField).first);
    final text = tester.getRect(find.byType(EditableText).first);
    expect(text.left - field.left, 4);
    final search = tester.widget<TextField>(
      find.descendant(
        of: find.byType(AppSearchField),
        matching: find.byType(TextField),
      ),
    );
    final searchBorder =
        search.decoration!.enabledBorder! as OutlineInputBorder;
    expect(searchBorder.borderRadius, BorderRadius.circular(6));
  });

  for (final brightness in Brightness.values) {
    testWidgets('a search field over a sidebar is a quiet fill with a fine '
        'edge, no white bezel (${brightness.name})', (tester) async {
      await pump(
        tester,
        brightness: brightness,
        const SizedBox(
          width: 220,
          child: AppSearchField(hintText: 'Search', sidebar: true),
        ),
      );
      final context = tester.element(find.byType(AppSearchField));
      final colors = context.appColors;
      final decoration = tester
          .widget<TextField>(
            find.descendant(
              of: find.byType(AppSearchField),
              matching: find.byType(TextField),
            ),
          )
          .decoration!;
      expect(decoration.fillColor, colors.hoverFill);
      final edge = decoration.enabledBorder! as AppOutlineInputBorder;
      expect(edge.borderSide.color, colors.controlBorder);
      expect(edge.borderRadius, BorderRadius.circular(6));
      // Its lower edge is lighter in the dark only, as AppKit draws it.
      expect(edge.shade, brightness == Brightness.dark ? isNotNull : isNull);
      final focused = decoration.focusedBorder! as AppOutlineInputBorder;
      expect(focused.halo, isNotNull);
    });
  }

  testWidgets('a sidebar search field elsewhere keeps the theme\'s field', (
    tester,
  ) async {
    await pump(
      tester,
      style: AppPlatformStyle.gnome,
      const SizedBox(
        width: 220,
        child: AppSearchField(hintText: 'Search', sidebar: true),
      ),
    );
    final decoration = tester
        .widget<TextField>(
          find.descendant(
            of: find.byType(AppSearchField),
            matching: find.byType(TextField),
          ),
        )
        .decoration!;
    expect(decoration.fillColor, isNull);
  });

  testWidgets('a focused text field takes the accent halo outside its '
      'bezel, as an NSTextField', (tester) async {
    tester.view.physicalSize = const Size(400, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(
      tester,
      const SizedBox(width: 300, child: TextField(autofocus: true)),
    );
    await tester.pumpAndSettle();
    final field = tester.getRect(find.byType(TextField));
    final above = await tester.runAsync(() async {
      final image = await captureImage(
        find.byType(Scaffold).evaluate().single,
      );
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final i =
          ((field.top.round() - 2) * image.width + field.center.dx.round()) * 4;
      return Color.fromARGB(
        255,
        data.getUint8(i),
        data.getUint8(i + 1),
        data.getUint8(i + 2),
      );
    });
    // The page is white; two points above the bezel the ring is blue.
    expect(above!.b, greaterThan(above.r + 0.2));
  });

  testWidgets('a push button\'s bezel is shaded below on macOS 15 only', (
    tester,
  ) async {
    OutlinedBorder shapeOf(ThemeData theme) =>
        theme.outlinedButtonTheme.style!.shape!.resolve(const {})!;
    expect(
      shapeOf(AppTheme.of(AppPlatformStyle.macos, Brightness.light)),
      isA<AppBezelBorder>(),
    );
    expect(
      shapeOf(
        AppTheme.of(
          AppPlatformStyle.macos,
          Brightness.light,
          generation: MacGeneration.tahoe,
        ),
      ),
      isNot(isA<AppBezelBorder>()),
    );
  });

  test('a sheet darkens the window behind it as macOS does', () {
    Color barrier(Brightness b) =>
        AppTheme.of(AppPlatformStyle.macos, b).dialogTheme.barrierColor!;
    expect(barrier(Brightness.light).a, closeTo(0.19, 0.005));
    expect(barrier(Brightness.dark).a, closeTo(0.28, 0.005));
  });

  testWidgets('a pop-up button ends in the accent\'s cap with white '
      'chevrons; on macOS 26 in bare chevrons', (tester) async {
    Future<Color?> chevrons(MacGeneration generation) async {
      await pump(
        tester,
        AppPopupButton<int>(
          value: 1,
          items: const [(1, 'Ask'), (2, 'Overwrite')],
          onChanged: (_) {},
        ),
        generation: generation,
      );
      return tester
          .widget<Icon>(
            find.byWidgetPredicate(
              (w) => w is Icon && w.icon == AppIcons.chevronsUpDown,
            ),
          )
          .color;
    }

    final colors = AppTheme.of(
      AppPlatformStyle.macos,
      Brightness.light,
    ).extension<AppColorsExt>()!;
    expect(await chevrons(MacGeneration.sequoia), colors.onAccent);
    expect(await chevrons(MacGeneration.tahoe), colors.textMuted);
  });

  group('edges hold round the corners at one pixel per point', () {
    const ground = Color(0xFFE9E9E9);

    /// The grey of every pixel of the screen, read back.
    Future<int Function(int x, int y)> pixels(WidgetTester tester) async {
      final data = await tester.runAsync(() async {
        final image = await captureImage(
          find.byType(RepaintBoundary).evaluate().first,
        );
        return (
          image.width,
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!,
        );
      });
      final (width, bytes) = data!;
      return (x, y) => bytes.getUint8((y * width + x) * 4 + 1);
    }

    /// From outside a corner inward along its diagonal, the first pixel
    /// off the ground is the edge's, darker; a fill laid under the edge
    /// shows first, lighter, and the corner looks open.
    void expectEdgeAtCorner(int Function(int, int) grey, Offset corner) {
      for (var k = 0; k < 8; k++) {
        final g = grey(corner.dx.round() + k, corner.dy.round() + k);
        if (g == 0xE9) continue;
        expect(g, lessThan(0xE9), reason: 'the first pixel in, at $k');
        return;
      }
      fail('no edge on the diagonal');
    }

    Future<void> pumpOnGround(
      WidgetTester tester,
      Widget child, {
      Size size = const Size(300, 200),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          themeAnimationDuration: Duration.zero,
          theme: AppTheme.of(AppPlatformStyle.macos, Brightness.light),
          home: RepaintBoundary(
            child: ColoredBox(
              color: ground,
              child: Center(child: child),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final half in [false, true]) {
      testWidgets('an edged box${half ? ' half a pixel off' : ''}', (
        tester,
      ) async {
        await pumpOnGround(
          tester,
          Padding(
            padding: EdgeInsets.only(top: half ? 1 : 0),
            child: Container(
              key: const Key('box'),
              width: 120,
              height: 41,
              clipBehavior: Clip.antiAlias,
              decoration: appEdgedBox(
                color: Colors.white,
                edge: const Color(0x1A000000),
                radius: 8,
              ),
              child: const ColoredBox(color: Colors.white),
            ),
          ),
        );
        expectEdgeAtCorner(
          await pixels(tester),
          tester.getTopLeft(find.byKey(const Key('box'))),
        );
      });
    }

    testWidgets('a push button', (tester) async {
      await pumpOnGround(
        tester,
        OutlinedButton(onPressed: () {}, child: const Text('Cancel')),
      );
      final grey = await pixels(tester);
      final button = tester.getRect(find.byType(OutlinedButton));
      expectEdgeAtCorner(grey, button.topLeft);
    });

    for (final sidebar in [false, true]) {
      testWidgets('a ${sidebar ? 'sidebar\'s search field' : 'text field'}: '
          'its edge lies on the ground, not on its fill', (tester) async {
        await pumpOnGround(
          tester,
          Material(
            type: MaterialType.transparency,
            child: SizedBox(
              width: 200,
              child: sidebar
                  ? const AppSearchField(hintText: 'Search', sidebar: true)
                  : const TextField(),
            ),
          ),
        );
        final grey = await pixels(tester);
        final field = tester.getRect(find.byType(TextField));
        final x = field.right.round() - 20;
        final top = field.top.round();
        final colors = AppTheme.light(AppPlatformStyle.macos)
            .extension<AppColorsExt>()!;
        final edge = colors.controlBorder;
        // The control edge lands on the ground, including on a sidebar.
        expect(
          grey(x, top),
          closeTo(Color.alphaBlend(edge, ground).g * 255, 2),
        );
        expect(grey(x, top), lessThan(grey(x, top + 3)));
        expectEdgeAtCorner(grey, field.topLeft);
      });
    }

    testWidgets('a focused button shows its ring: the button does not '
        'clip it away', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await pumpOnGround(
        tester,
        OutlinedButton(
          focusNode: node,
          onPressed: () {},
          child: const Text('Cancel'),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      node.requestFocus();
      await tester.pumpAndSettle();
      final button = tester.getRect(find.byType(OutlinedButton));
      final data = await tester.runAsync(() async {
        final image = await captureImage(
          find.byType(RepaintBoundary).evaluate().first,
        );
        return (
          image.width,
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!,
        );
      });
      final (width, bytes) = data!;
      final i =
          ((button.top.round() - 2) * width + button.center.dx.round()) * 4;
      // Blue two points above the bezel, on a grey ground.
      expect(bytes.getUint8(i + 2), greaterThan(bytes.getUint8(i) + 30));
    });

    testWidgets('a focused field in a dialog body that scrolls keeps its '
        'ring at the sides', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await pumpOnGround(
        tester,
        size: const Size(400, 300),
        AppDialog(
          title: 'Rename',
          width: 320,
          body: AppDialogScrollBody(
            maxHeight: 120,
            child: Column(
              children: [
                TextField(focusNode: node),
                const SizedBox(height: 400),
              ],
            ),
          ),
          actions: [OutlinedButton(onPressed: () {}, child: const Text('OK'))],
        ),
      );
      node.requestFocus();
      await tester.pumpAndSettle();
      final field = tester.getRect(find.byType(TextField));
      final data = await tester.runAsync(() async {
        final image = await captureImage(
          find.byType(RepaintBoundary).evaluate().first,
        );
        return (
          image.width,
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!,
        );
      });
      final (width, bytes) = data!;
      for (final x in [field.left.round() - 2, field.right.round() + 1]) {
        final i = (field.center.dy.round() * width + x) * 4;
        expect(
          bytes.getUint8(i + 2),
          greaterThan(bytes.getUint8(i) + 30),
          reason: 'blue beside the field at $x',
        );
      }
    });

    testWidgets('a dialog: its content is clipped inside the edge', (
      tester,
    ) async {
      await pumpOnGround(
        tester,
        AppDialog(
          title: 'Copy',
          width: 240,
          actions: [OutlinedButton(onPressed: () {}, child: const Text('OK'))],
        ),
      );
      final grey = await pixels(tester);
      final dialog = tester.getRect(
        find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(Material),
            )
            .first,
      );
      final x = dialog.center.dx.round();
      final top = dialog.top.round();
      // The edge line, darker than the ground above it and the fill below.
      expect(grey(x, top), lessThan(grey(x, top - 3)));
      expect(grey(x, top), lessThan(grey(x, top + 3)));
      expectEdgeAtCorner(grey, dialog.topLeft);
    });

    for (final room in [const Size(300, 200), const Size(301, 201)]) {
      testWidgets('a dialog centred in a room of ${room.width.toInt()} lands '
          'on whole pixels: no pale column inside its edge', (tester) async {
        await pumpOnGround(
          tester,
          size: room,
          AppDialog(
            title: 'Copy',
            width: 240,
            actions: [
              OutlinedButton(onPressed: () {}, child: const Text('OK')),
            ],
          ),
        );
        final dialog = tester.getRect(
          find
              .descendant(
                of: find.byType(Dialog),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(dialog.left, dialog.left.roundToDouble());
        expect(dialog.top, dialog.top.roundToDouble());
        final grey = await pixels(tester);
        final y = dialog.center.dy.round();
        final left = dialog.left.round();
        final right = dialog.right.round() - 1;
        // The edge, then the fill at once on both sides.
        expect(grey(left, y), lessThan(grey(left - 2, y)));
        expect(grey(left + 1, y), grey(left + 4, y));
        expect(grey(right, y), lessThan(grey(right + 2, y)));
        expect(grey(right - 1, y), grey(right - 4, y));
      });
    }
  });

  group('a menu', () {
    Future<void> open(
      WidgetTester tester,
      List<AppMenuEntry<String>> entries, {
      MacGeneration generation = MacGeneration.sequoia,
    }) async {
      await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppMenu<String>(
              context: context,
              anchor: const Offset(100, 100) & Size.zero,
              entries: entries,
            ),
            child: const Text('menu'),
          ),
        ),
        generation: generation,
      );
      await tester.tap(find.text('menu'));
      await tester.pumpAndSettle();
    }

    double labelLeft(WidgetTester tester, String label) =>
        tester.getTopLeft(find.text(label)).dx;

    testWidgets('keeps a check column only while an item is checked, its '
        'labels 11 further in', (tester) async {
      await open(tester, const [
        AppMenuAction(value: 'a', label: 'Short', checked: false),
        AppMenuAction(value: 'b', label: 'Wide', checked: false),
      ]);
      final bare = labelLeft(tester, 'Short');
      expect(
        tester
            .widget<AppMenuItem>(find.widgetWithText(AppMenuItem, 'Short'))
            .checked,
        isNull,
      );
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
      await open(tester, const [
        AppMenuAction(value: 'a', label: 'Short', checked: false),
        AppMenuAction(value: 'b', label: 'Wide', checked: true),
      ]);
      expect(
        labelLeft(tester, 'Short') - bare,
        sequoia.menuCheckWidth - sequoia.menuCheckPull,
      );
    });

    testWidgets('shows no symbols on macOS 15, and them on macOS 26', (
      tester,
    ) async {
      const entries = [
        AppMenuAction(value: 'a', label: 'Copy', icon: AppIcons.copy),
        AppMenuAction(value: 'b', label: 'Rename'),
      ];
      await open(tester, entries);
      expect(find.byIcon(AppIcons.copy), findsNothing);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
      await open(tester, entries, generation: MacGeneration.tahoe);
      expect(find.byIcon(AppIcons.copy), findsOneWidget);
    });
  });

  group('an alert', () {
    Widget dialog({bool alert = true}) => AppDialog(
      title: 'Delete?',
      alert: alert,
      actions: [
        OutlinedButton(onPressed: () {}, child: const Text('No')),
        FilledButton(onPressed: () {}, child: const Text('Yes')),
      ],
    );

    final icon = find.byWidgetPredicate((w) => w is Image && w.image == _icon);

    testWidgets('carries the app\'s icon, 64 square, 20 above its title', (
      tester,
    ) async {
      await pump(tester, dialog());
      expect(tester.getSize(icon), const Size(64, 64));
      expect(
        tester.getRect(find.text('Delete?')).top - tester.getRect(icon).bottom,
        20,
      );
    });

    testWidgets('a sheet does not, nor an alert on another desktop', (
      tester,
    ) async {
      await pump(tester, dialog(alert: false));
      expect(icon, findsNothing);
      await pump(tester, dialog(), style: AppPlatformStyle.gnome);
      expect(icon, findsNothing);
    });
  });

  group('window tabs, as Finder\'s on macOS 15', () {
    /// The bar above in its colour, the strip under it, at 1x; the grey of
    /// each pixel by its position in the strip's box.
    Future<(Rect, int Function(double x, double y))> pumpStrip(
      WidgetTester tester,
      Brightness brightness, {
      double stripWidth = 400,
      int active = 1,
    }) async {
      tester.view.physicalSize = Size(stripWidth, 120);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          themeAnimationDuration: Duration.zero,
          theme: AppTheme.of(AppPlatformStyle.macos, brightness),
          home: Builder(
            builder: (context) => RepaintBoundary(
              child: Material(
                color: context.appColors.windowChrome,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 20),
                    AppTabStrip(
                      tabs: const [
                        AppTab(id: 0, label: 'A', icon: AppIcons.folder),
                        AppTab(id: 1, label: 'B', icon: AppIcons.folder),
                        AppTab(id: 2, label: 'C', icon: AppIcons.folder),
                      ],
                      active: active,
                      onSelect: (_) {},
                      onClose: (_) {},
                      onReorder: (_, _) {},
                      onMenu: (_, _) {},
                      onNewTab: () {},
                      closeTooltip: 'Close',
                      newTabTooltip: 'New',
                      listTooltip: 'All',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final bar = tester.getRect(find.byType(AppTabStrip));
      final data = await tester.runAsync(() async {
        final image = await captureImage(
          find.byType(RepaintBoundary).evaluate().first,
        );
        return (
          image.width,
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!,
        );
      });
      final (width, bytes) = data!;
      return (
        bar,
        (double x, double y) =>
            bytes.getUint8(((bar.top + y).round() * width + x.round()) * 4 + 1),
      );
    }

    double tabLeft(WidgetTester tester, String label) => tester
        .getRect(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(HintTarget),
          ),
        )
        .left;

    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name}: the active tab opens into the bar '
          'above in its colour; the others sit lower, under an edge, with a '
          'line between them', (tester) async {
        final (bar, grey) = await pumpStrip(tester, brightness);
        final above = grey(200, -3);
        final b = tabLeft(tester, 'B');
        final c = tabLeft(tester, 'C');
        // Clear of the names and icons in the middle.
        final inA = bar.left + 3;
        final inB = b + 3;
        expect(c, greaterThan(inB));
        // The active tab: the bar's colour from its top row down.
        expect(grey(inB, 0), above);
        expect(grey(inB, 14), above);
        // An inactive one: an edge on top, then the bar, apart from the
        // bar above.
        final fill = grey(inA, 14);
        expect(fill, isNot(above));
        expect(grey(inA, 0), isNot(fill), reason: 'the edge');
        // The line between A and B, the bar's height.
        expect(grey(b, 14), isNot(fill));
        if (brightness == Brightness.light) {
          // Under the toolbar's white: lower, and a shade under the edge.
          expect(fill, lessThan(above));
          expect(grey(inA, 1), lessThan(fill));
        } else {
          // Darker than the bar above, as AppKit's dark tab bar is.
          expect(fill, lessThan(above));
        }
      });

      testWidgets('${brightness.name}: the last active tab meets the new-tab '
          'cell without a step in its top edge or underline', (tester) async {
        final (bar, grey) = await pumpStrip(
          tester,
          brightness,
          stripWidth: 599,
          active: 2,
        );
        final context = tester.element(find.byType(AppTabStrip));
        final cellLeft = bar.right - context.metrics.iconButtonSize.width;
        final lastTabPixel = cellLeft - 1;
        final inActiveTab = tabLeft(tester, 'C') + 3;
        final above = grey(lastTabPixel, -3);

        expect(
          grey(lastTabPixel, 0),
          above,
          reason: 'continuous open top edge',
        );
        expect(grey(lastTabPixel, 14), above, reason: 'no exposed strip pixel');
        final underlineY = bar.height - 3;
        final accent = grey(inActiveTab, underlineY);
        expect(accent, isNot(above));
        expect(
          grey(lastTabPixel, underlineY),
          accent,
          reason: 'the active underline reaches the new-tab cell',
        );
      });
    }
  });
}

/// One transparent pixel.
final _icon = MemoryImage(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
  ),
);
