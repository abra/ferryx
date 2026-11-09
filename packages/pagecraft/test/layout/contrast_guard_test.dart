import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/src/layout/contrast_guard.dart';

/// The cases of the WebView's `readflex_contrast_guard.test.mjs`.
void main() {
  const darkBackground = 0xFF0F1115;
  const darkText = 0xFFBCC1CA;

  test('dark blue on the dark reader background is low contrast', () {
    expect(contrastRatio(0xFF000050, darkBackground), lessThan(4.5));
    expect(contrastRatio(0xFFFFFFFF, 0xFF000000), closeTo(21, 1e-9));
    expect(contrastRatio(0xFF777777, 0xFF777777), 1);
  });

  test('only unreadable text takes the reader\'s colour', () {
    expect(
      readableTextColor(
        0xFF000050,
        background: darkBackground,
        textColor: darkText,
      ),
      darkText,
    );
    const readable = 0xFFDCE1EB;
    expect(
      readableTextColor(
        readable,
        background: darkBackground,
        textColor: darkText,
      ),
      readable,
    );
  });

  test('on a dark panel in a light theme the text turns white', () {
    // The reader's dark text does not read on it either.
    expect(
      readableTextColor(
        0xFF222222,
        background: 0xFF000055,
        textColor: 0xFF292521,
      ),
      0xFFFFFFFF,
    );
  });

  test('translucent colours are judged as they show', () {
    // A white panel at 10% over black.
    final panel = composite(0x1AFFFFFF, 0xFF000000);
    expect(panel >>> 24, 0xFF);
    expect(panel & 0xFF, closeTo(26, 1));
    expect(
      readableTextColor(0xFF222222, background: panel, textColor: 0xFF292521),
      0xFFFFFFFF,
    );
    // Almost transparent text over white does not read.
    expect(
      readableTextColor(
        0x10000000,
        background: 0xFFFFFFFF,
        textColor: 0xFF292521,
      ),
      0xFF292521,
    );
  });
}
