/// Language and script signals shared by document and book direction fallback.
library;

bool isRtlLanguage(String? language) {
  final primary = language
      ?.trim()
      .toLowerCase()
      .replaceAll('_', '-')
      .split('-')
      .first;
  return _rtlLanguages.contains(primary);
}

({int rtl, int ltr}) directionCharacterCounts(String text) => (
  rtl: _rtlCharacters.allMatches(text).length,
  ltr: _ltrCharacters.allMatches(text).length,
);

// The script ranges and language list used by the former WebView reader.
final _rtlCharacters = RegExp('[\u0590-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]');
final _ltrCharacters = RegExp('[A-Za-z\u00C0-\u024F\u1E00-\u1EFF]');

const _rtlLanguages = {
  'ar',
  'arc',
  'ckb',
  'dv',
  'fa',
  'glk',
  'he',
  'iw',
  'ks',
  'lrc',
  'mzn',
  'nqo',
  'pnb',
  'ps',
  'sd',
  'syr',
  'ug',
  'ur',
  'yi',
};
