import 'dart:convert';

import 'package:bloc_test/bloc_test.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:preferences_service/preferences_service.dart';
import 'package:terminal_feature/terminal_feature.dart';
import 'package:terminal_service/terminal_service.dart';

import 'fakes.dart';

class _MockService extends Mock implements TerminalService {}

class _MockPreferences extends Mock implements PreferencesService {}

void main() {
  late _MockService service;
  late _MockPreferences preferences;
  late List<FakeSession> sessions;
  late List<TerminalStart> starts;

  setUpAll(() {
    registerFallbackValue(const TerminalStart(cols: 1, rows: 1));
  });

  setUp(() {
    service = _MockService();
    preferences = _MockPreferences();
    sessions = [];
    starts = [];
    when(() => preferences.current).thenReturn(
      const Preferences(
        terminal: TerminalPreferences(shell: '/bin/zsh', scrollback: 2000),
      ),
    );
    when(() => service.start(any())).thenAnswer((call) async {
      starts.add(call.positionalArguments.single as TerminalStart);
      final session = FakeSession();
      sessions.add(session);
      return session;
    });
  });

  TerminalSessionCubit build() => TerminalSessionCubit(
    service: service,
    preferences: preferences,
    platform: TargetPlatform.macOS,
    locale: 'en_US',
  );

  /// Lets the start and the stream's events run.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  /// A cubit with a running shell at its prompt in [folder].
  Future<TerminalSessionCubit> running({String folder = '/a'}) async {
    final cubit = build();
    cubit.terminal.resize(80, 24);
    cubit.show(folder);
    await settle();
    sessions.last.emit(TerminalShellState(idle: true, folder: folder));
    await settle();
    return cubit;
  }

  group('start', () {
    test('waits for the view\'s size, then starts in the panel\'s folder '
        'with the settings\' shell', () async {
      final cubit = build();
      cubit.show('/projects');
      await settle();
      verifyNever(() => service.start(any()));
      expect(cubit.state.status, TerminalStatus.stopped);
      cubit.terminal.resize(120, 40);
      await settle();
      expect(starts.single.folder, '/projects');
      expect(starts.single.shell, '/bin/zsh');
      expect(starts.single.locale, 'en_US');
      expect((starts.single.cols, starts.single.rows), (120, 40));
      expect(cubit.state.status, TerminalStatus.running);
      expect(cubit.terminal.maxLines, 2000);
      await cubit.close();
    });

    test('an empty shell setting asks for the user\'s own', () async {
      when(() => preferences.current).thenReturn(const Preferences());
      final cubit = build();
      cubit.terminal.resize(80, 24);
      cubit.show(null);
      await settle();
      expect(starts.single.shell, isNull);
      expect(starts.single.folder, isNull);
      await cubit.close();
    });

    blocTest<TerminalSessionCubit, TerminalSessionState>(
      'a shell that will not start is a typed failure; Return-restart '
      'tries again',
      setUp: () {
        var first = true;
        when(() => service.start(any())).thenAnswer((call) async {
          if (first) {
            first = false;
            throw const FerryxException(
              FerryxErrorKind.notFound,
              'missing',
              path: '/bin/nope',
            );
          }
          final session = FakeSession();
          sessions.add(session);
          return session;
        });
      },
      build: build,
      act: (cubit) async {
        cubit.terminal.resize(80, 24);
        cubit.show('/a');
        await settle();
        await cubit.restart();
      },
      expect: () => [
        const TerminalSessionState(status: TerminalStatus.starting),
        isA<TerminalSessionState>()
            .having((s) => s.status, 'status', TerminalStatus.failed)
            .having((s) => s.error?.kind, 'kind', FerryxErrorKind.notFound),
        const TerminalSessionState(status: TerminalStatus.starting),
        const TerminalSessionState(status: TerminalStatus.running),
      ],
    );
  });

  group('output and input', () {
    test(
      'output is decoded across batches, written and acknowledged',
      () async {
        final cubit = await running();
        final session = sessions.single;
        final bytes = utf8.encode('Привет ✓\r\n');
        // A letter split between two batches.
        session.emit(TerminalOutput(Uint8List.fromList(bytes.sublist(0, 3))));
        session.emit(TerminalOutput(Uint8List.fromList(bytes.sublist(3))));
        await settle();
        await settle();
        expect(
          cubit.terminal.buffer.lines[0].toString(),
          startsWith('Привет ✓'),
        );
        expect(session.acks, 2);
        await cubit.close();
      },
    );

    test('what the user types reaches the shell', () async {
      final cubit = await running();
      cubit.terminal.textInput('ls -l');
      cubit.terminal.textInput('\r');
      expect(sessions.single.text, 'ls -l\r');
      await cubit.close();
    });

    test('a resized view resizes the shell', () async {
      final cubit = await running();
      cubit.terminal.resize(100, 30);
      expect(sessions.single.resizes, [(100, 30)]);
      await cubit.close();
    });

    test(
      'paste goes in as text; select all and copy take the buffer',
      () async {
        final cubit = await running();
        sessions.single.emit(TerminalOutput(utf8.encode('hello\r\n')));
        await settle();
        cubit.paste('echo pasted');
        expect(sessions.single.text, 'echo pasted');
        expect(cubit.selectedText(), isNull);
        cubit.selectAll();
        expect(cubit.selectedText(), contains('hello'));
        await cubit.close();
      },
    );

    test('clear empties the scrollback and asks the shell for a fresh '
        'prompt', () async {
      final cubit = await running();
      for (var i = 0; i < 60; i++) {
        sessions.single.emit(TerminalOutput(utf8.encode('line $i\r\n')));
      }
      await settle();
      expect(cubit.terminal.buffer.height, greaterThan(24));
      cubit.clear();
      expect(cubit.terminal.buffer.height, 24);
      expect(sessions.single.written, [0x0c]);
      await cubit.close();
    });

    test('clear leaves a running program its screen', () async {
      final cubit = await running();
      sessions.single.emit(
        const TerminalShellState(idle: false, folder: '/a'),
      );
      await settle();
      cubit.clear();
      expect(sessions.single.written, isEmpty);
      await cubit.close();
    });
  });

  group('folder sync', () {
    test('the panel moving types cd while the terminal is shown', () async {
      final cubit = await running();
      cubit.followFolder('/b');
      await settle();
      expect(sessions.single.directories, ['/b']);
      await cubit.close();
    });

    test('hidden, the shell waits; shown again, it follows', () async {
      final cubit = await running();
      cubit.hide();
      cubit.followFolder('/b');
      cubit.followFolder('/c');
      await settle();
      expect(sessions.single.directories, isEmpty);
      cubit.show('/c');
      await settle();
      expect(sessions.single.directories, ['/c']);
      await cubit.close();
    });

    test('inside an archive nothing is sent', () async {
      final cubit = await running();
      cubit.followFolder(null);
      await settle();
      expect(sessions.single.directories, isEmpty);
      await cubit.close();
    });

    test('a half-typed line is not disturbed', () async {
      final cubit = await running();
      cubit.terminal.textInput('git sta');
      cubit.followFolder('/b');
      await settle();
      expect(sessions.single.directories, isEmpty);
      await cubit.close();
    });

    test('a cd typed in the shell sends the panel there', () async {
      final cubit = await running();
      final folders = <String>[];
      cubit.shellFolders.listen(folders.add);
      sessions.single
        ..emit(const TerminalShellState(idle: false, folder: '/a'))
        ..emit(const TerminalShellState(idle: true, folder: '/tmp'));
      await settle();
      expect(folders, ['/tmp']);
      expect(cubit.state.folder, '/tmp');
      expect(cubit.state.atPrompt, isTrue);
      await cubit.close();
    });

    test('the shell following the panel is not sent back to it', () async {
      final cubit = await running();
      final folders = <String>[];
      cubit.shellFolders.listen(folders.add);
      cubit.followFolder('/b');
      await settle();
      sessions.single.emit(const TerminalShellState(idle: true, folder: '/b'));
      await settle();
      expect(folders, isEmpty);
      await cubit.close();
    });
  });

  group('commands', () {
    test('typed at the prompt; refused while a program runs or a line is '
        'half typed', () async {
      final cubit = await running();
      final session = sessions.single;
      expect(cubit.runCommand('  make test '), isTrue);
      expect(session.text, 'make test\r');
      session.emit(const TerminalShellState(idle: false, folder: '/a'));
      await settle();
      expect(cubit.runCommand('ls'), isFalse);
      session.emit(const TerminalShellState(idle: true, folder: '/a'));
      await settle();
      cubit.terminal.textInput('echo hal');
      expect(cubit.runCommand('ls'), isFalse);
      await cubit.close();
    });

    test('asked before the shell is up, it runs at its first prompt', () async {
      final cubit = build();
      cubit.show('/a');
      expect(cubit.runCommand('htop'), isTrue);
      cubit.terminal.resize(80, 24);
      await settle();
      final session = sessions.single;
      expect(session.written, isEmpty);
      session.emit(const TerminalShellState(idle: true, folder: '/a'));
      await settle();
      expect(session.text, 'htop\r');
      await cubit.close();
    });

    test('asked after the shell ended, a new one starts and runs it', () async {
      final cubit = await running();
      sessions.single.emit(const TerminalExited(0));
      await settle();
      expect(cubit.runCommand('ls'), isTrue);
      await settle();
      expect(sessions, hasLength(2));
      sessions.last.emit(const TerminalShellState(idle: true, folder: '/a'));
      await settle();
      expect(sessions.last.text, 'ls\r');
      await cubit.close();
    });
  });

  group('the end', () {
    test('an exit shows the code; restart starts a new shell below the old '
        'output, in the panel\'s folder', () async {
      final cubit = await running();
      final first = sessions.single;
      first.emit(TerminalOutput(utf8.encode('before\r\n')));
      first.emit(const TerminalExited(3));
      await settle();
      await settle();
      expect(cubit.state.status, TerminalStatus.exited);
      expect(cubit.state.exitCode, 3);
      expect(first.closed, isTrue);
      // Typing into the ended shell goes nowhere.
      cubit.terminal.textInput('x');
      expect(first.written, isEmpty);
      cubit.followFolder('/z');
      await cubit.restart();
      expect(sessions, hasLength(2));
      expect(starts.last.folder, '/z');
      expect(cubit.state.status, TerminalStatus.running);
      expect(cubit.state.exitCode, isNull);
      expect(cubit.terminal.buffer.lines[0].toString(), startsWith('before'));
      await cubit.close();
    });

    test('a changed scrollback gives the new shell a new emulator', () async {
      final cubit = await running();
      final old = cubit.terminal;
      sessions.single.emit(const TerminalExited(0));
      await settle();
      when(() => preferences.current).thenReturn(
        const Preferences(terminal: TerminalPreferences(scrollback: 5000)),
      );
      await cubit.restart();
      expect(cubit.terminal, isNot(same(old)));
      expect(cubit.terminal.maxLines, 5000);
      expect(cubit.state.generation, 1);
      // The new emulator starts the shell once the view sizes it.
      expect(sessions, hasLength(1));
      cubit.terminal.resize(80, 24);
      await settle();
      expect(sessions, hasLength(2));
      await cubit.close();
    });

    test('closing hangs up the shell', () async {
      final cubit = await running();
      await cubit.close();
      expect(sessions.single.closed, isTrue);
    });
  });
}
