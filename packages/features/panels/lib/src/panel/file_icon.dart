import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter/widgets.dart';

/// The icon of a row, by what the item is: folders in the accent, kinds of
/// files tinted from the tag palette, the rest quiet.
class FileIcon extends StatelessWidget {
  const FileIcon(this.entry, {this.size = AppIconSize.md, super.key});

  final FileEntry entry;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final (icon, color) = describe(entry, colors);
    return Icon(icon, size: size, color: color);
  }

  /// The glyph and colour for [entry].
  static (IconData, Color) describe(FileEntry entry, AppColorsExt colors) {
    if (entry.isParent) return (AppIcons.folderUp, colors.textMuted);
    if (entry.isDir) {
      if (entry.isSymlink) return (AppIcons.folderSymlink, colors.accent);
      if (entry.name.endsWith('.app')) {
        return (AppIcons.application, colors.ink(4));
      }
      return (AppIcons.folder, colors.accent);
    }
    if (entry.isSymlink) return (AppIcons.fileSymlink, colors.textMuted);
    final kind = kindOf(entry.extension.toLowerCase());
    return switch (kind) {
      FileKind.image => (AppIcons.fileImage, colors.ink(3)),
      FileKind.audio => (AppIcons.fileAudio, colors.ink(5)),
      FileKind.video => (AppIcons.fileVideo, colors.ink(0)),
      FileKind.archive => (AppIcons.fileArchive, colors.ink(1)),
      FileKind.code => (AppIcons.fileCode, colors.ink(4)),
      FileKind.text => (AppIcons.fileText, colors.textMuted),
      FileKind.spreadsheet => (AppIcons.fileSpreadsheet, colors.ink(3)),
      FileKind.pdf => (AppIcons.filePdf, colors.ink(0)),
      FileKind.executable => (AppIcons.fileExecutable, colors.textMuted),
      FileKind.other =>
        entry.isExecutable
            ? (AppIcons.fileExecutable, colors.textMuted)
            : (AppIcons.file, colors.textMuted),
    };
  }

  static FileKind kindOf(String extension) {
    if (_images.contains(extension)) return FileKind.image;
    if (_audio.contains(extension)) return FileKind.audio;
    if (_video.contains(extension)) return FileKind.video;
    if (_archives.contains(extension)) return FileKind.archive;
    if (_code.contains(extension)) return FileKind.code;
    if (_text.contains(extension)) return FileKind.text;
    if (_sheets.contains(extension)) return FileKind.spreadsheet;
    if (extension == 'pdf') return FileKind.pdf;
    if (_executables.contains(extension)) return FileKind.executable;
    return FileKind.other;
  }

  static const _images = {
    'png',
    'jpg',
    'jpeg',
    'gif',
    'webp',
    'bmp',
    'heic',
    'heif',
    'tiff',
    'tif',
    'svg',
    'ico',
    'icns',
    'psd',
    'raw',
    'avif',
  };
  static const _audio = {
    'mp3',
    'aac',
    'm4a',
    'flac',
    'wav',
    'ogg',
    'oga',
    'opus',
    'aiff',
    'wma',
  };
  static const _video = {
    'mp4',
    'mkv',
    'mov',
    'avi',
    'webm',
    'm4v',
    'wmv',
    'flv',
  };
  static const _archives = {
    'zip',
    'tar',
    'gz',
    'tgz',
    'bz2',
    'xz',
    'zst',
    '7z',
    'rar',
    'jar',
    'dmg',
    'iso',
    'pkg',
    'xar',
    'cpio',
    'lz',
    'lz4',
    'lzma',
    'z',
    'cab',
    'deb',
    'rpm',
    'apk',
    'ipa',
    'whl',
  };
  static const _code = {
    'dart',
    'rs',
    'py',
    'js',
    'ts',
    'tsx',
    'jsx',
    'go',
    'java',
    'kt',
    'swift',
    'c',
    'h',
    'cpp',
    'hpp',
    'cc',
    'm',
    'mm',
    'cs',
    'rb',
    'php',
    'sh',
    'zsh',
    'bash',
    'fish',
    'lua',
    'pl',
    'scala',
    'hs',
    'ex',
    'exs',
    'erl',
    'clj',
    'html',
    'htm',
    'css',
    'scss',
    'less',
    'json',
    'yaml',
    'yml',
    'toml',
    'xml',
    'plist',
    'sql',
    'cmake',
    'make',
    'gradle',
    'zig',
    'nim',
    'vue',
    'svelte',
    'ini',
    'cfg',
    'conf',
    'lock',
  };
  static const _text = {
    'txt',
    'md',
    'markdown',
    'rst',
    'rtf',
    'log',
    'tex',
    'org',
    'adoc',
    'doc',
    'docx',
    'odt',
    'pages',
    'csv',
    'tsv',
  };
  static const _sheets = {'xls', 'xlsx', 'ods', 'numbers'};
  static const _executables = {'exe', 'bin', 'run', 'command', 'bat', 'cmd'};
}

enum FileKind {
  image,
  audio,
  video,
  archive,
  code,
  text,
  spreadsheet,
  pdf,
  executable,
  other,
}
