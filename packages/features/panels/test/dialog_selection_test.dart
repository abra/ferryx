import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panels_feature/src/dialogs/simple_dialogs.dart';

/// A dialog's field starts with the selection the dialog chose, not the
/// desktop's select-all on focus: the mask's caret waits after `*.`.
void main() {
  testWidgets(
    'Select by Mask opens with the caret after `*.`, so an '
    'extension typed completes the mask',
    variant: TargetPlatformVariant.only(
      TargetPlatform.macOS,
    ),
    (tester) async {
      late Future<MaskChoice?> result;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppPlatformStyle.macos),
          localizationsDelegates: FerryxSupportedLocales.delegates,
          supportedLocales: FerryxSupportedLocales.locales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    result = showSelectMaskDialog(context, select: true),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final field = tester.state<EditableTextState>(find.byType(EditableText));
      expect(field.widget.focusNode.hasPrimaryFocus, isTrue);
      expect(
        field.textEditingValue.selection,
        const TextSelection.collapsed(offset: 2),
      );
      // What the desktop sends for `txt` typed at the caret.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '*.txt',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect((await result)?.mask, '*.txt');
    },
  );
}
