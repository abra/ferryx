import 'dart:convert';

import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:panels_feature/panels_feature.dart';
import 'package:viewer_feature/viewer_feature.dart';

import '../../packages/features/panels/test/support/workspace_harness.dart';

void main() {
  setUpAll(WorkspaceHarness.registerFallbacks);
  for (final vim in [false, true]) {
    testWidgets(
      'Vim=$vim: preview, search, Escape and Tab preserve file state and focus',
      (tester) async {
        final h = WorkspaceHarness();
        await h.setUp(vim: vim);
        addTearDown(h.tearDown);
        final bytes = Uint8List.fromList(
          utf8.encode('needle one\nneedle two\n'),
        );
        when(() => h.files.fileSize(any()))
            .thenAnswer((_) async => bytes.length);
        when(() => h.files.readRange(any(), any(), any()))
            .thenAnswer((_) async => bytes);
        await h.pump(
          tester,
          preview: WorkspacePreview(
            builder: (context, view) {
              final location = view.location;
              if (location == null) return const SizedBox.shrink();
              return ViewerScreen(
                files: h.files,
                preferences: h.preferences,
                shortcutMap: h.shortcutMap,
                windowDecor: view.decor,
                location: location,
                focusScope: view.focusScope,
                autofocus: false,
                startInPreview: view.startInPreview,
                fullWindow: view.fullWindow,
                onToggleFullWindow: view.onToggleFullWindow,
                onFocusFiles: view.onFocusFiles,
                onClose: view.onClose,
              );
            },
          ),
        );
        final panelWidget = tester.widget<PanelView>(
          find.byType(PanelView).first,
        );
        final panel = tester
            .element(find.byType(PanelView).first)
            .read<PanelCubit>();
        panel.moveCursorTo(
          panel.state.active!.rows.indexWhere((row) => row.name == 'a.txt'),
        );
        await tester.pump();
        final before = panel.state.active!;
        await h.press(
          tester,
          vim ? LogicalKeyboardKey.keyI : LogicalKeyboardKey.space,
          character: vim ? 'i' : ' ',
        );
        expect(find.byType(ViewerScreen), findsOneWidget);
        expect(panelWidget.focusNode.hasFocus, isTrue);
        await h.press(tester, LogicalKeyboardKey.tab);
        expect(panelWidget.focusNode.hasFocus, isFalse);
        await h.press(
          tester,
          LogicalKeyboardKey.keyF,
          meta: true,
          character: 'f',
        );
        await tester.enterText(find.byType(AppSearchField), 'needle');
        await tester.pumpAndSettle();
        expect(
          find.text(
            lookupFerryxLocalizations(const Locale('en')).viewerMatches(1, 2),
          ),
          findsOneWidget,
        );
        await h.press(tester, LogicalKeyboardKey.escape);
        await h.press(tester, LogicalKeyboardKey.escape);
        expect(find.byType(AppSearchField), findsNothing);
        expect(find.byType(ViewerScreen), findsOneWidget);
        await h.press(tester, LogicalKeyboardKey.keyJ, character: 'j');
        expect(panel.state.active!.cursor, before.cursor);
        expect(panel.state.active!.selected, before.selected);
        final viewerState = tester.state(find.byType(ViewerScreen));
        for (var i = 0; i < 4; i++) {
          tester
              .widget<ViewerScreen>(find.byType(ViewerScreen))
              .onToggleFullWindow!();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 20));
          expect(tester.state(find.byType(ViewerScreen)), same(viewerState));
          expect(tester.takeException(), isNull);
        }
        await tester.pumpAndSettle();
        await h.press(tester, LogicalKeyboardKey.tab);
        expect(panelWidget.focusNode.hasFocus, isTrue);
        await h.press(tester, LogicalKeyboardKey.escape);
        expect(find.byType(ViewerScreen), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
