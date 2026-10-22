import 'package:ferryx/app/dependency_container.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_services/platform_services.dart';
import 'package:shortcuts/shortcuts.dart';

/// A command whose capability the desktop lacks is not offered at all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every capability there: every command offered', () {
    expect(
      unavailableCommandsFor(
        const PlatformCapabilities(quickLook: true, share: true),
      ),
      isEmpty,
    );
  });

  test('none there: Quick Look and Share are not offered', () {
    expect(unavailableCommandsFor(PlatformCapabilities.none), {
      AppCommand.quickLook,
      AppCommand.share,
    });
  });

  test("each desktop's services decide its commands", () async {
    for (final (platform, hidden) in [
      (TargetPlatform.macOS, <AppCommand>{}),
      (TargetPlatform.windows, {AppCommand.quickLook, AppCommand.share}),
      (TargetPlatform.linux, {AppCommand.quickLook, AppCommand.share}),
    ]) {
      final services = PlatformServices.forPlatform(platform);
      final unavailable = unavailableCommandsFor(services.capabilities);
      expect(unavailable, hidden, reason: '$platform');
      final map = ShortcutMap.forUser(platform, unavailable: unavailable);
      for (final command in hidden) {
        expect(map.chordsFor(command), isEmpty, reason: '$command');
      }
      await services.dispose();
    }
  });
}
