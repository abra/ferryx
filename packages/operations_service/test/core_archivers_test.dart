import 'dart:io';

import 'package:domain_models/domain_models.dart';
import 'package:ferryx_backend/ferryx_backend.dart' show FerryxBackend;
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';
import 'package:monitoring/monitoring.dart';
import 'package:operations_service/operations_service.dart';

final _library = File(
  '../../rust/target/debug/${Platform.isMacOS
      ? 'libferryx_api.dylib'
      : Platform.isWindows
      ? 'ferryx_api.dll'
      : 'libferryx_api.so'}',
);

void main() {
  late FerryxBackend backend;
  late OperationsService operations;
  late List<ArchiveTool> tools;
  final skip = _library.existsSync() ? null : 'run make core first';
  setUpAll(() async {
    if (skip != null) return;
    backend = await FerryxBackend.initialize(
      externalLibrary: ExternalLibrary.open(_library.path),
    );
    operations = OperationsService(backend: backend, logger: Logger());
    tools = await operations.discoverArchivers(const []);
  });
  tearDownAll(() async {
    if (skip != null) return;
    await operations.dispose();
  });

  test('discovery uses actual executable paths, shares scans and honors manual names', () async {
    expect(
      operations.discoverArchivers(const []),
      same(operations.discoverArchivers(const [])),
    );
    for (final tool in tools) {
      expect(File(tool.path).existsSync(), isTrue);
    }
    if (tools.isEmpty) return;
    final first = tools.first;
    final manual = ArchiveTool(
      name: 'My archive program',
      path: first.path,
      engine: first.engine,
    );
    final discovered = await operations.discoverArchivers([
      manual,
    ], refresh: true);
    expect(discovered.firstWhere((t) => t.id == manual.id).name, manual.name);
  }, skip: skip);

  test(
    'external archive operations flow through the bridge with progress and Undo',
    () async {
      final writers = tools
          .where((t) => t.engine.creates.isNotEmpty && t.engine.extracts)
          .toList();
      if (writers.isEmpty) return;
      final tool = writers.first;
      final format = tool.engine.creates.first;
      final directory = await Directory.systemTemp.createTemp(
        'ferryx-archiver-bridge-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final input = File('${directory.path}/literal spaces.txt');
      await input.writeAsString('bridge archive data');
      final compressed = await operations.run(
        OperationRequest(
          kind: OpKind.compress,
          sources: [input.path],
          destination: directory.path,
          newName: 'result.${format.extension}',
          archiver: tool,
          archiveType: format,
        ),
        answer: (_) => Answer.abort,
      );
      expect(
        compressed.state,
        OpState.done,
        reason: compressed.errors.toString(),
      );
      final archive = File('${directory.path}/result.${format.extension}');
      expect(archive.existsSync(), isTrue);
      final output = '${directory.path}/output';
      final extracted = await operations.run(
        OperationRequest(
          kind: OpKind.extract,
          sources: [archive.path],
          destination: output,
          archiver: tool,
        ),
        answer: (_) => Answer.abort,
      );
      expect(
        extracted.state,
        OpState.done,
        reason: extracted.errors.toString(),
      );
      expect(
        await File('$output/literal spaces.txt').readAsString(),
        'bridge archive data',
      );
      expect(operations.current[extracted.id]?.state, OpState.done);
      expect(operations.currentJournal.undo, isNotNull);
    },
    skip: skip,
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'configured ZIP and compressor defaults survive the native bridge',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ferryx-compressor-options-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final input = File('${directory.path}/source.txt');
      final content = List.filled(10000, 'test data').join();
      await input.writeAsString(content);
      final stored = await operations.run(
        OperationRequest(
          kind: OpKind.compress,
          sources: [input.path],
          destination: directory.path,
          newName: 'stored.zip',
          archiveOptions: const ArchiverOptions(level: 0),
        ),
        answer: (_) => Answer.abort,
      );
      expect(stored.state, OpState.done, reason: stored.errors.toString());
      expect(
        await File('${directory.path}/stored.zip').length(),
        greaterThan(content.length),
      );
      for (final (index, tool)
          in tools.where((tool) => tool.engine.isStream).indexed) {
        await operations.validateArchiverOptions(
          tool.engine,
          const ArchiverOptions(level: 1),
        );
        final stem = '${tool.engine.name}-$index';
        final archive = '$stem.${tool.engine.creates.last.extension}';
        final compressed = await operations.run(
          OperationRequest(
            kind: OpKind.compress,
            sources: [input.path],
            destination: directory.path,
            newName: archive,
            archiver: tool,
            archiveType: tool.engine.creates.last,
            archiveOptions: const ArchiverOptions(level: 1),
          ),
          answer: (_) => Answer.abort,
        );
        expect(
          compressed.state,
          OpState.done,
          reason: compressed.errors.toString(),
        );
        final extracted = await operations.run(
          OperationRequest(
            kind: OpKind.extract,
            sources: ['${directory.path}/$archive'],
            destination: '${directory.path}/$stem-out',
            archiver: tool,
          ),
          answer: (_) => Answer.abort,
        );
        expect(
          extracted.state,
          OpState.done,
          reason: '${tool.path}: ${extracted.errors}',
        );
        expect(
          await File(
            '${directory.path}/$stem-out/$stem',
          ).readAsString(),
          content,
        );
        await expectLater(
          operations.validateArchiverOptions(
            tool.engine,
            const ArchiverOptions(arguments: ['--rm']),
          ),
          throwsA(isA<FerryxException>()),
        );
      }
      expect(await input.readAsString(), content);
    },
    skip: skip,
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
