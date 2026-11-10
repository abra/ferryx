import 'package:domain_models/domain_models.dart';
import 'package:file_repository/file_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:viewer_feature/src/markdown_format.dart';
import 'package:viewer_feature/viewer_feature.dart';

class _Files extends Mock implements FileRepository {}

void main() {
  test('Markdown names are case-insensitive and exclude HTML/MDX', () {
    for (final name in [
      'README.md',
      'readme.MARKDOWN',
      'a.mdown',
      'a.mkd',
      'a.mkdn',
    ]) {
      expect(isMarkdownName(name), isTrue);
    }
    for (final name in [
      'md',
      'book.mdx',
      'page.html',
      'foo.md.zip',
      'image.png',
    ]) {
      expect(isMarkdownName(name), isFalse, reason: name);
    }
  });

  final files = _Files();
  for (final location in [
    const Location.native('/docs/guide/README.md'),
    const Location.inArchive(archive: '/docs.zip', path: 'guide/README.md'),
    const Location.remote(
      server: 'sftp://user@example.com:22',
      path: '/docs/guide/README.md',
    ),
  ]) {
    test(
      'relative images preserve ${location.kind.name} identity and decode paths',
      () {
        final source = FileRepositorySource(files, location);
        final resolved =
            source.resolveRelative(Uri.parse('../images/a%20b.png'))!
                as FileRepositorySource;
        expect(resolved.location.kind, location.kind);
        expect(resolved.location.archive, location.archive);
        expect(resolved.location.server, location.server);
        expect(
          resolved.location.path,
          location.kind == LocationKind.archive
              ? 'images/a b.png'
              : '/docs/images/a b.png',
        );
        for (final reference in [
          'https://example.com/a.png',
          '//example.com/a.png',
          'file:///etc/a.png',
          '/absolute.png',
          '%2Fabsolute.png',
          '#heading',
          'data:image/png;base64,xxx',
        ]) {
          expect(
            source.resolveRelative(Uri.parse(reference)),
            isNull,
            reason: reference,
          );
        }
      },
    );
  }

  test('archive images cannot traverse above the archive root', () {
    final source = FileRepositorySource(
      files,
      const Location.inArchive(archive: '/docs.zip', path: 'README.md'),
    );
    expect(source.resolveRelative(Uri.parse('../outside.png')), isNull);
    expect(source.resolveRelative(Uri.parse('%2e%2e/outside.png')), isNull);
  });
}
