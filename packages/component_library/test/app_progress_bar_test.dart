import 'package:component_library/component_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('unknown progress never announces a placeholder percentage', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      for (final reducedMotion in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(AppPlatformStyle.macos),
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reducedMotion),
              child: Scaffold(
                body: AppProgressBar(value: null, animate: reducedMotion),
              ),
            ),
          ),
        );
        expect(
          tester
              .getSemantics(find.byType(AppProgressBar))
              .getSemanticsData()
              .value,
          isEmpty,
        );
      }
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(AppPlatformStyle.macos),
          home: const Scaffold(body: AppProgressBar(value: 0.65)),
        ),
      );
      expect(
        tester
            .getSemantics(find.byType(AppProgressBar))
            .getSemanticsData()
            .value,
        '65%',
      );
    } finally {
      semantics.dispose();
    }
  });
}
