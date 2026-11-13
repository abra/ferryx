import 'package:component_library/component_library.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// A host that filters [words] by the query typed, as a caller does.
class _Host extends StatefulWidget {
  const _Host({
    required this.words,
    required this.onPick,
    this.onDismiss,
    this.captions = false,
    this.actions = const {AppQuickPickerAction.primary},
  });

  final List<String> words;
  final ValueChanged<AppQuickPick<String>> onPick;
  final VoidCallback? onDismiss;
  final bool captions;
  final Set<AppQuickPickerAction> actions;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final matching = [
      for (final w in widget.words)
        if (w.contains(query)) w,
    ];
    return AppQuickPicker<String>(
      entries: [
        if (widget.captions && matching.isNotEmpty)
          const AppQuickPickerHeader('Group A'),
        for (var i = 0; i < matching.length; i++) ...[
          if (widget.captions && i == 2) const AppQuickPickerHeader('Group B'),
          AppQuickPickerItem(
            value: matching[i],
            label: matching[i],
            labelHighlights: query.isEmpty
                ? const []
                : [
                    (
                      matching[i].indexOf(query),
                      matching[i].indexOf(query) + query.length,
                    ),
                  ],
            detail: 'detail of ${matching[i]}',
            keys: const ['K'],
          ),
        ],
      ],
      hintText: 'Type',
      noResultsText: 'Nothing matches',
      emptyText: 'Nothing yet',
      hints: const [('X', 'run')],
      actions: widget.actions,
      onQueryChanged: (q) => setState(() => query = q),
      onPick: widget.onPick,
      onDismiss: widget.onDismiss,
    );
  }
}

void main() {
  late List<AppQuickPick<String>> picks;
  late int dismissed;

  setUp(() {
    picks = [];
    dismissed = 0;
  });

  Future<void> pump(
    WidgetTester tester,
    List<String> words, {
    bool captions = false,
    Set<AppQuickPickerAction> actions = const {AppQuickPickerAction.primary},
    AppPlatformStyle style = AppPlatformStyle.macos,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(style),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: _Host(
                words: words,
                captions: captions,
                actions: actions,
                onPick: picks.add,
                onDismiss: () => dismissed++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The label of the lit row: drawn on the selection accent.
  String? lit(WidgetTester tester) {
    final theme = Theme.of(tester.element(find.byType(AppQuickPicker<String>)));
    final accent = theme.extension<AppColorsExt>()!.selectionAccent;
    for (final element in find.byType(Container).evaluate()) {
      final container = element.widget as Container;
      final decoration = container.decoration;
      if (decoration is BoxDecoration && decoration.color == accent) {
        final texts = find.descendant(
          of: find.byWidget(container),
          matching: find.byType(RichText),
        );
        return (tester.widget<RichText>(texts.first).text).toPlainText();
      }
    }
    return null;
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
  }

  testWidgets('the first item is lit; the arrows go round the ends and '
      'skip the captions', (tester) async {
    await pump(tester, ['alpha', 'beta', 'gamma'], captions: true);
    expect(lit(tester), 'alpha');
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(lit(tester), 'beta');
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(lit(tester), 'gamma');
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(lit(tester), 'alpha');
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(lit(tester), 'gamma');
    expect(find.text('Group A'), findsOneWidget);
    expect(find.text('Group B'), findsOneWidget);
  });

  testWidgets('Return picks the lit item; the primary key and Option ask '
      'for the other actions', (tester) async {
    await pump(
      tester,
      ['alpha', 'beta'],
      actions: AppQuickPickerAction.values.toSet(),
    );
    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.enter);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await key(tester, LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.alt);
    await key(tester, LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.alt);
    expect(picks, const [
      AppQuickPick('beta'),
      AppQuickPick('beta', AppQuickPickerAction.secondary),
      AppQuickPick('beta', AppQuickPickerAction.alternate),
    ]);
  });

  testWidgets('an action the picker does not offer falls back to the '
      'primary one', (tester) async {
    await pump(tester, ['alpha']);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await key(tester, LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    expect(picks, const [AppQuickPick('alpha')]);
  });

  testWidgets('Esc leaves', (tester) async {
    await pump(tester, ['alpha']);
    await key(tester, LogicalKeyboardKey.escape);
    expect(dismissed, 1);
    expect(picks, isEmpty);
  });

  testWidgets('typing asks for new rows and lights the first of them', (
    tester,
  ) async {
    await pump(tester, ['alpha', 'beta', 'alphabet']);
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(lit(tester), 'beta');
    await tester.enterText(find.byType(EditableText), 'alph');
    await tester.pump();
    expect(lit(tester), 'alpha');
    expect(find.text('beta'), findsNothing);
    // What matched is set apart.
    final label = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((r) => r.text)
        .whereType<TextSpan>()
        .firstWhere((s) => s.toPlainText() == 'alphabet');
    final spans = <TextSpan>[];
    label.visitChildren((span) {
      if (span is TextSpan && span.text != null) spans.add(span);
      return true;
    });
    expect(spans.first.text, 'alph');
    expect(spans.first.style?.fontWeight, FontWeight.w700);
  });

  testWidgets('nothing to pick: the empty text, then the no-results one', (
    tester,
  ) async {
    await pump(tester, const []);
    expect(find.text('Nothing yet'), findsOneWidget);
    await pump(tester, ['alpha']);
    await tester.enterText(find.byType(EditableText), 'zzz');
    await tester.pump();
    expect(find.text('Nothing matches'), findsOneWidget);
    await key(tester, LogicalKeyboardKey.enter);
    expect(picks, isEmpty);
  });

  testWidgets('a long list builds the rows in view only; End, Home and the '
      'page keys reach every row', (tester) async {
    final words = [for (var i = 0; i < 1000; i++) 'item $i'];
    await pump(tester, words);
    expect(find.text('item 999'), findsNothing);
    expect(
      find.byType(AppMiddleEllipsis).evaluate().length,
      lessThan(60),
      reason: 'rows out of view are not built',
    );
    await key(tester, LogicalKeyboardKey.end);
    expect(lit(tester), 'item 999');
    expect(find.text('item 999'), findsOneWidget);
    await key(tester, LogicalKeyboardKey.home);
    expect(lit(tester), 'item 0');
    await key(tester, LogicalKeyboardKey.pageDown);
    final paged = int.parse(lit(tester)!.split(' ').last);
    expect(paged, greaterThan(5));
    await key(tester, LogicalKeyboardKey.pageUp);
    expect(lit(tester), 'item 0');
    await key(tester, LogicalKeyboardKey.pageUp);
    expect(lit(tester), 'item 0', reason: 'the page keys stop at the ends');
  });

  testWidgets('the pointer lights a row by moving over it; a click picks', (
    tester,
  ) async {
    await pump(tester, ['alpha', 'beta', 'gamma']);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('gamma')));
    await tester.pump();
    expect(lit(tester), 'gamma');
    await tester.tap(find.text('beta'));
    await tester.pump();
    expect(picks, const [AppQuickPick('beta')]);
  });

  testWidgets('rows grow with the text, never under the platform\'s row', (
    tester,
  ) async {
    for (final style in AppPlatformStyle.values) {
      await pump(tester, ['alpha'], style: style);
      final context = tester.element(find.byType(AppQuickPicker<String>));
      final small = AppQuickPicker.rowExtentOf(context);
      expect(small, greaterThanOrEqualTo(context.metrics.navItemHeight));
      await pump(tester, ['alpha'], style: style, textScale: 1.6);
      final large = AppQuickPicker.rowExtentOf(
        tester.element(find.byType(AppQuickPicker<String>)),
      );
      expect(large, greaterThan(small));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('showAppQuickPicker answers the pick and gives the focus back', (
    tester,
  ) async {
    final opener = FocusNode(debugLabel: 'opener');
    addTearDown(opener.dispose);
    AppQuickPick<String>? answer;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        home: Scaffold(
          body: Builder(
            builder: (context) => Focus(
              focusNode: opener,
              autofocus: true,
              child: TextButton(
                onPressed: () async {
                  answer = await showAppQuickPicker<AppQuickPick<String>>(
                    context,
                    builder: (context) => AppQuickPicker<String>(
                      entries: const [
                        AppQuickPickerItem(value: 'one', label: 'One'),
                        AppQuickPickerItem(value: 'two', label: 'Two'),
                      ],
                      hintText: 'Type',
                      noResultsText: 'None',
                      onQueryChanged: (_) {},
                      onPick: (pick) => Navigator.of(context).pop(pick),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(opener.hasFocus, isFalse);
    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(answer, const AppQuickPick('two'));
    expect(find.text('One'), findsNothing);
    expect(opener.hasFocus, isTrue);
  });
}
