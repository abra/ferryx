import 'package:component_library/component_library.dart';
import 'package:ferryx/app/window_chrome.dart';
import 'package:ferryx/app/window_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  for (final generation in MacGeneration.values) {
    testWidgets(
      '$generation: full screen updates window corners without remounting content',
      (tester) async {
        final title = WindowTitle()..integrated = true;
        addTearDown(title.dispose);
        final node = FocusNode();
        addTearDown(node.dispose);
        final key = GlobalKey();
        var radius = 0.0;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.of(
              AppPlatformStyle.macos,
              Brightness.light,
              generation: generation,
            ),
            home: WindowChrome(
              title: title,
              frame: const WindowFrame(WindowFrameKind.trafficLights),
              child: Builder(
                builder: (context) {
                  radius = WindowDecor.of(context).cornerRadius;
                  return Scaffold(
                    body: TextField(key: key, focusNode: node),
                  );
                },
              ),
            ),
          ),
        );
        node.requestFocus();
        await tester.pumpAndSettle();
        final state = key.currentState;
        final rect = tester.getRect(find.byKey(key));
        final normal = AppMetrics.of(
          AppPlatformStyle.macos,
          generation: generation,
        ).radius.window;
        expect(radius, normal);
        expect(radius, greaterThan(0));
        final listener =
            tester.state(find.byType(WindowChrome)) as WindowListener;
        listener.onWindowEnterFullScreen();
        await tester.pumpAndSettle();
        expect(radius, 0);
        listener.onWindowLeaveFullScreen();
        await tester.pumpAndSettle();
        expect(radius, normal);
        expect(key.currentState, same(state));
        expect(tester.getRect(find.byKey(key)), rect);
        expect(node.hasFocus, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
