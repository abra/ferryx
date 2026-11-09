import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_text_selection/native_text_selection.dart';
import 'package:pagecraft/all_formats.dart';
import 'package:pagecraft/src/text_book/text_native_selection.dart';

const _style = BookStyle(fontScale: 12 / 16, lineHeight: 1.5);

({ContentDocument document, ColumnLayout column, List<ColumnPage> pages})
_layout(String html, {double height = 200}) {
  final document = ContentDocument.parseXml(
    '<html xmlns="http://www.w3.org/1999/xhtml"><body>$html</body></html>',
  );
  final styles =
      StyleResolver([
        CssSheetSource(
          CssStyleSheet.parse(cssUserAgentStyleSheet),
          CssOrigin.userAgent,
        ),
        ...readerSheetSources(_style),
      ]).resolve(
        document,
        options: StyleResolverOptions(rootFontSize: _style.rootFontSize),
      );
  final column = ColumnLayout.layout(
    buildSectionBoxes(document, styles),
    width: 280,
    pageHeight: height,
    bookStyle: _style,
    text: TextLayoutEnvironment(
      styler: InlineStyler(bookStyle: _style, fonts: const BookFonts()),
      imageSize: (_) => null,
      maxImageHeight: height,
    ),
  );
  addTearDown(column.dispose);
  return (
    document: document,
    column: column,
    pages: paginateColumn(column, pageHeight: height),
  );
}

class _SelectionFixture extends StatelessWidget {
  const _SelectionFixture({
    required this.viewportKey,
    required this.column,
    required this.pages,
    required this.images,
    required this.document,
    required this.onRegion,
    this.vertical = false,
    this.shift = Offset.zero,
    this.selectionKey,
  });

  final GlobalKey viewportKey;
  final ColumnLayout column;
  final List<ColumnPage> pages;
  final BookImageCache images;
  final ContentDocument document;
  final ValueChanged<SelectionHandler?> onRegion;
  final bool vertical;
  final Offset shift;
  final GlobalKey<SelectionAreaState>? selectionKey;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        key: viewportKey,
        width: 700,
        height: 500,
        child: SelectionArea(
          key: selectionKey,
          child: TextSelectionRegionProbe(
            onRegion: onRegion,
            child: Transform.translate(
              offset: shift,
              child: Flex(
                direction: vertical ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final page in pages)
                    TextColumnPage(
                      column: column,
                      page: page,
                      images: images,
                      imageKey: (src) => src,
                      document: document,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  late BookImageCache images;
  setUp(() => images = BookImageCache(read: (_) async => null));
  tearDown(() => images.dispose());

  testWidgets('native offsets retain inline-node source positions', (
    tester,
  ) async {
    final (:document, :column, :pages) = _layout(
      '<p>Alpha <em>beta</em> gamma.</p><p>Second paragraph.</p>',
    );
    final key = GlobalKey();
    SelectionHandler? region;
    await tester.pumpWidget(
      _SelectionFixture(
        viewportKey: key,
        column: column,
        pages: [pages.first],
        images: images,
        document: document,
        onRegion: (value) => region = value,
      ),
    );
    await tester.pump();
    final page = tester.renderObject<RenderTextColumnPage>(
      find.byType(TextColumnPage),
    );
    final geometry = TextNativeSelectionGeometry.capture(
      [page],
      key.currentContext!.findRenderObject()! as RenderBox,
    );
    final start = geometry.text.indexOf('beta');
    region!
      ..dispatchSelectionEvent(
        SelectionEdgeUpdateEvent.forStart(
          globalPosition: geometry.edgeAt(start, isEnd: false)!,
        ),
      )
      ..dispatchSelectionEvent(
        SelectionEdgeUpdateEvent.forEnd(
          globalPosition: geometry.edgeAt(start + 4, isEnd: true)!,
        ),
      );
    await tester.pump();
    final selected = page.selection!;
    expect(selected.text, 'beta');
    expect(document.textOf(selected.start.node), 'beta');
    expect(selected.start.offset, 0);
    expect(selected.end.offset, 4);
    expect(
      geometry.selection,
      TextSelection(baseOffset: start, extentOffset: start + 4),
    );
    // Highlight persistence consumes these same original document points.
    final cfi = document.cfiRangeOf(
      TextPointRange(selected.start, selected.end),
    );
    expect(cfi.start.offset, 0);
    expect(cfi.end.offset, 4);
  });

  testWidgets('native cells preserve emoji and combining grapheme ranges', (
    tester,
  ) async {
    const text = 'A 👩🏽‍💻 e\u0301 Z';
    final (:document, :column, :pages) = _layout('<p>$text</p>');
    final key = GlobalKey();
    await tester.pumpWidget(
      _SelectionFixture(
        viewportKey: key,
        column: column,
        pages: [pages.first],
        images: images,
        document: document,
        onRegion: (_) {},
      ),
    );
    await tester.pump();
    final geometry = TextNativeSelectionGeometry.capture(
      tester.renderObjectList<RenderTextColumnPage>(
        find.byType(TextColumnPage),
      ),
      key.currentContext!.findRenderObject()! as RenderBox,
    );
    expect(geometry.text, text);
    final boundaries = <int>{0};
    var offset = 0;
    for (final grapheme in text.characters) {
      offset += grapheme.length;
      boundaries.add(offset);
    }
    expect(geometry.boxes, isNotEmpty);
    expect(
      geometry.boxes.map((box) => (box.start, box.end)).toSet(),
      hasLength(geometry.boxes.length),
      reason: 'A grapheme has one atomic native cell across font fragments',
    );
    for (final box in geometry.boxes) {
      expect(boundaries, contains(box.start));
      expect(boundaries, contains(box.end));
    }
  });

  testWidgets('RTL native edges select exact source range', (tester) async {
    const text = 'مرحبا بالعالم';
    final (:document, :column, :pages) = _layout('<p dir="rtl">$text</p>');
    final key = GlobalKey();
    SelectionHandler? region;
    await tester.pumpWidget(
      _SelectionFixture(
        viewportKey: key,
        column: column,
        pages: [pages.first],
        images: images,
        document: document,
        onRegion: (value) => region = value,
      ),
    );
    await tester.pump();
    final page = tester.renderObject<RenderTextColumnPage>(
      find.byType(TextColumnPage),
    );
    final geometry = TextNativeSelectionGeometry.capture(
      [page],
      key.currentContext!.findRenderObject()! as RenderBox,
    );
    expect(
      geometry.boxes.every((box) => box.direction == TextDirection.rtl),
      isTrue,
    );
    region!
      ..dispatchSelectionEvent(
        SelectionEdgeUpdateEvent.forStart(
          globalPosition: geometry.edgeAt(0, isEnd: false)!,
        ),
      )
      ..dispatchSelectionEvent(
        SelectionEdgeUpdateEvent.forEnd(
          globalPosition: geometry.edgeAt(5, isEnd: true)!,
        ),
      );
    await tester.pump();
    expect(page.selection?.text, 'مرحبا');
    expect(page.selection?.start.offset, 0);
    expect(page.selection?.end.offset, 5);
  });

  testWidgets('two-page spread carries distinct physical native regions', (
    tester,
  ) async {
    final (:document, :column, :pages) = _layout(
      '<p>${'Alpha beta gamma delta. ' * 18}</p>',
      height: 100,
    );
    final key = GlobalKey();
    await tester.pumpWidget(
      _SelectionFixture(
        viewportKey: key,
        column: column,
        pages: pages.take(2).toList(),
        images: images,
        document: document,
        onRegion: (_) {},
      ),
    );
    await tester.pump();
    final geometry = TextNativeSelectionGeometry.capture(
      tester.renderObjectList<RenderTextColumnPage>(
        find.byType(TextColumnPage),
      ),
      key.currentContext!.findRenderObject()! as RenderBox,
    );
    expect(geometry.regions, hasLength(2));
    expect(geometry.regions.first.rect.right, geometry.regions.last.rect.left);
    expect(geometry.regions.first.start, 0);
    expect(geometry.regions.first.end, geometry.regions.last.start);
    expect(geometry.regions.last.end, geometry.text.length);
  });

  testWidgets('vertical article slices share one continuous native region', (
    tester,
  ) async {
    final (:document, :column, :pages) = _layout(
      '<p>${'Alpha beta gamma delta. ' * 18}</p>',
      height: 100,
    );
    final key = GlobalKey();
    await tester.pumpWidget(
      _SelectionFixture(
        viewportKey: key,
        column: column,
        pages: pages.take(2).toList(),
        images: images,
        document: document,
        onRegion: (_) {},
        vertical: true,
      ),
    );
    await tester.pump();
    final geometry = TextNativeSelectionGeometry.capture(
      tester.renderObjectList<RenderTextColumnPage>(
        find.byType(TextColumnPage),
      ),
      key.currentContext!.findRenderObject()! as RenderBox,
    );
    expect(geometry.regions, hasLength(1));
    expect(geometry.regions.single.start, 0);
    expect(geometry.regions.single.end, geometry.text.length);
  });

  testWidgets('cached glyph geometry follows a moved page', (tester) async {
    final (:document, :column, :pages) = _layout('<p>Alpha beta gamma.</p>');
    final key = GlobalKey();
    await tester.pumpWidget(
      _SelectionFixture(
        viewportKey: key,
        column: column,
        pages: [pages.first],
        images: images,
        document: document,
        onRegion: (_) {},
      ),
    );
    await tester.pump();
    final page = tester.renderObject<RenderTextColumnPage>(
      find.byType(TextColumnPage),
    );
    final viewport = key.currentContext!.findRenderObject()! as RenderBox;
    final original = TextNativeSelectionGeometry.capture([page], viewport);
    expect(original.matches([page], viewport), isTrue);
    const shift = Offset(8, 12);
    await tester.pumpWidget(
      _SelectionFixture(
        viewportKey: key,
        column: column,
        pages: [pages.first],
        images: images,
        document: document,
        onRegion: (_) {},
        shift: shift,
      ),
    );
    await tester.pump();
    expect(original.matches([page], viewport), isFalse);
    final moved = TextNativeSelectionGeometry.capture([page], viewport);
    expect(moved.boxes.first.rect, original.boxes.first.rect.shift(shift));
  });

  for (final custom in [false, true]) {
    testWidgets(
      'native-active selection preserves ${custom ? 'caller' : 'default'} actions',
      (tester) async {
        const capabilities = MethodChannel(
          'io.github.abra.native_text_selection/capabilities',
        );
        final messenger = tester.binding.defaultBinaryMessenger;
        NativeSelectionPlatform.resetAvailability();
        messenger.setMockMethodCallHandler(capabilities, (_) async => true);
        addTearDown(() {
          messenger.setMockMethodCallHandler(capabilities, null);
          NativeSelectionPlatform.resetAvailability();
        });
        final (:document, :column, :pages) = _layout(
          '<p>Alpha beta gamma.</p>',
        );
        final key = GlobalKey();
        final selectionKey = GlobalKey<SelectionAreaState>();
        SelectionHandler? region;
        var customActions = 0;
        await tester.pumpWidget(
          _SelectionFixture(
            viewportKey: key,
            selectionKey: selectionKey,
            column: column,
            pages: [pages.first],
            images: images,
            document: document,
            onRegion: (value) => region = value,
          ),
        );
        await tester.pump();
        final page = tester.renderObject<RenderTextColumnPage>(
          find.byType(TextColumnPage),
        );
        final viewport = key.currentContext!.findRenderObject()! as RenderBox;
        final geometry = TextNativeSelectionGeometry.capture([page], viewport);
        region!
          ..dispatchSelectionEvent(
            SelectionEdgeUpdateEvent.forStart(
              globalPosition: geometry.edgeAt(6, isEnd: false)!,
            ),
          )
          ..dispatchSelectionEvent(
            SelectionEdgeUpdateEvent.forEnd(
              globalPosition: geometry.edgeAt(10, isEnd: true)!,
            ),
          );
        await tester.pump();
        final before = page.selection!;
        final controller = TextNativeSelectionController(
          pages: () => [page],
          viewport: () => key.currentContext!,
          region: () => region,
          selectionState: () => selectionKey.currentState?.selectableRegion,
          contextMenuBuilder: () => custom
              ? (context, state) => TextButton(
                  onPressed: () {
                    customActions++;
                    ContextMenuController.removeAny();
                  },
                  child: const Text('Custom action'),
                )
              : null,
          onChanged: () {},
          onClear: () =>
              selectionKey.currentState?.selectableRegion.clearSelection(),
        );
        await tester.pumpAndSettle();
        expect(
          controller.snapshot?.selection,
          const TextSelection(baseOffset: 6, extentOffset: 10),
        );
        controller.setActive(true);
        await tester.pumpAndSettle();
        final label = custom ? 'Custom action' : 'Copy';
        expect(find.text(label), findsOneWidget);
        controller.setAdjusting(true);
        await tester.pumpAndSettle();
        expect(find.text(label), findsNothing);
        controller.setSelection(
          const TextSelection(baseOffset: 0, extentOffset: 5),
        );
        await tester.pumpAndSettle();
        expect(page.selection?.text, 'Alpha');
        expect(page.selection?.start.offset, 0);
        expect(page.selection?.end.offset, 5);
        expect(find.text(label), findsNothing);
        controller.setSelection(
          const TextSelection(baseOffset: 6, extentOffset: 10),
        );
        await tester.pumpAndSettle();
        controller.setAdjusting(false);
        await tester.pumpAndSettle();
        expect(find.text(label), findsOneWidget);
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(find.text(label), findsNothing);
        expect(page.selection?.text, 'beta');
        expect(page.selection?.start, before.start);
        expect(page.selection?.end, before.end);
        expect(customActions, custom ? 1 : 0);
        controller.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }

  testWidgets(
    'cleared source selection removes native UI during deferred refresh',
    (tester) async {
      const capabilities = MethodChannel(
        'io.github.abra.native_text_selection/capabilities',
      );
      final messenger = tester.binding.defaultBinaryMessenger;
      NativeSelectionPlatform.resetAvailability();
      messenger.setMockMethodCallHandler(capabilities, (_) async => true);
      addTearDown(() {
        messenger.setMockMethodCallHandler(capabilities, null);
        NativeSelectionPlatform.resetAvailability();
      });
      final (:document, :column, :pages) = _layout('<p>Alpha beta gamma.</p>');
      final key = GlobalKey();
      final selectionKey = GlobalKey<SelectionAreaState>();
      SelectionHandler? region;
      await tester.pumpWidget(
        _SelectionFixture(
          viewportKey: key,
          selectionKey: selectionKey,
          column: column,
          pages: [pages.first],
          images: images,
          document: document,
          onRegion: (value) => region = value,
        ),
      );
      await tester.pump();
      final page = tester.renderObject<RenderTextColumnPage>(
        find.byType(TextColumnPage),
      );
      final geometry = TextNativeSelectionGeometry.capture([
        page,
      ], key.currentContext!.findRenderObject()! as RenderBox);
      region!
        ..dispatchSelectionEvent(
          SelectionEdgeUpdateEvent.forStart(
            globalPosition: geometry.edgeAt(6, isEnd: false)!,
          ),
        )
        ..dispatchSelectionEvent(
          SelectionEdgeUpdateEvent.forEnd(
            globalPosition: geometry.edgeAt(10, isEnd: true)!,
          ),
        );
      final controller = TextNativeSelectionController(
        pages: () => [page],
        viewport: () => key.currentContext!,
        region: () => region,
        selectionState: () => selectionKey.currentState?.selectableRegion,
        contextMenuBuilder: () => null,
        onChanged: () {},
        onClear: () =>
            selectionKey.currentState?.selectableRegion.clearSelection(),
      );
      addTearDown(controller.dispose);
      await tester.pumpAndSettle();
      controller.setActive(true);
      await tester.pumpAndSettle();
      expect(controller.snapshot, isNotNull);
      expect(find.text('Copy'), findsOneWidget);
      // Scrollable wins the gesture and SelectableRegion cancels its source
      // selection while TextScrollView still has a pointer down.
      selectionKey.currentState!.selectableRegion.clearSelection();
      controller.refresh(deferred: true);
      await tester.pumpAndSettle();
      expect(page.selection, isNull);
      expect(controller.snapshot, isNull);
      expect(find.text('Copy'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
