import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panels_feature/src/panel/panel_state.dart';
import 'package:panels_feature/src/panel/panel_view.dart';

/// The strip under the rows says what is the matter, of what, and what
/// its button does: a fault in red, a state to act on without alarm.
void main() {
  final en = lookupFerryxLocalizations(const Locale('en'));

  PanelTabState tab(Location location, {Location? password}) => PanelTabState(
    id: 't',
    location: location,
    sort: const SortOptions(),
    passwordLocation: password,
  );

  test('an archive that waits for its password is named, not the folder', () {
    final text = errorStripOf(
      en,
      tab(
        const Location.native('/data'),
        password: const Location.inArchive(archive: '/data/locked.7z'),
      ),
      const FerryxException(FerryxErrorKind.passwordRequired, ''),
    );
    expect(text.title, en.archivePasswordTitle('locked.7z'));
    expect(text.action, en.archiveEnterPassword);
    expect(text.fault, isFalse);
  });

  test('a server not connected yet is a state with Connect; a dropped one '
      'is a fault with Reconnect', () {
    const server = Location.remote(
      server: 'sftp://me@example.com:22',
      path: '/srv',
    );
    final waiting = errorStripOf(
      en,
      tab(server),
      const FerryxException(FerryxErrorKind.notConnected, ''),
    );
    expect(waiting.title, en.errorNotConnected);
    expect(waiting.message, server.display);
    expect(waiting.action, en.networkConnect);
    expect(waiting.fault, isFalse);
    final lost = errorStripOf(
      en,
      tab(server),
      const FerryxException(FerryxErrorKind.connectionLost, ''),
    );
    expect(lost.title, en.errorConnectionLost);
    expect(lost.action, en.networkReconnect);
    expect(lost.fault, isTrue);
  });

  test('a folder that cannot be read says why, with Retry', () {
    final text = errorStripOf(
      en,
      tab(const Location.native('/gone')),
      const FerryxException(FerryxErrorKind.notFound, '/gone'),
    );
    expect(text.title, en.panelErrorTitle);
    expect(text.action, en.actionRetry);
    expect(text.fault, isTrue);
  });
}
