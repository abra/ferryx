import 'dart:convert';
import 'dart:io';

import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:panels_feature/panels_feature.dart';
import 'package:viewer_feature/src/text_layout.dart';
import 'package:viewer_feature/src/viewer_views.dart';
import 'package:viewer_feature/viewer_feature.dart';

import '../../packages/features/panels/test/support/workspace_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Uint8List bytes;
  late WorkspaceHarness h;
  final en = lookupFerryxLocalizations(const Locale('en'));

  setUpAll(() async {
    WorkspaceHarness.registerFallbacks();
    for (final (family, asset) in [
      ('Inter', 'Inter-Variable.ttf'),
      ('Geist Mono', 'GeistMono-Variable.ttf'),
      ('.AppleSystemUIFont', 'Inter-Variable.ttf'),
      ('.AppleSystemUIFontMonospaced', 'GeistMono-Variable.ttf'),
    ]) {
      await (FontLoader(family)..addFont(
            rootBundle.load('packages/component_library/fonts/$asset'),
          ))
          .load();
    }
    final fixture = Platform.environment['FERRYX_LARGE_TEXT_FIXTURE'];
    if (fixture != null) {
      bytes = await File(fixture).readAsBytes();
    } else {
      const length = 24 * 1024 * 1024;
      bytes = Uint8List(length)..fillRange(0, length, 0x61);
      final prefix = utf8.encode('{"payload":"');
      bytes.setRange(0, prefix.length, prefix);
      bytes.setRange(length - 2, length, utf8.encode('"}'));
    }
  });

  setUp(() async {
    h = WorkspaceHarness();
    await h.setUp(vim: true);
    await h.preferences.update(
      (p) => p.copyWith(
        viewerFontSize: 14,
        viewerWrap: true,
        textScale: 1.2,
        singlePane: false,
      ),
    );
    h.folders['${WorkspaceHarness.home}/docs'] = [
      h.file('${WorkspaceHarness.home}/docs', 'large.json', size: bytes.length),
      h.file('${WorkspaceHarness.home}/docs', 'small.txt', size: 5),
    ];
    when(() => h.files.fileSize(any())).thenAnswer(
      (call) async =>
          (call.positionalArguments[0] as Location).name == 'large.json'
          ? bytes.length
          : 5,
    );
    when(() => h.files.readRange(any(), any(), any())).thenAnswer((call) async {
      final source =
          (call.positionalArguments[0] as Location).name == 'large.json'
          ? bytes
          : Uint8List.fromList(utf8.encode('small'));
      final offset = call.positionalArguments[1] as int;
      final length = call.positionalArguments[2] as int;
      return Uint8List.sublistView(
        source,
        offset,
        (offset + length).clamp(0, source.length),
      );
    });
  });
  tearDown(() => h.tearDown());

  for (final follow in [false, true]) {
    testWidgets(
      'workspace ${follow ? "selection follows" : "i opens"} large JSON with real fonts, fade and semantics',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await h.pump(
            tester,
            textScale: 1.2,
            brightness: Brightness.dark,
            preview: WorkspacePreview(
              builder: (context, view) {
                final location = view.location;
                if (location == null) return const SizedBox.shrink();
                return ViewerScreen(
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
                );
              },
            ),
          );
          final panelFinder = find.byType(PanelView).first;
          final panel = tester.element(panelFinder).read<PanelCubit>();
          final wanted = follow ? 'small.txt' : 'large.json';
          panel.moveCursorTo(
            panel.state.active!.rows.indexWhere((row) => row.name == wanted),
          );
          await tester.pump();
          final opening = Stopwatch()..start();
          await tester.sendKeyEvent(
            LogicalKeyboardKey.keyI,
            platform: 'macos',
            character: 'i',
          );
          await tester.pump();
          expect(find.byType(ViewerScreen), findsOneWidget);
          if (follow) {
            await tester.pump(const Duration(milliseconds: 200));
            await tester.tap(find.text('large.json', findRichText: true).first);
            // Single-click dispatch waits for the row's double-click recognizer.
            await tester.pump(const Duration(milliseconds: 350));
            await tester.pump(const Duration(milliseconds: 200));
            expect(panel.state.active!.focused!.name, 'large.json');
          }

          var loaded = false;
          for (var i = 0; i < 200; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            // Let the worker finish without allowing the entrance fade to end.
            await tester.pump();
            final views = tester.widgetList<TextView>(find.byType(TextView));
            if (views.isNotEmpty &&
                views.single.window.lines.any(
                  (line) => line.length > maxTextParagraphLength,
                )) {
              loaded = true;
              break;
            }
          }
          expect(loaded, isTrue);
          final view = tester.widget<TextView>(find.byType(TextView));
          expect(view.wrap, isTrue);
          expect(view.fontSize, 14);
          final context = tester.element(find.byType(TextView));
          expect(
            charWidthOf(context, contentStyle(context, 14)),
            lessThan(14 * 1.2 * 0.8),
          );
          expect(
            tester
                .widgetList<TextLine>(find.byType(TextLine))
                .every(
                  (line) => line.text.length <= maxTextParagraphLength,
                ),
            isTrue,
          );
          // Force rasterization while the actual workspace entrance fade is active.
          await tester.pump(const Duration(milliseconds: 20));
          final fadeValues = tester
              .widgetList<FadeTransition>(
                find.ancestor(
                  of: find.byType(ViewerScreen),
                  matching: find.byType(FadeTransition),
                ),
              )
              .map((fade) => fade.opacity.value)
              .toList();
          if (!follow) {
            expect(
              fadeValues.any((opacity) => opacity > 0 && opacity < 1),
              isTrue,
            );
          }
          final image = await tester.runAsync(
            () => captureImage(h.shotKey.currentContext! as Element),
          );
          image?.dispose();
          await tester.pump(const Duration(milliseconds: 35));
          await tester.pumpAndSettle();
          expect(find.text(en.viewerLoadNext), findsOneWidget);
          expect(
            tester.widget<PanelView>(panelFinder).focusNode.hasFocus,
            isTrue,
          );
          expect(tester.takeException(), isNull);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab, platform: 'macos');
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(
            LogicalKeyboardKey.escape,
            platform: 'macos',
          );
          await tester.pumpAndSettle();
          expect(find.byType(ViewerScreen), findsNothing);
          expect(tester.takeException(), isNull);
          debugPrint(
            'Workspace large text: $follow, ${bytes.length} bytes, ${opening.elapsedMilliseconds} ms, fade values $fadeValues',
          );
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}
