import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

Future<void> main(List<String> args) async {
  await build(args, (input, output) async {
    final crate = Directory.fromUri(input.packageRoot.resolve('rust/'));
    final compiler = await Process.run('rustup', [
      'which',
      'rustc',
    ], workingDirectory: crate.path);
    if (compiler.exitCode != 0) {
      throw StateError(
        'Cannot resolve the pinned Rust compiler: ${compiler.stderr}',
      );
    }
    await FlutterRustBridgeNativeAssetsBuilder(
      cratePath: 'rust',
      assetName: 'src/formats/mobi/native/rust/frb_generated.io.dart',
      extraCargoBuildArgs: ['--locked'],
      // Homebrew rustc can precede rustup proxies in PATH on macOS.
      extraCargoEnvironmentVariables: {
        'RUSTC': (compiler.stdout as String).trim(),
      },
    ).run(input: input, output: output);

    if (!input.config.buildCodeAssets) return;

    final nativeDirectory = input.packageRoot.resolve('native/djvu/');
    final upstreamDirectory = Directory.fromUri(
      nativeDirectory.resolve('upstream/libdjvu/'),
    );
    final upstreamSources = await upstreamDirectory
        .list()
        .where((entry) => entry is File && entry.path.endsWith('.cpp'))
        .map(
          (entry) =>
              'native/djvu/upstream/libdjvu/${entry.uri.pathSegments.last}',
        )
        .toList();
    upstreamSources.sort();
    final targetOS = input.config.code.targetOS;
    await CBuilder.library(
      name: 'pagecraft_djvu',
      assetName: 'src/formats/djvu/native/djvu_native.dart',
      sources: ['native/djvu/pagecraft_djvu.cpp', ...upstreamSources],
      includes: ['native/djvu', 'native/djvu/upstream/libdjvu'],
      frameworks: const [],
      libraries: [
        if (targetOS == OS.android || targetOS == OS.linux) ...['m', 'dl'],
      ],
      language: Language.cpp,
      std: 'c++17',
      defines: {'HAVE_CONFIG_H': '1'},
      flags: [
        if (targetOS == OS.android || targetOS == OS.linux)
          '-Wl,--no-undefined',
        // CBuilder 0.19 forwards `frameworks` only for Objective-C sources.
        if (targetOS == OS.iOS || targetOS == OS.macOS) ...[
          '-framework',
          'CoreFoundation',
        ],
        if (targetOS != OS.windows) ...[
          '-fvisibility=hidden',
          '-fvisibility-inlines-hidden',
          '-pthread',
        ],
      ],
      // Android otherwise requires a separately bundled libc++_shared.so.
      cppLinkStdLib: targetOS == OS.android ? 'c++_static' : null,
    ).run(input: input, output: output);
  });
}
