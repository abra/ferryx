import 'package:component_library/component_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('dialog actions keep the button foreground colours', (
    tester,
  ) async {
    final theme = AppTheme.light(AppPlatformStyle.macos);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: AppDialog(
            title: 'Title',
            body: Text('Body'),
            actions: [
              TextButton(onPressed: _noop, child: Text('Cancel')),
              FilledButton(onPressed: _noop, child: Text('Create')),
            ],
          ),
        ),
      ),
    );
    final create = tester.widget<DefaultTextStyle>(
      find
          .ancestor(
            of: find.text('Create'),
            matching: find.byType(DefaultTextStyle),
          )
          .first,
    );
    final expected = theme.filledButtonTheme.style!.foregroundColor!.resolve(
      {},
    );
    expect(create.style.color, expected);
    final cancel = tester.widget<DefaultTextStyle>(
      find
          .ancestor(
            of: find.text('Cancel'),
            matching: find.byType(DefaultTextStyle),
          )
          .first,
    );
    expect(
      cancel.style.color,
      theme.textButtonTheme.style!.foregroundColor!.resolve({}),
    );
  });

  group('an alert\'s two buttons', () {
    Future<void> pumpAlert(
      WidgetTester tester, {
      required String cancel,
      required String confirm,
      double textScale = 1,
    }) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: Center(
              child: AppDialog(
                title: 'Delete?',
                alert: true,
                actions: [
                  OutlinedButton(onPressed: _noop, child: Text(cancel)),
                  FilledButton(onPressed: _noop, child: Text(confirm)),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    Rect buttonOf(WidgetTester tester, String label) => tester.getRect(
      find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );

    testWidgets('stand side by side, equally wide, when both labels fit', (
      tester,
    ) async {
      await pumpAlert(tester, cancel: 'No', confirm: 'Yes');
      final no = buttonOf(tester, 'No');
      final yes = buttonOf(tester, 'Yes');
      expect(no.top, yes.top);
      expect(no.width, yes.width);
      // NSAlert on macOS 15: 12 apart, 28 high.
      expect(yes.left - no.right, AppSpacing.md);
      expect(no.height, greaterThanOrEqualTo(28));
    });

    testWidgets('stack when a label is wider than its share by any fraction '
        'of a pixel: a label never wraps', (tester) async {
      // The macOS alert: 260 wide, 18 in, its buttons 12 apart.
      const share = (260 - 2 * 18 - AppSpacing.md) / 2;
      Future<bool> sideBySide(double width) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(AppPlatformStyle.macos),
            home: Scaffold(
              body: Center(
                child: AppDialog(
                  title: 'Delete?',
                  alert: true,
                  actions: [
                    const SizedBox(key: Key('cancel'), width: 40, height: 20),
                    SizedBox(
                      key: const Key('confirm'),
                      width: width,
                      height: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        return tester.getRect(find.byKey(const Key('cancel'))).top ==
            tester.getRect(find.byKey(const Key('confirm'))).top;
      }

      expect(await sideBySide(share), isTrue);
      expect(await sideBySide(share + 0.3), isFalse);
    });

    testWidgets('stack, the default on top, when a label does not fit', (
      tester,
    ) async {
      await pumpAlert(
        tester,
        cancel: 'Cancel',
        confirm: 'Move everything to trash',
      );
      final cancel = buttonOf(tester, 'Cancel');
      final confirm = buttonOf(tester, 'Move everything to trash');
      expect(confirm.bottom, lessThan(cancel.top));
      expect(cancel.top - confirm.bottom, AppSpacing.md);
      expect(confirm.width, cancel.width);
      expect(confirm.left, cancel.left);
      expect(tester.takeException(), isNull);
    });

    testWidgets('on macOS: the other button a grey plate without a bezel, '
        'its label 8 in', (tester) async {
      await pumpAlert(tester, cancel: 'No', confirm: 'Yes');
      final no = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      final style = Theme.of(
        tester.element(find.text('No')),
      ).outlinedButtonTheme.style!;
      expect(no.style, isNull);
      expect(style.side?.resolve(const {}), BorderSide.none);
      expect(
        style.backgroundColor?.resolve(const {}),
        Colors.black.withValues(alpha: 0.12),
      );
      expect(
        (style.padding?.resolve(const {}) as EdgeInsets?)?.left,
        AppSpacing.sm,
      );
    });

    testWidgets('take the alert radii of libadwaita on GNOME', (tester) async {
      Future<(double, double)> radii(AppPlatformStyle style) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(style),
            home: const Scaffold(
              body: Center(
                child: AppDialog(
                  title: 'Delete?',
                  alert: true,
                  actions: [
                    OutlinedButton(onPressed: _noop, child: Text('No')),
                    FilledButton(onPressed: _noop, child: Text('Yes')),
                  ],
                ),
              ),
            ),
          ),
        );
        // MaterialApp animates a change of theme.
        await tester.pumpAndSettle();
        final dialog = tester.widget<Material>(
          find
              .descendant(
                of: find.byType(Dialog),
                matching: find.byType(Material),
              )
              .first,
        );
        final button = tester.widget<Material>(
          find
              .ancestor(of: find.text('Yes'), matching: find.byType(Material))
              .first,
        );
        double of(ShapeBorder? shape) =>
            ((shape! as RoundedRectangleBorder).borderRadius as BorderRadius)
                .topLeft
                .x;
        return (of(dialog.shape), of(button.shape));
      }

      expect(await radii(AppPlatformStyle.gnome), (18.0, 12.0));
      final mac = AppMetrics.of(AppPlatformStyle.macos).radius;
      expect(await radii(AppPlatformStyle.macos), (mac.dialog, mac.control));
    });

    testWidgets('grow taller with the text size', (tester) async {
      await pumpAlert(tester, cancel: 'No', confirm: 'Yes');
      final small = buttonOf(tester, 'Yes').height;
      await pumpAlert(tester, cancel: 'No', confirm: 'Yes', textScale: 1.6);
      expect(buttonOf(tester, 'Yes').height, greaterThan(small));
    });
  });
}

void _noop() {}
