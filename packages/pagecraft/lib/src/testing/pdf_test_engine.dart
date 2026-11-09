import 'dart:convert';
import 'dart:io';

import 'package:pdfrx_engine/pdfrx_engine.dart';

bool _prepared = false;

/// Loads pdfium for `flutter test`, once per test process.
///
/// The build hook of `pdfium_dart` downloads the host library when the
/// package is built, and Flutter records it in
/// `build/native_assets/<os>/native_assets.json` of the package under
/// test, while the engine's loader still looks for the older
/// `.dart_tool/native_assets.yaml` and fails. This reads Flutter's manifest
/// (searching upwards from the current directory) and points the engine at
/// the library. Throws [StateError] with the path it looked for when the
/// manifest is missing, which means the package has not been built for
/// tests yet.
Future<void> preparePdfEngineForTests() async {
  if (_prepared) return;
  Pdfrx.pdfiumModulePath ??= _hostPdfiumPath();
  await pdfrxInitialize(
    tmpPath: '${Directory.systemTemp.path}/pagecraft_pdfrx',
  );
  _prepared = true;
}

String _hostPdfiumPath() {
  final target = _targetKey();
  final os = target.split('_').first;
  var directory = Directory.current;
  while (true) {
    final manifest = File(
      '${directory.path}/build/native_assets/$os/native_assets.json',
    );
    if (manifest.existsSync()) {
      final json = jsonDecode(manifest.readAsStringSync()) as Map;
      final assets = (json['native-assets'] as Map?)?[target] as Map?;
      final asset = assets?['package:pdfium_dart/libpdfium'];
      if (asset is List && asset.length == 2 && asset[0] == 'absolute') {
        return asset[1] as String;
      }
      throw StateError(
        'No pdfium entry for $target in ${manifest.path}; '
        'run `flutter test` once in a package that depends on pagecraft.',
      );
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError(
        'No build/native_assets/$os/native_assets.json above '
        '${Directory.current.path}; the pdfium build hook has not run.',
      );
    }
    directory = parent;
  }
}

/// `<os>_<arch>` as Flutter keys the manifest, e.g. `macos_arm64`.
String _targetKey() {
  final match = RegExp(r'"([^_"]+)_([^_"]+)"').firstMatch(Platform.version);
  if (match == null) {
    throw StateError('Cannot read the host target from ${Platform.version}');
  }
  return '${match[1]}_${match[2]}';
}
