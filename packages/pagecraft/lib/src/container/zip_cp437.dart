import 'dart:typed_data';

/// Decodes a ZIP entry name written in the specification's default code
/// page, used when the UTF-8 flag is clear and the bytes are not UTF-8.
String decodeCp437(Uint8List bytes) {
  final units = Uint16List(bytes.length);
  for (var i = 0; i < bytes.length; i++) {
    final byte = bytes[i];
    units[i] = byte < 0x80 ? byte : _highHalf.codeUnitAt(byte - 0x80);
  }
  return String.fromCharCodes(units);
}

/// Code points 0x80–0xFF of code page 437, in order.
const _highHalf =
    'ÇüéâäàåçêëèïîìÄÅÉæÆôöòûùÿÖÜ¢£¥₧ƒáíóúñÑªº¿⌐¬½¼¡«»░▒▓│┤╡╢╖╕╣║╗╝╜╛┐└┴┬├─┼╞╟╚╔╩╦╠═╬╧╨╤╥╙╘╒╓╫╪┘┌█▄▌▐▀αßΓπΣσµτΦΘΩδ∞φε∩≡±≥≤⌠⌡÷≈°∙·√ⁿ²■ ';
