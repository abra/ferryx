import 'package:component_library/component_library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('dots overlap and stop at three', () {
    expect(AppTagDots.widthOf(0, 10), 0);
    expect(AppTagDots.widthOf(1, 10), 10);
    expect(AppTagDots.widthOf(2, 10), 16);
    expect(AppTagDots.widthOf(5, 10), AppTagDots.widthOf(3, 10));
  });

  testWidgets('tag colours follow the brightness', (tester) async {
    late Color light;
    late Color dark;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        home: Builder(
          builder: (context) {
            light = AppTagColors.of(context, 6);
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(AppPlatformStyle.macos),
        home: Builder(
          builder: (context) {
            dark = AppTagColors.of(context, 6);
            return const SizedBox();
          },
        ),
      ),
    );
    // The theme animates to the new brightness.
    await tester.pumpAndSettle();
    expect(light, isNot(dark));
    expect(AppTagColors.menuOrder.toSet(), {1, 2, 3, 4, 5, 6, 7});
  });

  testWidgets('the dots take their own width, three at most', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        home: const Center(
          child: AppTagDots(colors: [6, 4, 2, 1], size: 10, ring: Colors.white),
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(AppTagDots)),
      const Size(22, 10),
    );
  });

  testWidgets('a menu item shows a dash for a mixed state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        home: const Scaffold(
          body: Column(
            children: [
              AppMenuItem(label: 'all', checked: true),
              AppMenuItem(label: 'some', checked: false, mixed: true),
              AppMenuItem(label: 'none', checked: false),
            ],
          ),
        ),
      ),
    );
    expect(find.byIcon(AppIcons.check), findsOneWidget);
    expect(find.byIcon(AppIcons.minus), findsOneWidget);
  });
}
