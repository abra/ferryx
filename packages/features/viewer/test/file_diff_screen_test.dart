import 'package:component_library/component_library.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shortcuts/shortcuts.dart';
import 'package:viewer_feature/src/file_diff_screen.dart';
import 'package:viewer_feature/src/viewer_source.dart';

class _Source implements ViewerSource {
  _Source(this.displayPath, this.text);
  final String text;
  @override
  final String displayPath;
  @override
  String get displayName => 'same-name.txt';
  @override
  bool get isNative => true;
  @override
  String? get nativePath => '$displayPath/$displayName';
  @override
  Future<int> size() async => text.length;
  @override
  Future<Uint8List> read(int offset, int length) async =>
      Uint8List.fromList(text.codeUnits);
}

void main() {
  final en = lookupFerryxLocalizations(const Locale('en'));
  for (final same in [false, true]) {
    testWidgets(
      'diff hints use actual bindings and omit absent changes: identical=$same',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final map = ShortcutMap.defaults(TargetPlatform.macOS).rebind(
          AppCommand.viewerFindNext,
          const [Chord(LogicalKeyboardKey.keyN, primary: true)],
        );
        var closed = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(AppPlatformStyle.macos),
            localizationsDelegates: FerryxSupportedLocales.delegates,
            supportedLocales: FerryxSupportedLocales.locales,
            home: FileDiffScreen(
              left: _Source('/before', 'a\nold\nc\nold2\ne'),
              right: _Source(
                '/after',
                same ? 'a\nold\nc\nold2\ne' : 'a\nnew\nc\nnew2\ne',
              ),
              shortcutMap: map,
              onClose: () => closed = true,
            ),
          ),
        );
        for (
          var i = 0;
          i < 100 && find.byType(ListView).evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        await tester.pump();
        final hints = tester
            .widget<AppKeyHints>(
              find.descendant(
                of: find.byType(AppStatusBar),
                matching: find.byType(AppKeyHints),
              ),
            )
            .hints;
        expect(hints.any((hint) => hint.label == en.diffNext), !same);
        expect(hints.any((hint) => hint.label == en.diffPrevious), !same);
        if (!same) {
          expect(hints.firstWhere((hint) => hint.label == en.diffNext).keys, [
            map.labelOf(AppCommand.viewerFindNext, TargetPlatform.macOS),
          ]);
          expect(find.text(en.diffChangeCount(1, 2)), findsOneWidget);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
          await tester.pump();
          expect(find.text(en.diffChangeCount(2, 2)), findsOneWidget);
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(closed, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final brightness in Brightness.values) {
    testWidgets(
      'diff handles long paths, narrow window and scrolling in ${brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(480, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.of(AppPlatformStyle.macos, brightness),
            localizationsDelegates: FerryxSupportedLocales.delegates,
            supportedLocales: FerryxSupportedLocales.locales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(1.5)),
              child: child!,
            ),
            home: FileDiffScreen(
              left: _Source(
                '/a/very/long/path/to/original',
                List.generate(300, (i) => 'original line $i').join('\n'),
              ),
              right: _Source(
                '/another/very/long/path/to/changed',
                List.generate(300, (i) => 'changed line $i').join('\n'),
              ),
              shortcutMap: ShortcutMap.defaults(TargetPlatform.macOS),
              onClose: () {},
            ),
          ),
        );
        for (
          var i = 0;
          i < 100 && find.byType(ListView).evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(find.byType(ListView), findsNWidgets(2));
        final lists = tester
            .widgetList<ListView>(find.byType(ListView))
            .toList();
        lists.first.controller!.jumpTo(500);
        await tester.pump();
        expect(lists.last.controller!.offset, 500);
        await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
        await tester.pump();
        expect(lists.first.controller!.offset, greaterThan(500));
        expect(lists.last.controller!.offset, lists.first.controller!.offset);
        expect(
          find.byWidgetPredicate(
            (w) => w is AppMiddleEllipsis && w.text.contains('/original/'),
          ),
          findsOneWidget,
        );
        expect(
          find.byWidgetPredicate(
            (w) => w is AppIconButton && w.tooltip == en.diffNext,
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
