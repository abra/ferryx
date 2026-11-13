import 'dart:io';

import 'package:component_library/component_library.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:terminal_feature/src/terminal_look.dart';
import 'package:terminal_feature/terminal_feature.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final bytes = await File(
      '../../component_library/fonts/GeistMono-Variable.ttf',
    ).readAsBytes();
    await (FontLoader(
      'Terminal Test Mono',
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  });

  testWidgets('the chosen face changes glyph and cell metrics, while equal '
      'settings preserve the glyph cache', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.of(AppPlatformStyle.macos, Brightness.light),
        home: const SizedBox(),
      ),
    );
    final context = tester.element(find.byType(SizedBox).last);
    final type = context.metrics.typeScale;
    final look = TerminalLook();
    final defaultStyle = look.styleOf(context, 12);
    final defaultCell = look.cellOf(defaultStyle);
    expect(defaultStyle.fontFamily, type.monoFamily);
    expect(look.styleOf(context, 12), same(defaultStyle));

    final chosen = look.styleOf(context, 12, fontFamily: 'Terminal Test Mono');
    expect(chosen.fontFamily, 'Terminal Test Mono');
    expect(chosen.fontFamilyFallback, contains(type.monoFamily));
    expect(chosen.fontFamilyFallback, containsAll(type.monoFallback));
    expect(chosen.fontFamilyFallback, containsAll(TerminalLook.symbolFonts));
    final chosenCell = look.cellOf(chosen);
    expect(chosenCell.width, isNot(closeTo(defaultCell.width, 0.01)));
    expect(
      look.styleOf(context, 12, fontFamily: 'Terminal Test Mono'),
      same(chosen),
      reason: 'xterm invalidates its glyph cache when style identity changes',
    );
    expect(
      TerminalPane.lineHeightOf(context, 12, fontFamily: 'Terminal Test Mono'),
      chosenCell.height,
    );

    final larger = look.styleOf(context, 18, fontFamily: 'Terminal Test Mono');
    final largerCell = look.cellOf(larger);
    expect(largerCell.width, greaterThan(chosenCell.width));
    expect(largerCell.height, greaterThan(chosenCell.height));

    final restored = look.styleOf(context, 12);
    expect(restored.fontFamily, defaultStyle.fontFamily);
    expect(look.cellOf(restored), defaultCell);
  });
}
