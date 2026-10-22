import 'package:component_library/component_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('with the focus above it, PageDown scrolls the largest view '
      'that can move; with the focus inside a list, that list', (
    tester,
  ) async {
    final pane = FocusNode(debugLabel: 'pane');
    final inList = FocusNode(debugLabel: 'in list');
    final page = ScrollController();
    final list = ScrollController();
    addTearDown(() {
      pane.dispose();
      inList.dispose();
      page.dispose();
      list.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppScrollKeys(
            child: Focus(
              focusNode: pane,
              child: SingleChildScrollView(
                controller: page,
                child: Column(
                  children: [
                    // A short list of its own, and a field: neither is the
                    // page.
                    SizedBox(
                      height: 120,
                      child: ListView(
                        controller: list,
                        children: [
                          Focus(focusNode: inList, child: const Text('row')),
                          for (var i = 0; i < 20; i++)
                            const SizedBox(height: 40),
                        ],
                      ),
                    ),
                    const TextField(maxLines: 4),
                    const SizedBox(height: 3000),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    pane.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    expect(page.offset, greaterThan(0));
    expect(list.offset, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.pumpAndSettle();
    expect(page.offset, 0);

    inList.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    expect(list.offset, greaterThan(0), reason: 'the nearest view moves');
    expect(page.offset, 0);
  });
}
