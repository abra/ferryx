import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ferryx/app/window_frame.dart';

void main() {
  group('WindowButtonLayout.parse', () {
    test('reads gsettings output: quoted, with appmenu and spacers', () {
      expect(
        WindowButtonLayout.parse("'appmenu:minimize,maximize,close'\n"),
        const WindowButtonLayout(
          trailing: [
            WindowButton.minimize,
            WindowButton.maximize,
            WindowButton.close,
          ],
        ),
      );
      expect(
        WindowButtonLayout.parse('close,minimize:appmenu'),
        const WindowButtonLayout(
          leading: [WindowButton.close, WindowButton.minimize],
          trailing: [],
        ),
      );
      expect(
        WindowButtonLayout.parse("'appmenu:close'"),
        WindowButtonLayout.gnomeDefault,
      );
    });

    test('without a colon every button is on the left; junk is skipped', () {
      expect(
        WindowButtonLayout.parse('close'),
        const WindowButtonLayout(leading: [WindowButton.close], trailing: []),
      );
      expect(
        WindowButtonLayout.parse('icon,spacer:menu'),
        const WindowButtonLayout(leading: [], trailing: []),
      );
    });
  });

  group('WindowFrame', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('macOS keeps the traffic lights in the content, Windows its own '
        'title bar', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final mac = await WindowFrame.detect();
      expect(mac.kind, WindowFrameKind.trafficLights);
      expect(mac.integrated, isTrue);
      expect(mac.leadingInset, WindowFrame.trafficLightsInset);
      expect(mac.trailingInset, 0);

      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final windows = await WindowFrame.detect();
      expect(windows.kind, WindowFrameKind.system);
      expect(windows.integrated, isFalse);
      expect(windows.leadingInset + windows.trailingInset, 0);
    });

    test('GNOME gets the app\'s header bar with the user\'s buttons; other '
        'Linux desktops keep their decorations', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      Future<ProcessResult> gsettings(String _, List<String> args) async {
        expect(args.last, 'button-layout');
        return ProcessResult(0, 0, "'appmenu:minimize,maximize,close'\n", '');
      }

      final ubuntu = await WindowFrame.detect(
        environment: {'XDG_CURRENT_DESKTOP': 'ubuntu:GNOME'},
        run: gsettings,
      );
      expect(ubuntu.kind, WindowFrameKind.headerBar);
      expect(ubuntu.buttons.trailing, hasLength(3));
      expect(
        ubuntu.trailingInset,
        3 * WindowFrame.headerBarButtonSlot + 6,
      );
      expect(ubuntu.leadingInset, 0);

      final kde = await WindowFrame.detect(
        environment: {'XDG_CURRENT_DESKTOP': 'KDE'},
        run: gsettings,
      );
      expect(kde.kind, WindowFrameKind.system);
    });

    test(
      'a GNOME session without gsettings falls back to a close button',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        final frame = await WindowFrame.detect(
          environment: {'XDG_CURRENT_DESKTOP': 'GNOME'},
          run: (_, _) async => throw const ProcessException('gsettings', []),
        );
        expect(frame.buttons, WindowButtonLayout.gnomeDefault);
        expect(frame.trailingInset, WindowFrame.headerBarButtonSlot + 6);
      },
    );

    test('forPlatform is the guess tests and the first frame use', () {
      expect(
        WindowFrame.forPlatform(TargetPlatform.linux).kind,
        WindowFrameKind.headerBar,
      );
      expect(
        WindowFrame.forPlatform(TargetPlatform.macOS),
        const WindowFrame(WindowFrameKind.trafficLights),
      );
    });
  });
}
