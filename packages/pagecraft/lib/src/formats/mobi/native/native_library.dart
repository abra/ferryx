import 'dart:convert';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;

import 'rust/frb_generated.dart';

const _assetId =
    'package:pagecraft/src/formats/mobi/native/rust/frb_generated.io.dart';
const _isFlutter = bool.fromEnvironment('dart.library.ui');
const _isProduct = bool.fromEnvironment('dart.vm.product');
Future<void>? _initialization;

Future<void> initializeMobiNative() => _initialization ??= _initialize();

Future<void> _initialize() async {
  try {
    final hostPath = _hostLibraryPath();
    await PagecraftMobiRustLib.init(
      externalLibrary: hostPath == null ? null : ExternalLibrary.open(hostPath),
    );
  } catch (_) {
    _initialization = null;
    rethrow;
  }
}

/// Packaged Flutter apps use FRB's platform loader. Host tests and Dart CLI
/// builds use the same native asset registered by the build hook.
String? _hostLibraryPath() {
  if (Platform.isIOS || Platform.isAndroid) return null;
  final name = Platform.isWindows
      ? 'pagecraft_mobi_native.dll'
      : Platform.isMacOS
      ? 'libpagecraft_mobi_native.dylib'
      : 'libpagecraft_mobi_native.so';
  final executableDirectory = File(Platform.resolvedExecutable).parent;
  for (final directory in [
    executableDirectory,
    Directory.fromUri(executableDirectory.uri.resolve('lib/')),
    Directory.fromUri(executableDirectory.uri.resolve('../lib/')),
  ]) {
    final library = File.fromUri(directory.uri.resolve(name));
    if (library.existsSync()) return library.path;
  }
  if (_isFlutter &&
      _isProduct &&
      !Platform.environment.containsKey('FLUTTER_TEST')) {
    return null;
  }
  final target = RegExp(r'"([^"_]+)_([^"_]+)"').firstMatch(Platform.version);
  if (target == null) throw StateError('Cannot determine native host target');
  final key = '${target[1]}_${target[2]}';
  var directory = Directory.current;
  while (true) {
    for (final relative in [
      'build/native_assets/${target[1]}/native_assets.json',
      '.dart_tool/native_assets.yaml',
    ]) {
      final manifest = File.fromUri(directory.uri.resolve(relative));
      if (!manifest.existsSync()) continue;
      final content = manifest
          .readAsLinesSync()
          .where((line) => !line.trimLeft().startsWith('#'))
          .join('\n');
      final data = jsonDecode(content) as Map;
      final asset = ((data['native-assets'] as Map?)?[key] as Map?)?[_assetId];
      if (asset is List && asset.length == 2 && asset[0] == 'absolute') {
        final library = File(asset[1] as String);
        if (library.existsSync()) return library.path;
      }
    }
    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
  return null;
}
