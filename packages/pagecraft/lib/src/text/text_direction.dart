final _letterOrNumber = RegExp(r'[\p{L}\p{N}]', unicode: true);
final _number = RegExp(r'\p{N}', unicode: true);

/// Direction of a text cell's first directional character. Numbers run LTR;
/// null leaves punctuation and spacing to the surrounding source geometry.
bool? textCellIsRtl(String text) {
  for (final rune in text.runes) {
    final character = String.fromCharCode(rune);
    if (_number.hasMatch(character)) return false;
    if (!_letterOrNumber.hasMatch(character)) continue;
    return (rune >= 0x0590 && rune <= 0x08FF) ||
        (rune >= 0xFB1D && rune <= 0xFDFF) ||
        (rune >= 0xFE70 && rune <= 0xFEFF) ||
        (rune >= 0x10840 && rune <= 0x10FFF) ||
        (rune >= 0x1E800 && rune <= 0x1EEFF);
  }
  return null;
}
