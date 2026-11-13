import 'package:component_library/component_library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<BuildContext> pump(WidgetTester tester) async {
    late BuildContext inside;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.of(AppPlatformStyle.macos, Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              inside = context;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    return inside;
  }

  testWidgets('a notice takes the place of the one showing', (tester) async {
    final context = await pump(tester);
    showAppNotice(context, 'Imported 9 rems and 6 cards');
    await tester.pumpAndSettle();
    showAppNotice(context, 'Exported to ~/Documents');
    await tester.pumpAndSettle();
    expect(find.text('Imported 9 rems and 6 cards'), findsNothing);
    expect(find.text('Exported to ~/Documents'), findsOneWidget);
  });

  testWidgets('nothing clips the plate, so its shadow shows whole', (
    tester,
  ) async {
    final context = await pump(tester);
    showAppNotice(context, 'Imported 9 rems and 6 cards');
    await tester.pumpAndSettle();
    final clips = tester.widgetList<ClipRect>(
      find.ancestor(
        of: find.text('Imported 9 rems and 6 cards'),
        matching: find.byType(ClipRect),
      ),
    );
    expect(clips.map((clip) => clip.clipBehavior), everyElement(Clip.none));
    final plate = tester.widget<Material>(
      find
          .ancestor(
            of: find.text('Imported 9 rems and 6 cards'),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(plate.elevation, greaterThan(0), reason: 'a plate with a shadow');
  });
}
