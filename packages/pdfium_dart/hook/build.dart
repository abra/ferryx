import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

import 'src/download.dart';

const _assetName = 'libpdfium';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    if (input.config.code.targetOS == OS.iOS) return;

    final target = _PdfiumTarget.fromCodeConfig(input.config.code);
    final manifestUri = input.packageRoot.resolve('hook/pdfium_binaries.json');
    output.dependencies.add(manifestUri);
    final manifest =
        jsonDecode(await File.fromUri(manifestUri).readAsString())
            as Map<String, dynamic>;
    final archiveName =
        'pdfium-${target.archivePlatform}-${target.archiveArch}.tgz';
    final assets = manifest['assets'] as Map<String, dynamic>;
    final artifact = assets[archiveName] as Map<String, dynamic>?;
    if (artifact == null) {
      throw UnsupportedError('No pinned PDFium binary for $archiveName');
    }
    final outputSubdir = (manifest['release'] as String).replaceAll('/', '_');
    final outputFile = input.outputDirectoryShared.resolve(
      '$outputSubdir/${target.archivePlatform}-${target.archiveArch}/${target.libraryFileName}',
    );

    await PdfiumDownloader(cacheDirectory: pdfiumCacheDirectory()).install(
      archive: PdfiumArchive.fromJson(artifact),
      libraryPath: target.archiveLibraryPath,
      output: File.fromUri(outputFile),
    );

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: _assetName,
        linkMode: DynamicLoadingBundled(),
        file: outputFile,
      ),
    );
  });
}

final class _PdfiumTarget {
  const _PdfiumTarget({
    required this.archivePlatform,
    required this.archiveArch,
    required this.archiveLibraryPath,
    required this.libraryFileName,
  });

  final String archivePlatform;
  final String archiveArch;
  final String archiveLibraryPath;
  final String libraryFileName;

  static _PdfiumTarget fromCodeConfig(CodeConfig config) {
    final arch = switch (config.targetArchitecture) {
      Architecture.ia32 => 'x86',
      Architecture.x64 => 'x64',
      Architecture.arm => 'arm',
      Architecture.arm64 => 'arm64',
      _ => throw UnsupportedError(
        'Unsupported PDFium architecture: ${config.targetArchitecture}',
      ),
    };

    return switch (config.targetOS) {
      OS.android => _PdfiumTarget(
        archivePlatform: 'android',
        archiveArch: arch,
        archiveLibraryPath: 'lib/libpdfium.so',
        libraryFileName: 'libpdfium.so',
      ),
      OS.windows => _PdfiumTarget(
        archivePlatform: 'win',
        archiveArch: arch,
        archiveLibraryPath: 'bin/pdfium.dll',
        libraryFileName: 'pdfium.dll',
      ),
      OS.linux => _PdfiumTarget(
        archivePlatform: 'linux',
        archiveArch: arch,
        archiveLibraryPath: 'lib/libpdfium.so',
        libraryFileName: 'libpdfium.so',
      ),
      OS.macOS => _PdfiumTarget(
        archivePlatform: 'mac',
        archiveArch: arch,
        archiveLibraryPath: 'lib/libpdfium.dylib',
        libraryFileName: 'libpdfium.dylib',
      ),
      _ => throw UnsupportedError(
        'Unsupported PDFium platform: ${config.targetOS}',
      ),
    };
  }
}
