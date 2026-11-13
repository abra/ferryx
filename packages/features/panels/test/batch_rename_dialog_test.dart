import 'package:domain_models/domain_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

import 'support/workspace_harness.dart';

void main() {
  setUpAll(() {
    WorkspaceHarness.registerFallbacks();
    registerFallbackValue(const RenameOptions());
  });

  late WorkspaceHarness h;

  setUp(() async {
    h = WorkspaceHarness();
    await h.setUp();
    h.addFolder('/photos', [
      for (var i = 0; i < 16; i++) 'IMG_${4012 + i}.jpg',
    ]);
    when(() => h.rename.preview(any(), any())).thenAnswer((call) async {
      final paths = call.positionalArguments[0] as List<String>;
      return [
        for (final path in paths)
          RenameOutcome(
            path: path,
            oldName: path.split('/').last,
            newName: path.split('/').last,
          ),
      ];
    });
  });

  tearDown(() => h.tearDown());

  testWidgets('in a low window the preview shrinks and the buttons stay in '
      'it', (tester) async {
    await h.pump(tester, left: '/photos', size: const Size(1180, 740));
    await h.press(tester, LogicalKeyboardKey.keyA, meta: true);
    await h.press(tester, LogicalKeyboardKey.keyM, control: true);
    expect(find.text('Rename 16 items'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final button = tester.getRect(
      find.widgetWithText(FilledButton, 'Rename'),
    );
    expect(button.bottom, lessThanOrEqualTo(740));
  });
}
