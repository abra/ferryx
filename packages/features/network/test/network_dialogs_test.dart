import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_feature/network_feature.dart';
import 'package:network_service/testing.dart';
import 'package:shortcuts/shortcuts.dart';

const web = ServerProfile(
  id: 'web',
  name: 'Web',
  protocol: ServerProtocol.sftp,
  host: 'web.example.com',
  user: 'deploy',
);
const nas = ServerProfile(
  id: 'nas',
  protocol: ServerProtocol.davs,
  host: 'nas.lan',
);

final en = lookupFerryxLocalizations(const Locale('en'));

/// The app around [child], in the light macOS theme, English.
Widget app(Widget child, {double textScale = 1}) => MaterialApp(
  theme: AppTheme.light(AppPlatformStyle.macos),
  locale: const Locale('en'),
  localizationsDelegates: FerryxSupportedLocales.delegates,
  supportedLocales: FerryxSupportedLocales.locales,
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(body: child),
    ),
  ),
);

void main() {
  const limit = Timeout(Duration(seconds: 40));
  late FakeNetworkService service;

  setUp(() => service = FakeNetworkService());

  Future<void> sized(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('Connect to Server', () {
    late List<List<ServerProfile>> saved;
    late Future<ServerConnection?> result;

    Future<void> open(
      WidgetTester tester, {
      List<String> recent = const [],
    }) async {
      await sized(tester);
      saved = [];
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => result = showConnectDialog(
                  context,
                  service: service,
                  servers: const [web, nas],
                  onServersChanged: saved.add,
                  shortcutMap: ShortcutMap.defaults(TargetPlatform.macOS),
                  recent: recent,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    String field(WidgetTester tester) =>
        tester.widget<TextField>(find.byType(TextField).first).controller!.text;

    testWidgets(timeout: limit, 'the arrows in the field walk the list, Return connects', (
      tester,
    ) async {
      await open(tester, recent: const ['ftp://files.lan']);
      expect(find.text(en.networkConnectTitle), findsOneWidget);
      expect(find.text('Web'), findsOneWidget);
      expect(find.text(en.networkRecent), findsOneWidget);
      expect(field(tester), 'sftp://deploy@web.example.com');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(field(tester), 'davs://nas.lan');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(field(tester), 'ftp://files.lan');
      // Plain FTP crosses the network in the clear: said under the field.
      expect(find.text(en.networkInsecure), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(find.text(en.networkInsecure), findsNothing);
      // Return in the field: its submit.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final connection = await result;
      expect(connection?.server, 'davs://nas.lan:443');
      expect(service.connected.single, nas);
      expect(find.text(en.networkConnectTitle), findsNothing);
    });

    testWidgets(timeout: limit, 'an address typed, a failure said, Esc gives up', (
      tester,
    ) async {
      final never = Completer<ServerConnection>();
      var attempts = 0;
      service.onConnect = (profile, _) async {
        attempts++;
        if (attempts == 1) {
          throw const FerryxException(
            FerryxErrorKind.hostUnreachable,
            'box.lan:22',
          );
        }
        return never.future;
      };
      await open(tester);
      await tester.enterText(find.byType(TextField).first, 'sftp://me@box.lan');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        find.text(
          en.errorMessage(
            const FerryxException(
              FerryxErrorKind.hostUnreachable,
              'box.lan:22',
            ),
          ),
        ),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField).first, 'gopher://x');
      await tester.pump();
      expect(find.text(en.networkNotAnAddress('gopher://x')), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'sftp://me@box.lan');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(
        find.text(en.networkConnecting('sftp://me@box.lan')),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(await result, isNull);
      expect(service.cancelled, 1);
    });

    testWidgets(timeout: limit, 'servers are added from the address typed and removed', (
      tester,
    ) async {
      await open(tester);
      await tester.enterText(
        find.byType(TextField).first,
        'ftps://me@files.lan/pub',
      );
      await tester.pump();
      await tester.tap(find.text(en.networkAddServer));
      await tester.pumpAndSettle();
      expect(find.text(en.networkServerNew), findsOneWidget);
      // The editor starts from the address: its host is filled.
      expect(find.widgetWithText(TextField, 'files.lan'), findsOneWidget);
      await tester.tap(find.text(en.actionSave));
      await tester.pumpAndSettle();
      expect(saved.last.map((s) => s.host), [
        'web.example.com',
        'nas.lan',
        'files.lan',
      ]);
      expect(saved.last.last.protocol, ServerProtocol.ftps);
      expect(saved.last.last.path, '/pub');

      await tester.tap(find.text(en.networkRemoveServer).first);
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(OutlinedButton, en.networkRemoveServer).last,
      );
      await tester.pumpAndSettle();
      expect(saved.last.map((s) => s.host), ['web.example.com', 'nas.lan']);
    });
  });

  group('the questions of a connection', () {
    Future<void> host(WidgetTester tester) async {
      await sized(tester);
      await tester.pumpWidget(
        app(
          NetworkPromptHost(service: service, child: const SizedBox.expand()),
        ),
      );
    }

    testWidgets(timeout: limit, 'an unknown host key: Return does not trust it', (
      tester,
    ) async {
      await host(tester);
      const question = HostKeyQuestion(
        id: 1,
        server: 'sftp://me@box.lan:22',
        host: 'box.lan',
        port: 22,
        algorithm: 'ssh-ed25519',
        fingerprint: 'SHA256:47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU',
      );
      service.ask(question);
      await tester.pumpAndSettle();
      expect(find.text(question.fingerprint), findsOneWidget);
      expect(
        find.text(en.networkHostKeyMessage('box.lan', 'ssh-ed25519')),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(service.answers[1]?.accept, isFalse);

      service.ask(
        const HostKeyQuestion(
          id: 2,
          server: 'sftp://me@box.lan:2222',
          host: 'box.lan',
          port: 2222,
          algorithm: 'ecdsa-sha2-nistp256',
          fingerprint: 'SHA256:x',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          en.networkHostKeyMessage('box.lan:2222', 'ecdsa-sha2-nistp256'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text(en.networkHostKeyTrust));
      await tester.pumpAndSettle();
      expect(
        service.answers[2],
        const NetworkAnswer(accept: true, remember: true),
      );
    });

    testWidgets(timeout: limit, 'a password asked again, kept on request', (tester) async {
      await host(tester);
      service.ask(
        const PasswordQuestion(
          id: 3,
          server: 'ftp://me@files.lan:21',
          user: 'me',
          retry: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(en.networkPasswordTitle('ftp://me@files.lan')),
        findsOneWidget,
      );
      expect(find.text(en.networkPasswordWrong), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'secret');
      await tester.tap(find.text(en.networkRememberPassword));
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        service.answers[3],
        const NetworkAnswer(accept: true, texts: ['secret'], remember: true),
      );
    });

    testWidgets(timeout: limit, 'questions come one after another; a withdrawn one closes', (
      tester,
    ) async {
      await host(tester);
      service
        ..ask(
          const PassphraseQuestion(
            id: 4,
            server: 'sftp://me@a:22',
            keyPath: '/k/id',
            retry: false,
          ),
        )
        ..ask(
          const PromptsQuestion(
            id: 5,
            server: 'sftp://me@a:22',
            name: '',
            instructions: 'Two factors',
            prompts: [('Code:', true), ('PIN:', false)],
          ),
        );
      await tester.pumpAndSettle();
      expect(find.text(en.networkPassphraseMessage('/k/id')), findsOneWidget);
      expect(find.text('Two factors'), findsNothing);
      service.withdraw(4);
      await tester.pumpAndSettle();
      // Closed without an answer: the core gave up on it.
      expect(service.answers.containsKey(4), isFalse);
      expect(find.text('Two factors'), findsOneWidget);
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '123456');
      await tester.enterText(fields.at(1), '0000');
      await tester.tap(find.text(en.networkContinue));
      await tester.pumpAndSettle();
      expect(service.answers[5]?.texts, ['123456', '0000']);
    });

    testWidgets(timeout: limit, 'a changed key is an alarm with nothing to go on with', (
      tester,
    ) async {
      await sized(tester);
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => FilledButton(
              onPressed: () => showHostKeyChangedDialog(
                context,
                server: 'sftp://me@box.lan:22',
                detail: '~/.ssh/known_hosts:12',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text(en.networkHostKeyChangedTitle), findsOneWidget);
      expect(find.text('~/.ssh/known_hosts:12'), findsOneWidget);
      expect(find.byType(FilledButton).evaluate().length, 2);
      expect(find.byType(OutlinedButton), findsNothing);
    });
  });

  group('the server editor', () {
    testWidgets(timeout: limit, 'a host and a port that read, the rest as typed', (
      tester,
    ) async {
      await sized(tester);
      late Future<ServerProfile?> result;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => FilledButton(
              onPressed: () => result = showServerEditor(
                context,
                server: const ServerProfile(
                  id: 'n',
                  protocol: ServerProtocol.sftp,
                  host: '',
                ),
                isNew: true,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.actionSave));
      await tester.pumpAndSettle();
      expect(find.text(en.networkHostRequired), findsOneWidget);

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(1), 'box.lan');
      await tester.enterText(fields.at(2), '99999');
      await tester.tap(find.text(en.actionSave));
      await tester.pumpAndSettle();
      // Five figures fit; more than a port has do not.
      expect(find.text(en.networkPortInvalid), findsOneWidget);
      await tester.enterText(fields.at(2), '2222');
      await tester.enterText(fields.at(3), 'me');
      // SFTP logs in with keys or a password; FTP has no such choice.
      expect(find.text(en.networkFieldAuth), findsOneWidget);
      await tester.tap(find.text(en.networkProtocolSftp));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.networkProtocolFtp).last);
      await tester.pumpAndSettle();
      expect(find.text(en.networkFieldAuth), findsNothing);
      expect(find.text(en.networkInsecure), findsOneWidget);
      await tester.tap(find.text(en.actionSave));
      await tester.pumpAndSettle();
      final server = await result;
      expect(
        (server?.protocol, server?.host, server?.port, server?.user),
        (ServerProtocol.ftp, 'box.lan', 2222, 'me'),
      );
      expect(server?.auth, ServerAuth.password);
    });
  });
}
