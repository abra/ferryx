import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terminal_feature/terminal_feature.dart';

void main() {
  late DateTime now;
  late FolderSync sync;

  TerminalShellState prompt(String folder) =>
      TerminalShellState(idle: true, folder: folder);
  TerminalShellState busy(String folder) =>
      TerminalShellState(idle: false, folder: folder);

  setUp(() {
    now = DateTime(2026);
    sync = FolderSync(clock: () => now);
  });

  group('panel to shell', () {
    test('nothing before the shell has been seen at its prompt', () {
      sync.panel = '/a';
      expect(sync.toShell(), isNull);
    });

    test('a shell at its prompt elsewhere is sent the panel\'s folder', () {
      sync.panel = '/a';
      sync.onShellState(prompt('/home'));
      expect(sync.toShell(), '/a');
    });

    test('a shell already there, busy, or with a typed line is left '
        'alone', () {
      sync.onShellState(prompt('/a'));
      sync.panel = '/a';
      expect(sync.toShell(), isNull, reason: 'already there');
      sync.panel = '/b';
      sync.typed('ls -l');
      expect(sync.toShell(), isNull, reason: 'a half-typed line');
      sync.typed('\r');
      expect(sync.toShell(), '/b');
      sync.onShellState(busy('/a'));
      expect(sync.toShell(), isNull, reason: 'a program runs');
    });

    test('a folder inside an archive is never sent', () {
      sync.onShellState(prompt('/a'));
      sync.panel = null;
      expect(sync.toShell(), isNull);
    });

    test('a cd under way is not typed twice', () {
      sync.onShellState(prompt('/a'));
      sync.panel = '/b';
      sync.cdTyped('/b');
      expect(sync.toShell(), isNull);
      // Dropped by the core: free to try again.
      sync.cdDropped('/b');
      expect(sync.toShell(), '/b');
    });

    test('a program ending leaves a clean line', () {
      sync.onShellState(prompt('/a'));
      sync.typed('vim notes');
      sync.typed('\r');
      sync.onShellState(busy('/a'));
      sync.typed('ihello'); // typed into vim, not the shell
      sync.onShellState(prompt('/a'));
      expect(sync.lineDirty, isFalse);
      sync.panel = '/b';
      expect(sync.toShell(), '/b');
    });

    test('Ctrl+C and Ctrl+U clear the line; focus reports do not dirty it', () {
      sync.typed('abc');
      expect(sync.lineDirty, isTrue);
      sync.typed('\x03');
      expect(sync.lineDirty, isFalse);
      sync.typed('x');
      sync.typed('\x15');
      expect(sync.lineDirty, isFalse);
      sync.typed('\x1b[I');
      sync.typed('\x1b[O');
      expect(sync.lineDirty, isFalse);
      sync.typed('\x1b[A'); // history: the line now holds a command
      expect(sync.lineDirty, isTrue);
    });
  });

  group('shell to panel', () {
    test('the first prompt is where the shell started: no report', () {
      sync.panel = null; // the panel is in an archive
      expect(sync.onShellState(prompt('/home')), isNull);
    });

    test('a cd typed in the shell is reported once it is at its prompt', () {
      sync.panel = '/a';
      sync.onShellState(prompt('/a'));
      expect(sync.onShellState(busy('/a')), isNull);
      expect(sync.onShellState(prompt('/tmp')), '/tmp');
      // Reported once: the same folder again is no news.
      expect(sync.onShellState(prompt('/tmp')), isNull);
    });

    test('a folder changed while a program ran is reported when it ends', () {
      sync.panel = '/a';
      sync.onShellState(prompt('/a'));
      // `cd /tmp && sleep 5`
      expect(sync.onShellState(busy('/tmp')), isNull);
      expect(sync.onShellState(prompt('/tmp')), '/tmp');
    });

    test('the panel moving while a program runs is not undone when it '
        'ends', () {
      sync.panel = '/a';
      sync.onShellState(prompt('/a'));
      sync.onShellState(busy('/a'));
      sync.panel = '/elsewhere';
      expect(sync.onShellState(prompt('/a')), isNull);
    });

    test('a folder the panel is in already is not reported', () {
      sync.panel = '/a';
      sync.onShellState(prompt('/home'));
      sync.panel = '/b';
      expect(sync.onShellState(prompt('/b')), isNull);
    });

    test('the folders of a cd under way are not sent back: no ping-pong', () {
      sync.panel = '/a';
      sync.onShellState(prompt('/a'));
      // The panel goes to /b, then quickly to /c.
      sync.panel = '/b';
      sync.cdTyped('/b');
      sync.panel = '/c';
      // The shell reports /b on its way: the panel is not pulled back.
      expect(sync.onShellState(prompt('/b')), isNull);
      sync.cdTyped('/c');
      expect(sync.onShellState(prompt('/c')), isNull);
      // Settled: a cd typed by the user is reported again.
      expect(sync.onShellState(prompt('/d')), '/d');
    });

    test('a cd that never arrives stops holding reports back', () {
      sync.panel = '/a';
      sync.onShellState(prompt('/a'));
      sync.panel = '/locked';
      sync.cdTyped('/locked');
      // cd: permission denied; the shell stays.
      expect(sync.onShellState(prompt('/a')), isNull);
      now = now.add(FolderSync.settle);
      sync.panel = '/a';
      expect(sync.onShellState(prompt('/tmp')), '/tmp');
    });

    test('unknown states (Windows) never report', () {
      sync.panel = '/a';
      expect(
        sync.onShellState(const TerminalShellState(folder: '/x')),
        isNull,
      );
      expect(sync.onShellState(const TerminalShellState(idle: true)), isNull);
      expect(sync.toShell(), isNull);
    });

    test('reset forgets the shell', () {
      sync.onShellState(prompt('/a'));
      sync.typed('x');
      sync.reset();
      expect(sync.lineDirty, isFalse);
      expect(sync.shellFolder, isNull);
      expect(sync.onShellState(prompt('/b')), isNull);
    });
  });
}
