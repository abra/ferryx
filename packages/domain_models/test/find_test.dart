import 'dart:convert';

import 'package:domain_models/domain_models.dart';
import 'package:test/test.dart';

void main() {
  test('saved queries preserve all conditions and relative date ranges', () {
    const query = FindRequest(
      root: '/documents',
      name: '*.pdf;*.docx',
      nameIsRegex: true,
      content: ContentQuery(
        text: 'слово',
        caseSensitive: true,
        wholePhrase: false,
        notContaining: true,
      ),
      size: SizeCondition(op: SizeOp.greater, bytes: 500000),
      includeFolders: false,
      includeHidden: true,
      useSpotlight: true,
      modifiedWithinDays: 7,
    );
    final json = jsonDecode(jsonEncode(query.toJson())) as Map<String, Object?>;
    expect(FindRequest.fromJson(json), query);
    expect(json['modifiedWithinDays'], 7);
    expect(json.containsKey('modifiedAfterMs'), isFalse);
  });
  test('malformed roots, size conditions and date ranges are rejected', () {
    for (final json in <Map<String, Object?>>[
      {},
      {'root': ''},
      {'root': '/a\u0000b'},
      {
        'root': '/',
        'size': {'op': 'unknown', 'bytes': 1},
      },
      {'root': '/', 'modifiedWithinDays': -1},
      {'root': '/', 'modifiedWithinDays': '7'},
    ]) {
      expect(FindRequest.fromJson(json), isNull);
    }
  });
}
