/// Base letters for U+00C0–U+024F (Latin-1 Supplement, Latin Extended-A
/// and B): the first character of the NFD decomposition, or the letter
/// itself when it has none. Generated with Python's `unicodedata`; the
/// letters without a decomposition that ICU still files under a base
/// letter are in [latinBaseOverrides].
const latinBaseTable =
    'AAAAAAÆCEEEEIIIIÐNOOOOO×ØUUUUYÞßaaaaaaæceeeeiiiiðnooooo÷øuuuuyþyAaAaAaCcCcCcCcDdĐđEeEeEeEeEeGgGgGgGgHhĦħIiIiIiIiIıĲĳJjKkĸLlLlLlĿŀŁłNnNnNnŉŊŋOoOoOoŒœRrRrRrSsSsSsSsTtTtŦŧUuUuUuUuUuUuWwYyYZzZzZzſƀƁƂƃƄƅƆƇƈƉƊƋƌƍƎƏƐƑƒƓƔƕƖƗƘƙƚƛƜƝƞƟOoƢƣƤƥƦƧƨƩƪƫƬƭƮUuƱƲƳƴƵƶƷƸƹƺƻƼƽƾƿǀǁǂǃǄǅǆǇǈǉǊǋǌAaIiOoUuUuUuUuUuǝAaAaǢǣǤǥGgKkOoOoǮǯjǱǲǳGgǶǷNnAaǼǽǾǿAaAaEeEeIiIiOoOoRrRrUuUuSsTtȜȝHhȠȡȢȣȤȥAaEeOoOoOoOoYyȴȵȶȷȸȹȺȻȼȽȾȿɀɁɂɃɄɅɆɇɈɉɊɋɌɍɎɏ';

/// Letters ICU orders as variants of a base letter although Unicode gives
/// them no decomposition (secondary difference, like an accent).
const latinBaseOverrides = <int, int>{
  0xF8: 0x6F, // ø → o
  0xD8: 0x4F, // Ø → O
  0x111: 0x64, // đ → d
  0x110: 0x44, // Đ → D
  0x142: 0x6C, // ł → l
  0x141: 0x4C, // Ł → L
  0x131: 0x69, // ı → i
  0x14B: 0x6E, // ŋ → n
  0x14A: 0x4E, // Ŋ → N
  0x127: 0x68, // ħ → h
  0x126: 0x48, // Ħ → H
  0x167: 0x74, // ŧ → t
  0x166: 0x54, // Ŧ → T
  0xF0: 0x64, // ð → d
  0xD0: 0x44, // Ð → D
  0x138: 0x6B, // ĸ → k
  0x17F: 0x73, // ſ → s
  0x451: 0x435, // ё → е
  0x401: 0x415, // Ё → Е
};

/// Letters that expand to two base letters at the primary level.
const latinExpansions = <int, String>{
  0xDF: 'ss', // ß
  0x1E9E: 'SS', // ẞ
  0xE6: 'ae', // æ
  0xC6: 'AE', // Æ
  0x153: 'oe', // œ
  0x152: 'OE', // Œ
  0x133: 'ij', // ĳ
  0x132: 'IJ', // Ĳ
};
