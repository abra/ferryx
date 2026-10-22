// A widget that reacts to state changes its properties, never the shape of
// its subtree: a new parent remounts the subtree, which drops its focus and
// resets its scroll positions (the PDF zoom once jumped to the cover so).

import 'package:component_library/component_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('FocusRing keeps its child mounted when decorate flips', (
    tester,
  ) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    Future<void> pump({required bool decorate}) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        home: Material(
          child: Focus(
            child: Builder(
              builder: (context) => FocusRing(
                decorate: decorate,
                child: TextField(focusNode: node),
              ),
            ),
          ),
        ),
      ),
    );
    await pump(decorate: true);
    node.requestFocus();
    await tester.pump();
    final field = tester.state<EditableTextState>(find.byType(EditableText));
    await pump(decorate: false);
    expect(
      tester.state<EditableTextState>(find.byType(EditableText)),
      same(field),
    );
    expect(node.hasFocus, isTrue);
  });
}
