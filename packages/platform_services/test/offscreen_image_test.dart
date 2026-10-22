import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_services/src/offscreen_image.dart';

void main() {
  testWidgets('paints a widget off screen at the pixel ratio, with the '
      "context's theme and strings", (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: const ColorScheme.light(primary: Colors.red),
        ),
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    Color? primary;
    String? ok;
    final image = await tester.runAsync(
      () => paintOffscreen(
        context,
        Builder(
          builder: (inner) {
            primary = Theme.of(inner).colorScheme.primary;
            ok = MaterialLocalizations.of(inner).okButtonLabel;
            return ColoredBox(color: primary!);
          },
        ),
        size: const Size(20, 10),
        pixelRatio: 2,
      ),
    );
    expect(image!.width, 40);
    expect(image.height, 20);
    expect(primary, Colors.red);
    expect(ok, 'OK');
    final bytes = await tester.runAsync(image.toByteData);
    // The top-left pixel is the box's red, opaque (RGBA).
    expect(bytes!.getUint8(0), (Colors.red.r * 255).round());
    expect(bytes.getUint8(3), 0xFF);
    image.dispose();
    // Nothing of the off-screen tree is in the window's.
    expect(
      find.byWidgetPredicate((w) => w is ColoredBox && w.color == primary),
      findsNothing,
    );
  });

  testWidgets('works without strings above the context', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (c) {
              context = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    final image = await tester.runAsync(
      () => paintOffscreen(
        context,
        const ColoredBox(color: Color(0xFF00FF00)),
        size: const Size(4, 4),
        pixelRatio: 1,
      ),
    );
    expect(image!.width, 4);
    image.dispose();
  });
}
