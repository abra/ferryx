import 'dart:async';
import 'dart:convert';

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:file_repository/file_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:panels_feature/panels_feature.dart';
import 'package:panels_feature/src/panel/panel_footer.dart';
import 'package:shortcuts/shortcuts.dart';
import 'package:viewer_feature/viewer_feature.dart';

import '../../packages/features/panels/test/support/workspace_harness.dart';

class _PendingPreview implements PreviewFileLease {
  final prepared = Completer<String>();

  @override
  Future<String> get path => prepared.future;

  @override
  Future<void> close() async {
    if (!prepared.isCompleted) {
      prepared.completeError(
        const FerryxException(FerryxErrorKind.cancelled, 'preview closed'),
      );
    }
  }
}

void main() {
  setUpAll(WorkspaceHarness.registerFallbacks);
  late WorkspaceHarness h;
  setUp(() async {
    h = WorkspaceHarness();
    await h.setUp(vim: true);
    h.addFolder('/home/docs', ['d.pdf']);
    final bytes = Uint8List.fromList(utf8.encode('Preview geometry\n'));
    when(() => h.files.fileSize(any())).thenAnswer((_) async => bytes.length);
    when(() => h.files.readRange(any(), any(), any())).thenAnswer(
      (call) async => Uint8List.sublistView(
        bytes,
        call.positionalArguments[1] as int,
        ((call.positionalArguments[1] as int) +
                (call.positionalArguments[2] as int))
            .clamp(0, bytes.length),
      ),
    );
    when(() => h.files.preparePreview(any())).thenAnswer(
      (_) => _PendingPreview(),
    );
  });
  tearDown(() => h.tearDown());

  for (final style in AppPlatformStyle.values) {
    for (final large in [false, true]) {
      testWidgets('${style.name}: file and viewer footer edges meet '
          'with ${large ? 'large Russian' : 'normal English'} text', (
        tester,
      ) async {
        final locale = Locale(large ? 'ru' : 'en');
        await h.pump(
          tester,
          style: style,
          locale: locale,
          brightness: large ? Brightness.dark : Brightness.light,
          size: Size(large ? 800 : 1200, 800),
          textScale: large ? 1.75 : 1,
          preview: WorkspacePreview(
            builder: (context, view) => switch (view.location) {
              final location? => ViewerScreen(
                key: ValueKey(location),
                files: h.files,
                preferences: h.preferences,
                shortcutMap: h.shortcutMap,
                windowDecor: view.decor,
                location: location,
                startInPreview: view.startInPreview,
                autofocus: false,
                focusScope: view.focusScope,
                fullWindow: view.fullWindow,
                onClose: view.onClose,
                onFocusFiles: view.onFocusFiles,
                onToggleFullWindow: view.onToggleFullWindow,
              ),
              null => ViewerPlaceholder(
                focusScope: view.focusScope,
                shortcutMap: h.shortcutMap,
                windowDecor: view.decor,
                fullWindow: view.fullWindow,
                onClose: view.onClose,
                onFocusFiles: view.onFocusFiles,
                onToggleFullWindow: view.onToggleFullWindow,
              ),
            },
          ),
        );

        void expectAligned(Finder viewer) {
          final fileBar = tester.getRect(
            find
                .descendant(
                  of: find.byType(PanelView),
                  matching: find.byType(AppTopBarRow),
                )
                .first,
          );
          final previewBar = tester.getRect(
            find
                .descendant(
                  of: viewer,
                  matching: find.byType(AppTopBarRow),
                )
                .first,
          );
          expect(previewBar.top, fileBar.top);
          expect(previewBar.bottom, fileBar.bottom);
          final footer = find.descendant(
            of: viewer,
            matching: find.byType(AppStatusBar),
          );
          expect(footer, findsOneWidget);
          final fileRect = tester.getRect(find.byType(PanelFooter));
          final previewRect = tester.getRect(footer);
          expect(previewRect.top, fileRect.top);
          expect(previewRect.bottom, fileRect.bottom);
          expect(
            previewRect.height,
            tester.getSize(find.byType(KeyHintStrip)).height,
          );
          final context = tester.element(footer);
          final l10n = lookupFerryxLocalizations(locale);
          for (final label in [
            l10n.viewerCloseHint(
              h.shortcutMap.labelOf(AppCommand.dismiss, context.platform)!,
            ),
            l10n.viewerFilesHint(
              h.shortcutMap.labelOf(AppCommand.switchPanel, context.platform)!,
            ),
          ]) {
            final hint = find.descendant(
              of: footer,
              matching: find.text(label),
            );
            expect(hint, findsOneWidget);
            final rect = tester.getRect(hint);
            expect(rect.top, greaterThanOrEqualTo(previewRect.top));
            expect(rect.bottom, lessThanOrEqualTo(previewRect.bottom));
            expect(rect.right, lessThanOrEqualTo(previewRect.right));
          }
          expect(tester.takeException(), isNull);
        }

        // A folder, text and a pending PDF must all reserve the same row.
        await h.press(tester, LogicalKeyboardKey.keyI, character: 'i');
        expectAligned(find.byType(ViewerPlaceholder));
        for (var row = 0; row < 4; row++) {
          await h.press(tester, LogicalKeyboardKey.arrowDown);
          expectAligned(find.byType(ViewerScreen));
        }
        expect(
          tester.widget<ViewerScreen>(find.byType(ViewerScreen)).location.name,
          'd.pdf',
        );
        await h.press(tester, LogicalKeyboardKey.f3);
        expect(find.byType(PanelFooter), findsNothing);
        await h.press(tester, LogicalKeyboardKey.tab);
        expectAligned(find.byType(ViewerScreen));
        await h.press(tester, LogicalKeyboardKey.escape);
        expect(find.byType(ViewerScreen), findsNothing);
        expect(find.byType(PanelFooter), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
