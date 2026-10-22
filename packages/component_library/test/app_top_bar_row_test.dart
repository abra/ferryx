import 'package:component_library/component_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Fixed widths, so where a form stops fitting is arithmetic: with the
  // macOS bar spacing (6) between neighbours and 8 between groups.
  Widget box(String name, double width, {VoidCallback? onTap}) =>
      GestureDetector(
        key: ValueKey(name),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(width: width, height: 20),
      );

  Future<void> pump(
    WidgetTester tester, {
    required double width,
    TextDirection direction = TextDirection.ltr,
    double? preferLaterBelow,
    List<Widget>? leading,
    List<List<Widget>>? forms,
    VoidCallback? onFull,
    AppPlatformStyle style = AppPlatformStyle.macos,
    double leftInset = 0,
    double rightInset = 0,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.of(style, Brightness.light),
      home: Directionality(
        textDirection: direction,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            height: 40,
            child: AppTopBarRow(
              leading: leading ?? [box('back', 20)],
              title: const Text('Title', key: ValueKey('title')),
              forms:
                  forms ??
                  [
                    [box('full', 300, onTap: onFull)],
                    [box('compact', 100)],
                  ],
              trailing: [box('panel', 20)],
              preferLaterBelow: preferLaterBelow,
              leftInset: leftInset,
              rightInset: rightInset,
            ),
          ),
        ),
      ),
    ),
  );

  bool shows(String name) => find.byKey(ValueKey(name)).evaluate().isNotEmpty;

  // The bar with the full form needs 20 + 300 + 20, three gaps of 8 and
  // the title's 64: 428; with the compact one 228.
  testWidgets('the richest form that fits shows; a narrower bar takes the '
      'next on the following frame, a wider one brings it back', (
    tester,
  ) async {
    await pump(tester, width: 500);
    expect(shows('full'), isTrue);
    expect(tester.getSize(find.byKey(const ValueKey('full'))).width, 300);
    // The title takes what is left, the actions sit at the end.
    expect(
      tester.getSize(find.byKey(const ValueKey('title'))).width,
      500 - 364,
    );
    expect(tester.getTopRight(find.byKey(const ValueKey('panel'))).dx, 500);

    await pump(tester, width: 420);
    await tester.pump();
    expect(shows('full'), isFalse);
    expect(shows('compact'), isTrue);

    await pump(tester, width: 200);
    await tester.pump();
    expect(shows('compact'), isFalse, reason: 'no form fits: none shows');
    expect(shows('back'), isTrue);
    expect(shows('panel'), isTrue);

    await pump(tester, width: 428);
    expect(shows('full'), isTrue, reason: 'a learned width needs no retry');
    expect(tester.takeException(), isNull);
  });

  testWidgets('for the frame before a too wide form gives way it is scaled '
      'down, not spilled, and still takes taps', (tester) async {
    var taps = 0;
    // 340 leaves the actions 276 of their 300.
    await pump(tester, width: 340, onFull: () => taps++);
    final full = find.byKey(const ValueKey('full'));
    final rect = tester.getRect(full);
    expect(rect.width, closeTo(276, 0.01));
    expect(rect.right, closeTo(340 - 20 - 8, 0.01));
    await tester.tapAt(rect.center);
    expect(taps, 1);
    expect(tester.takeException(), isNull);
    await tester.pump();
    expect(shows('compact'), isTrue);
  });

  testWidgets('under preferLaterBelow the compact form shows from the '
      'first frame', (tester) async {
    await pump(tester, width: 420, preferLaterBelow: 450);
    expect(shows('full'), isFalse);
    expect(shows('compact'), isTrue);
  });

  testWidgets('right to left, the order runs from the right', (tester) async {
    await pump(tester, width: 500, direction: TextDirection.rtl);
    expect(tester.getTopRight(find.byKey(const ValueKey('back'))).dx, 500);
    expect(tester.getTopLeft(find.byKey(const ValueKey('panel'))).dx, 0);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('full'))).dx,
      lessThan(tester.getTopLeft(find.byKey(const ValueKey('title'))).dx),
    );
  });

  group('a centred title (libadwaita)', () {
    Rect title(WidgetTester tester) =>
        tester.getRect(find.byKey(const ValueKey('title')));

    testWidgets('sits in the middle of the whole bar, not of the room '
        'between the buttons', (tester) async {
      await pump(
        tester,
        width: 600,
        style: AppPlatformStyle.gnome,
        leading: [box('back', 20), box('forward', 20)],
        forms: const [],
      );
      expect(title(tester).center.dx, moreOrLessEquals(300));
    });

    testWidgets('moves toward the free side as far as the buttons need, and '
        'never under them', (tester) async {
      await pump(tester, width: 600, style: AppPlatformStyle.gnome);
      // back, the title, the full form (300) and panel: the title ends a
      // group's gap before the form.
      final form = tester.getRect(find.byKey(const ValueKey('full')));
      expect(title(tester).right, moreOrLessEquals(form.left - 8));
      expect(
        title(tester).left,
        greaterThan(tester.getRect(find.byKey(const ValueKey('back'))).right),
      );
    });

    testWidgets('centres across the window buttons\' room as well, which '
        'nothing takes', (tester) async {
      await pump(
        tester,
        width: 600,
        style: AppPlatformStyle.gnome,
        leftInset: 12,
        rightInset: 40,
        forms: const [],
      );
      expect(title(tester).center.dx, moreOrLessEquals(300));
      expect(tester.getRect(find.byKey(const ValueKey('back'))).left, 12);
      expect(tester.getRect(find.byKey(const ValueKey('panel'))).right, 560);
    });

    testWidgets('right to left as well', (tester) async {
      await pump(
        tester,
        width: 600,
        style: AppPlatformStyle.gnome,
        direction: TextDirection.rtl,
        leading: [box('back', 20), box('forward', 20)],
        forms: const [],
      );
      expect(title(tester).center.dx, moreOrLessEquals(300));
    });

    testWidgets('elsewhere the title starts after the buttons', (
      tester,
    ) async {
      await pump(tester, width: 600, forms: const []);
      expect(
        title(tester).left,
        tester.getRect(find.byKey(const ValueKey('back'))).right + 8,
      );
    });
  });

  testWidgets('where even the leading and trailing controls do not fit, the '
      'bar clips instead of reporting an overflow', (tester) async {
    await pump(
      tester,
      width: 60,
      leading: [box('back', 20), box('forward', 20), box('fold', 20)],
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(shows('fold'), isTrue);
  });
}
