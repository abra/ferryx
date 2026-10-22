import 'package:domain_models/domain_models.dart';
import 'package:ferryx/app/dependency_container.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_services/platform_services.dart';
import 'package:shortcuts/shortcuts.dart';

/// A command whose capability the desktop lacks is not offered at all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const macCore = Capabilities(finderTags: true, spotlight: true);

  test('every capability there: every command offered', () {
    expect(
      unavailableCommandsFor(
        const PlatformCapabilities(quickLook: true, share: true),
        macCore,
      ),
      isEmpty,
    );
  });

  test('none there: Quick Look, Share and tags are not offered', () {
    expect(
      unavailableCommandsFor(PlatformCapabilities.none, const Capabilities()),
      {AppCommand.quickLook, AppCommand.share, AppCommand.editTags},
    );
  });

  test('the core decides the tags, the services the rest', () {
    expect(
      unavailableCommandsFor(
        const PlatformCapabilities(quickLook: true, share: true),
        const Capabilities(),
      ),
      {AppCommand.editTags},
    );
    expect(unavailableCommandsFor(PlatformCapabilities.none, macCore), {
      AppCommand.quickLook,
      AppCommand.share,
    });
  });

  test("each desktop's services decide its commands", () async {
    for (final (platform, core, hidden) in [
      (TargetPlatform.macOS, macCore, <AppCommand>{}),
      (
        TargetPlatform.windows,
        const Capabilities(),
        {AppCommand.quickLook, AppCommand.share, AppCommand.editTags},
      ),
      (
        TargetPlatform.linux,
        const Capabilities(),
        {AppCommand.quickLook, AppCommand.share, AppCommand.editTags},
      ),
    ]) {
      final services = PlatformServices.forPlatform(platform);
      final unavailable = unavailableCommandsFor(services.capabilities, core);
      expect(unavailable, hidden, reason: '$platform');
      final map = ShortcutMap.forUser(platform, unavailable: unavailable);
      for (final command in hidden) {
        expect(map.chordsFor(command), isEmpty, reason: '$command');
        expect(map.isAvailable(command), isFalse, reason: '$command');
      }
      await services.dispose();
    }
  });
}
