import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preferences_service/preferences_service.dart';

void main() {
  testWidgets('builds from the value it selects, again only when that value '
      'changes', (tester) async {
    final service = await PreferencesService.create(
      storage: InMemoryPreferencesStorage(),
    );
    var builds = 0;
    await tester.pumpWidget(
      PreferenceBuilder<bool>(
        service: service,
        select: (p) => p.singlePane,
        builder: (context, single) {
          builds++;
          return Text('$single', textDirection: TextDirection.ltr);
        },
      ),
    );
    expect(builds, 1);
    await service.update((p) => p.copyWith(splitFraction: 0.3));
    await tester.pump();
    expect(builds, 1);
    await service.update((p) => p.copyWith(singlePane: true));
    await tester.pump();
    expect(builds, 2);
    expect(find.text('true'), findsOneWidget);
    await service.dispose();
  });
}
