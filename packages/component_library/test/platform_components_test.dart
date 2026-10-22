import 'package:component_library/component_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps [child] under the theme of [style].
Future<void> pumpIn(
  WidgetTester tester,
  AppPlatformStyle style,
  Widget child, {
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) => tester.pumpWidget(
  MaterialApp(
    // Each test pumps a new style; no blend between the two.
    themeAnimationDuration: Duration.zero,
    theme: AppTheme.of(style, brightness),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  group('AppDialog', () {
    Future<void> showConfirm(
      WidgetTester tester,
      AppPlatformStyle style,
    ) async {
      await pumpIn(
        tester,
        style,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => AppDialog.confirm(
              context,
              title: 'Move "Soma" to the trash?',
              message: '12 rems and 3 cards',
              confirmLabel: 'Move',
              cancelLabel: 'Cancel',
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    for (final style in AppPlatformStyle.values) {
      testWidgets('$style puts the affirmative action where the platform '
          'does', (tester) async {
        await showConfirm(tester, style);
        final cancel = tester.getCenter(find.text('Cancel')).dx;
        final move = tester.getCenter(find.text('Move')).dx;
        if (style == AppPlatformStyle.windows) {
          expect(move, lessThan(cancel), reason: 'Fluent: primary first');
        } else {
          expect(move, greaterThan(cancel), reason: 'affirmative last');
        }
      });
    }

    testWidgets('alerts centre their title on macOS and GNOME, Fluent keeps '
        'it at the start', (tester) async {
      for (final style in AppPlatformStyle.values) {
        await showConfirm(tester, style);
        final title = tester.widget<Text>(
          find.text('Move "Soma" to the trash?'),
        );
        expect(
          title.textAlign,
          style == AppPlatformStyle.windows ? isNull : TextAlign.center,
          reason: '$style',
        );
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('Enter confirms, Esc dismisses; a destructive action is '
        'never the default', (tester) async {
      bool? result;
      var destructive = false;
      await pumpIn(
        tester,
        AppPlatformStyle.gnome,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await AppDialog.confirm(
              context,
              title: 'Delete?',
              confirmLabel: 'Delete',
              cancelLabel: 'Cancel',
              destructive: destructive,
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(result, isTrue);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(result, isFalse);
      // Return on a destructive alert is the dismissive action.
      destructive = true;
      result = null;
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(result, isFalse);
      // Space presses the focused button, which the pointer put on Delete.
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });
  });

  group('AppNavItem', () {
    Future<BoxDecoration?> rowDecoration(WidgetTester tester) async {
      final box = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(AppNavItem),
              matching: find.byType(Container),
            )
            .first,
      );
      return box.decoration as BoxDecoration?;
    }

    testWidgets('macOS greys the selected row and turns it to the accent '
        'while the list has the focus', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await pumpIn(
        tester,
        AppPlatformStyle.macos,
        SizedBox(
          width: 240,
          child: FocusTraversalGroup(
            child: AppNavItem(
              label: 'Neuron',
              selected: true,
              focusNode: node,
              onTap: () {},
            ),
          ),
        ),
      );
      final colors = AppTheme.light(AppPlatformStyle.macos)
          .extension<AppColorsExt>()!;
      expect((await rowDecoration(tester))!.color, colors.selectionMuted);
      node.requestFocus();
      await tester.pump();
      expect((await rowDecoration(tester))!.color, colors.selectionAccent);
      final label = tester.widget<Text>(find.text('Neuron'));
      expect(label.style!.color, colors.onAccent);
      expect(
        tester.widget<FocusRing>(find.byType(FocusRing)).decorate,
        isFalse,
        reason: 'the accent row is the focus mark, no ring around it',
      );
    });

    testWidgets('Fluent marks the selected row with an accent pill, the '
        'others do not', (tester) async {
      for (final style in AppPlatformStyle.values) {
        await pumpIn(
          tester,
          style,
          const SizedBox(
            width: 240,
            child: AppNavItem(label: 'Neuron', selected: true),
          ),
        );
        final accent = AppTheme.light(style).extension<AppColorsExt>()!.accent;
        final pills = find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.constraints?.maxWidth == 3 &&
              (w.decoration as BoxDecoration?)?.color == accent,
        );
        expect(
          pills,
          style == AppPlatformStyle.windows ? findsOneWidget : findsNothing,
          reason: '$style',
        );
        // The row fills the platform's height; the item adds its gap.
        final metrics = AppMetrics.of(style);
        final fill = find.descendant(
          of: find.byType(AppNavItem),
          matching: find.byType(InkWell),
        );
        expect(
          tester.getSize(fill).height,
          metrics.navItemHeight,
          reason: '$style',
        );
        expect(
          tester.getSize(find.byType(AppNavItem)).height,
          metrics.navItemHeight + metrics.navItemGap,
          reason: '$style',
        );
      }
    });
  });

  group('showAppMenu', () {
    Future<String?> open(
      WidgetTester tester,
      AppPlatformStyle style,
      Future<void> Function() interact,
    ) async {
      String? picked = 'none';
      await pumpIn(
        tester,
        style,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => picked = await showAppMenu<String>(
              context: context,
              anchor: const Offset(100, 100) & Size.zero,
              entries: const [
                AppMenuSection('Pages'),
                AppMenuAction(value: 'open', label: 'Open', shortcut: '⌘O'),
                AppMenuAction(value: 'off', label: 'Disabled', enabled: false),
                AppMenuSeparator(),
                AppMenuAction(value: 'rename', label: 'Rename'),
                AppMenuAction(value: 'trash', label: 'Trash', danger: true),
              ],
            ),
            child: const Text('menu'),
          ),
        ),
      );
      await tester.tap(find.text('menu'));
      await tester.pumpAndSettle();
      await interact();
      await tester.pumpAndSettle();
      return picked;
    }

    testWidgets('↓ skips headers, separators and disabled items; Enter '
        'picks', (tester) async {
      final picked = await open(tester, AppPlatformStyle.windows, () async {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      });
      expect(picked, 'rename');
    });

    testWidgets('↑ wraps to the last item; a letter jumps to the next item '
        'starting with it', (tester) async {
      expect(
        await open(tester, AppPlatformStyle.gnome, () async {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        }),
        'trash',
      );
      expect(
        await open(tester, AppPlatformStyle.gnome, () async {
          await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        }),
        'rename',
      );
    });

    testWidgets('Esc and a click outside dismiss with null', (tester) async {
      expect(
        await open(tester, AppPlatformStyle.macos, () async {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        }),
        isNull,
      );
      expect(
        await open(tester, AppPlatformStyle.macos, () async {
          await tester.tapAt(const Offset(5, 5));
        }),
        isNull,
      );
    });

    testWidgets('a menu taller than the window keeps the lit item in view: '
        'End, Home, ↑ from nothing, ↓ across the bottom', (tester) async {
      tester.view.physicalSize = const Size(480, 320);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpIn(
        tester,
        AppPlatformStyle.macos,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppMenu<int>(
              context: context,
              anchor: const Offset(20, 20) & Size.zero,
              entries: [
                for (var i = 0; i < 40; i++)
                  AppMenuAction(value: i, label: 'Item $i'),
              ],
            ),
            child: const Text('menu'),
          ),
        ),
      );
      await tester.tap(find.text('menu'));
      await tester.pumpAndSettle();
      final panel = tester.getRect(find.byType(AppMenuPanel));
      bool shown(int i) {
        final row = tester.getRect(find.widgetWithText(AppMenuItem, 'Item $i'));
        return row.top >= panel.top - 0.5 && row.bottom <= panel.bottom + 0.5;
      }

      Future<void> press(LogicalKeyboardKey key) async {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
      }

      expect(shown(0), isTrue);
      expect(shown(39), isFalse);
      await press(LogicalKeyboardKey.end);
      expect(shown(39), isTrue);
      await press(LogicalKeyboardKey.home);
      expect(shown(0), isTrue);
      await press(LogicalKeyboardKey.arrowUp);
      expect(shown(39), isTrue, reason: '↑ wraps to the last item');
      await press(LogicalKeyboardKey.arrowDown);
      expect(shown(0), isTrue, reason: '↓ wraps back to the top');
      // Step down past the bottom edge one row at a time.
      for (var i = 1; i < 20; i++) {
        await press(LogicalKeyboardKey.arrowDown);
        expect(shown(i), isTrue, reason: 'Item $i');
      }
    });

    testWidgets('the highlight takes the accent with light text on macOS, a '
        'subtle fill elsewhere; shortcuts are plain text', (tester) async {
      for (final style in AppPlatformStyle.values) {
        await open(tester, style, () async {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        });
        final colors = AppTheme.light(style).extension<AppColorsExt>()!;
        final label = tester.widget<Text>(find.text('Open'));
        final row = tester.widget<Container>(
          find
              .ancestor(of: find.text('Open'), matching: find.byType(Container))
              .first,
        );
        final fill = (row.decoration! as BoxDecoration).color;
        if (style == AppPlatformStyle.macos) {
          expect(fill, colors.selectionAccent);
          expect(label.style!.color, colors.onAccent);
        } else {
          expect(fill, colors.hoverFill);
        }
        expect(find.byType(AppShortcutLabel), findsOneWidget);
        expect(find.byType(AppKeyCap), findsNothing, reason: 'no key caps');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      }
    });
  });

  group('menu width', () {
    Future<void> openWith(
      WidgetTester tester,
      String label, {
      String? shortcut,
    }) async {
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpIn(
        tester,
        AppPlatformStyle.windows,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppMenu<int>(
              context: context,
              anchor: const Offset(20, 20) & Size.zero,
              entries: [
                const AppMenuAction(value: 0, label: 'Rename'),
                AppMenuAction(
                  value: 1,
                  label: label,
                  shortcut: shortcut,
                ),
              ],
            ),
            child: const Text('menu'),
          ),
        ),
      );
      await tester.tap(find.text('menu'));
      await tester.pumpAndSettle();
    }

    testWidgets('grows to the widest item, label and shortcut whole', (
      tester,
    ) async {
      // The test font draws em squares: 'Open pane' and its shortcut
      // need about 330 px of the 420.
      await openWith(tester, 'Open pane', shortcut: 'Ctrl+Shift+P');
      final label = tester.renderObject<RenderParagraph>(
        find.text('Open pane'),
      );
      expect(label.didExceedMaxLines, isFalse);
      final panel = tester.getSize(find.byType(AppMenuPanel));
      expect(panel.width, greaterThan(AppSizes.menuMinWidth));
      expect(panel.width, lessThanOrEqualTo(AppSizes.menuMaxWidth));
    });

    testWidgets('a short menu keeps the minimum width; a very long label '
        'stops at the maximum and ends in an ellipsis', (tester) async {
      await openWith(tester, 'Go');
      expect(
        tester.getSize(find.byType(AppMenuPanel)).width,
        AppSizes.menuMinWidth,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      final long = 'A label far longer than any menu should be ' * 2;
      await openWith(tester, long);
      expect(
        tester.getSize(find.byType(AppMenuPanel)).width,
        AppSizes.menuMaxWidth,
      );
      expect(
        tester.renderObject<RenderParagraph>(find.text(long)).didExceedMaxLines,
        isTrue,
      );
    });
  });

  testWidgets('a count badge keeps its own height in a taller row', (
    tester,
  ) async {
    await pumpIn(
      tester,
      AppPlatformStyle.windows,
      const SizedBox(
        width: 240,
        child: AppNavItem(label: 'Flashcards', badge: '6'),
      ),
    );
    final row = tester.getSize(find.byType(AppNavItem)).height;
    final badge = tester.getSize(
      find.ancestor(of: find.text('6'), matching: find.byType(Container)).first,
    );
    expect(badge.height, lessThan(row / 2 + 4));
    expect(badge.width, greaterThanOrEqualTo(18));
  });

  group('AppToggle', () {
    for (final style in AppPlatformStyle.values) {
      testWidgets('$style: the platform\'s switch size, Space flips it', (
        tester,
      ) async {
        var value = false;
        await pumpIn(
          tester,
          style,
          StatefulBuilder(
            builder: (context, setState) => AppToggle(
              value: value,
              onChanged: (v) => setState(() => value = v),
            ),
          ),
        );
        expect(
          tester.getSize(find.byType(AppToggle)),
          AppMetrics.of(style).toggleSize,
        );
        await tester.tap(find.byType(AppToggle));
        await tester.pumpAndSettle();
        expect(value, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(value, isFalse);
      });
    }
  });

  for (final style in AppPlatformStyle.values) {
    for (final scale in [1.0, 1.6]) {
      testWidgets('$style, text at $scale: controls in a row share one '
          'height, the platform\'s control height at scale 1, so they line '
          'up', (tester) async {
        // The test font is an em square per glyph: room for the labels.
        tester.view.physicalSize = const Size(1800, 400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await pumpIn(
          tester,
          style,
          textScale: scale,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton(onPressed: () {}, child: const Text('Create')),
              OutlinedButton(onPressed: () {}, child: const Text('Cancel')),
              TextButton(onPressed: () {}, child: const Text('More')),
              AppPopupButton<int>(
                value: 1,
                items: const [(1, 'Markdown'), (2, 'OPML')],
                onChanged: (_) {},
              ),
              AppSegmentedControl<int>(
                options: const [(1, 'Light'), (2, 'Dark')],
                value: 1,
                onChanged: (_) {},
              ),
              const SizedBox(
                width: 140,
                child: TextField(
                  decoration: InputDecoration(hintText: 'Search'),
                ),
              ),
              // A search field: Material's 48 px icon box would make it tall.
              const SizedBox(
                width: 160,
                child: TextField(
                  key: Key('search'),
                  decoration: InputDecoration(
                    hintText: 'Find',
                    prefixIcon: Icon(Icons.search, size: 16),
                  ),
                ),
              ),
              // A path field: monospace, no decoration of its own.
              Builder(
                builder: (context) => SizedBox(
                  width: 140,
                  child: TextField(
                    key: const Key('path'),
                    autofocus: true,
                    style: context.mono,
                  ),
                ),
              ),
            ],
          ),
        );
        await tester.pump();
        // At a larger text size every control grows by what its line grows,
        // as a field does.
        final height = scale == 1
            ? AppMetrics.of(style).controlHeight
            : tester.getSize(find.byType(TextField).first).height;
        expect(
          height,
          greaterThanOrEqualTo(AppMetrics.of(style).controlHeight),
        );
        for (final type in [
          FilledButton,
          OutlinedButton,
          TextButton,
          AppPopupButton<int>,
          AppSegmentedControl<int>,
          TextField,
        ]) {
          final finder = find.byType(type);
          expect(
            tester.getSize(finder.first).height,
            moreOrLessEquals(height, epsilon: 0.5),
            reason: '$type',
          );
        }
        expect(
          tester.getSize(find.byKey(const Key('path'))).height,
          moreOrLessEquals(height, epsilon: 0.5),
          reason: 'a focused monospace field',
        );
        expect(
          tester.getSize(find.byKey(const Key('search'))).height,
          moreOrLessEquals(height, epsilon: 0.5),
          reason: 'a field with a prefix icon',
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  group('AppSegmentedControl', () {
    const options = [
      ('whole', 'Вся база знаний целиком'),
      ('doc', 'Текущий документ'),
    ];

    for (final style in AppPlatformStyle.values) {
      testWidgets('$style: its own height; long labels share a narrow '
          'width without overflowing', (tester) async {
        await pumpIn(
          tester,
          style,
          const SizedBox(
            width: 180,
            child: Align(
              alignment: Alignment.centerLeft,
              child: AppSegmentedControl<String>(
                options: options,
                value: 'whole',
                onChanged: _ignore,
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(
          tester
              .renderObject<RenderParagraph>(find.text(options.first.$2))
              .didExceedMaxLines,
          isTrue,
          reason: 'the long label ends in an ellipsis',
        );
        final size = tester.getSize(find.byType(AppSegmentedControl<String>));
        expect(size.width, lessThanOrEqualTo(180));
        expect(size.height, AppMetrics.of(style).controlHeight);
      });
    }

    testWidgets('Fluent\'s pill sits under the selected label, not on it', (
      tester,
    ) async {
      await pumpIn(
        tester,
        AppPlatformStyle.windows,
        const AppSegmentedControl<String>(
          options: options,
          value: 'doc',
          onChanged: _ignore,
        ),
      );
      final label = tester.getRect(find.text('Текущий документ'));
      final accent = AppTheme.light(
        AppPlatformStyle.windows,
      ).extension<AppColorsExt>()!.accent;
      final pill = tester.getRect(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              (w.decoration as BoxDecoration?)?.color == accent &&
              w.constraints?.maxHeight == 3,
        ),
      );
      expect(pill.top, greaterThanOrEqualTo(label.bottom));
      expect(
        pill.bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byType(AppSegmentedControl<String>)).bottom,
        ),
      );
    });

    testWidgets('takes only its labels\' width where there is room; ←/→ '
        'step the choice', (tester) async {
      var value = 'whole';
      await pumpIn(
        tester,
        AppPlatformStyle.macos,
        StatefulBuilder(
          builder: (context, setState) => AppSegmentedControl<String>(
            options: options,
            value: value,
            onChanged: (v) => setState(() => value = v),
          ),
        ),
      );
      for (final (_, label) in options) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(label),
        );
        expect(paragraph.didExceedMaxLines, isFalse, reason: label);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(value, 'doc');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(value, 'doc', reason: 'stops at the end');
    });
  });

  group('FocusRing', () {
    testWidgets('paints outside the control and takes no layout space', (
      tester,
    ) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      for (final style in AppPlatformStyle.values) {
        final node = FocusNode();
        await pumpIn(
          tester,
          style,
          Focus(
            focusNode: node,
            child: Builder(
              builder: (context) => const FocusRing(
                child: SizedBox(width: 80, height: 22),
              ),
            ),
          ),
        );
        expect(tester.getSize(find.byType(FocusRing)), const Size(80, 22));
        CustomPaint ring() => tester.widget<CustomPaint>(
          find.descendant(
            of: find.byType(FocusRing),
            matching: find.byType(CustomPaint),
          ),
        );
        expect(ring().foregroundPainter, isNull, reason: 'no ring unfocused');
        node.requestFocus();
        await tester.pump();
        final painter = ring().foregroundPainter! as FocusRingPainter;
        final metrics = AppMetrics.of(style);
        expect(painter.width, metrics.focusRingWidth, reason: '$style');
        expect(
          painter.color,
          AppTheme.light(style).extension<AppColorsExt>()!.focusRing,
        );
        expect(tester.getSize(find.byType(FocusRing)), const Size(80, 22));
        node.dispose();
      }
    });
  });

  testWidgets('a ringed control keeps the focus it gains (the ring never '
      'rebuilds the child)', (tester) async {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(
      () => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic,
    );
    final outer = FocusNode(debugLabel: 'row');
    addTearDown(outer.dispose);
    await pumpIn(
      tester,
      AppPlatformStyle.macos,
      Focus(
        focusNode: outer,
        child: Builder(
          builder: (context) => FocusRing(
            child: InkWell(onTap: () {}, child: const Text('row')),
          ),
        ),
      ),
    );
    final inner = Focus.of(tester.element(find.text('row')));
    inner.requestFocus();
    await tester.pump();
    await tester.pump();
    expect(inner.hasPrimaryFocus, isTrue);
    expect(inner.context, isNotNull, reason: 'still mounted');
    expect(
      (tester
              .widget<CustomPaint>(
                find.descendant(
                  of: find.byType(FocusRing),
                  matching: find.byType(CustomPaint),
                ),
              )
              .foregroundPainter)
          is FocusRingPainter,
      isTrue,
    );
  });

  testWidgets('AppPopupButton shows the choice, opens the others with the '
      'current one checked and lit, and reports a pick', (tester) async {
    String value = 'all';
    await pumpIn(
      tester,
      AppPlatformStyle.windows,
      StatefulBuilder(
        builder: (context, setState) => AppPopupButton<String>(
          value: value,
          items: const [('all', 'All documents'), ('neuro', 'Neuroscience')],
          onChanged: (v) => setState(() => value = v),
        ),
      ),
    );
    expect(find.text('All documents'), findsOneWidget);
    await tester.tap(find.text('All documents'));
    await tester.pumpAndSettle();
    final checked = tester.widget<AppMenuItem>(
      find.widgetWithText(AppMenuItem, 'All documents'),
    );
    expect(checked.checked, isTrue);
    // It opens lit, as native pop-ups do, so the keys step from it.
    expect(checked.selected, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      tester
          .widget<AppMenuItem>(find.widgetWithText(AppMenuItem, 'Neuroscience'))
          .selected,
      isTrue,
    );
    await tester.tap(find.text('Neuroscience'));
    await tester.pumpAndSettle();
    expect(value, 'neuro');
    expect(find.text('Neuroscience'), findsOneWidget);
  });
}

void _ignore(String _) {}
