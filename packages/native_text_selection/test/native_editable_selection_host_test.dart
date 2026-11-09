import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_text_selection/native_text_selection.dart';

const _viewType = 'io.github.abra.native_text_selection/surface';
const _capabilities = MethodChannel(
  'io.github.abra.native_text_selection/capabilities',
);

class _HostFixture extends StatelessWidget {
  const _HostFixture({required this.child, this.hosted = true});

  final Widget child;
  final bool hosted;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 280,
          child: hosted ? NativeEditableSelectionHost(child: child) : child,
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final updates = <Map<Object?, Object?>>[];
  final viewChannels = <MethodChannel>[];
  final platformCalls = <MethodCall>[];
  var available = true;

  setUp(() {
    available = true;
    updates.clear();
    viewChannels.clear();
    platformCalls.clear();
    NativeSelectionPlatform.resetAvailability();
    messenger.setMockMethodCallHandler(
      _capabilities,
      (call) async => available,
    );
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      platformCalls.add(call);
      if (call.method == 'create') {
        final arguments = call.arguments as Map<Object?, Object?>;
        final channel = MethodChannel('$_viewType/${arguments['id']}');
        viewChannels.add(channel);
        messenger.setMockMethodCallHandler(channel, (method) async {
          if (method.method == 'update') {
            updates.add(Map<Object?, Object?>.from(method.arguments as Map));
            return true;
          }
          return null;
        });
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_capabilities, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    for (final channel in viewChannels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    NativeSelectionPlatform.resetAvailability();
  });

  Future<void> nativeCall(String method, Map<String, Object> arguments) async {
    final channel = viewChannels.last;
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall(method, arguments)),
      (_) {},
    );
  }

  testWidgets('native range preserves original widget, state and callbacks', (
    tester,
  ) async {
    final changes = <TextSelection>[];
    await tester.pumpWidget(
      _HostFixture(
        child: SelectableText(
          'Alpha beta gamma',
          key: const ValueKey('originalText'),
          onSelectionChanged: (selection, cause) => changes.add(selection),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final state = tester.state<EditableTextState>(find.byType(EditableText));
    final controller = state.widget.controller;
    state.widget.focusNode.requestFocus();
    await tester.pumpAndSettle();
    state.userUpdateTextEditingValue(
      controller.value.copyWith(
        selection: const TextSelection(baseOffset: 6, extentOffset: 10),
      ),
      SelectionChangedCause.longPress,
    );
    await tester.pumpAndSettle();
    expect(updates, isNotEmpty);
    expect(updates.last['text'], 'Alpha beta gamma');
    final revision = updates.last['revision']! as int;
    await nativeCall('ready', {'revision': revision});
    await tester.pumpAndSettle();
    expect(state.renderEditable.selectionColor, Colors.transparent);
    expect(find.text('Copy'), findsOneWidget);
    await nativeCall('adjusting', {'revision': revision, 'value': true});
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsNothing);
    await nativeCall('selectionChanged', {
      'revision': revision,
      'base': 0,
      'extent': 5,
    });
    await tester.pumpAndSettle();
    expect(
      controller.selection,
      const TextSelection(baseOffset: 0, extentOffset: 5),
    );
    expect(changes.last, controller.selection);
    expect(tester.state(find.byType(EditableText)), same(state));
    expect(find.byKey(const ValueKey('originalText')), findsOneWidget);
    expect(find.text('Copy'), findsNothing);
    await nativeCall('adjusting', {'revision': revision, 'value': false});
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsOneWidget);
    // Selection-only messages reuse the cached native glyph document.
    expect(updates, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('editable text retains its keyboard and Flutter selection', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Editable text');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _HostFixture(child: TextField(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.showKeyboard(find.byType(TextField));
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 8);
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isTrue);
    expect(viewChannels, isEmpty);
    expect(updates, isEmpty);
    expect(controller.selection.extentOffset, 8);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('missing native registration preserves Flutter selection', (
    tester,
  ) async {
    available = false;
    await tester.pumpWidget(
      const _HostFixture(child: SelectableText('Fallback text')),
    );
    await tester.pumpAndSettle();
    final state = tester.state<EditableTextState>(find.byType(EditableText));
    state.widget.controller.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 8,
    );
    await tester.pumpAndSettle();
    expect(viewChannels, isEmpty);
    expect(state.widget.controller.selection.extentOffset, 8);
    expect(state.renderEditable.selectionColor, isNot(Colors.transparent));
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('native handles outside a short text box use the full overlay', (
    tester,
  ) async {
    var backgroundTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => backgroundTaps++,
            child: const Center(
              child: SizedBox(
                width: 280,
                child: NativeEditableSelectionHost(
                  child: SelectableText('Alpha beta gamma'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    final original = tester.getRect(find.byType(SelectableText));
    editable.widget.focusNode.requestFocus();
    await tester.pumpAndSettle();
    editable.widget.controller.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 5,
    );
    await tester.pumpAndSettle();
    final overlay = Overlay.of(editable.context, rootOverlay: true);
    final overlayBox = overlay.context.findRenderObject()! as RenderBox;
    expect(
      tester.getRect(find.byType(UiKitView)),
      overlayBox.localToGlobal(Offset.zero) & overlayBox.size,
    );
    expect(tester.getRect(find.byType(SelectableText)), original);
    final surface = tester.widget<NativeSelectionSurface>(
      find.byType(NativeSelectionSurface),
    );
    final snapshot = surface.snapshot!;
    await nativeCall('ready', {'revision': snapshot.revision});
    await tester.pumpAndSettle();
    final end = snapshot.boxes.firstWhere((box) => box.end == 5);
    final grip = overlayBox.localToGlobal(
      Offset(end.rect.right, end.rect.bottom + 10),
    );
    expect(original.contains(grip), isFalse);
    await tester.tapAt(grip);
    await tester.pumpAndSettle();
    expect(
      platformCalls.where((call) => call.method == 'acceptGesture'),
      isNotEmpty,
      reason: 'A native knob outside text bounds must receive its pointer',
    );
    expect(backgroundTaps, 0);
    await tester.tapAt(const Offset(700, 550));
    await tester.pumpAndSettle();
    expect(
      backgroundTaps,
      1,
      reason: 'Other page taps pass through the overlay',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('split font runs become one complete grapheme cell', (
    tester,
  ) async {
    const span = TextSpan(
      children: [
        TextSpan(text: 'A '),
        TextSpan(text: '👩', style: TextStyle(fontSize: 20)),
        TextSpan(text: '\u200D', style: TextStyle(fontSize: 21)),
        TextSpan(text: '🔬', style: TextStyle(fontSize: 24)),
        TextSpan(text: ' result'),
      ],
    );
    await tester.pumpWidget(
      const _HostFixture(child: SelectableText.rich(span)),
    );
    await tester.pumpAndSettle();
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    editable.widget.focusNode.requestFocus();
    await tester.pumpAndSettle();
    editable.widget.controller.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 1,
    );
    await tester.pumpAndSettle();
    const start = 2;
    const end = start + '👩‍🔬'.length;
    final parts = editable.renderEditable
        .getBoxesForSelection(
          const TextSelection(baseOffset: start, extentOffset: end),
        )
        .where((box) => !box.toRect().isEmpty)
        .toList();
    expect(
      parts.length,
      greaterThan(1),
      reason: 'Fixture forces separate font runs',
    );
    final snapshot = tester
        .widget<NativeSelectionSurface>(find.byType(NativeSelectionSurface))
        .snapshot!;
    final cells = snapshot.boxes.where((box) => box.start == start).toList();
    expect(cells, hasLength(1));
    expect(cells.single.end, end);
    expect(snapshot.text.substring(start, end), '👩‍🔬');
    final overlay = Overlay.of(editable.context, rootOverlay: true);
    final transform = editable.renderEditable.getTransformTo(
      overlay.context.findRenderObject(),
    );
    final union = parts
        .map((box) => box.toRect())
        .reduce((first, next) => first.expandToInclude(next));
    expect(cells.single.rect, MatrixUtils.transformRect(transform, union));
    expect(cells.single.direction, parts.first.direction);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets(
    'native overlay closes when another Flutter control gains focus',
    (tester) async {
      final otherFocus = FocusNode();
      addTearDown(otherFocus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const NativeEditableSelectionHost(
                  child: SelectableText(
                    'Focused source text',
                    key: ValueKey('focusedSource'),
                  ),
                ),
                TextButton(
                  focusNode: otherFocus,
                  onPressed: () {},
                  child: const Text('Other control'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final state = tester.state<EditableTextState>(find.byType(EditableText));
      final original = tester.getRect(find.byType(SelectableText));
      state.widget.focusNode.requestFocus();
      await tester.pumpAndSettle();
      state.userUpdateTextEditingValue(
        state.widget.controller.value.copyWith(
          selection: const TextSelection(baseOffset: 0, extentOffset: 7),
        ),
        SelectionChangedCause.longPress,
      );
      await tester.pumpAndSettle();
      final revision = updates.last['revision']! as int;
      await nativeCall('ready', {'revision': revision});
      await tester.pumpAndSettle();
      expect(find.byType(UiKitView), findsOneWidget);
      expect(state.renderEditable.selectionColor, Colors.transparent);
      otherFocus.requestFocus();
      await tester.pumpAndSettle();
      expect(otherFocus.hasFocus, isTrue);
      expect(find.byType(UiKitView), findsNothing);
      expect(find.byType(NativeSelectionSurface), findsNothing);
      expect(state.renderEditable.selectionColor, state.widget.selectionColor);
      expect(tester.getRect(find.byType(SelectableText)), original);
      expect(tester.state(find.byType(EditableText)), same(state));
      expect(find.byKey(const ValueKey('focusedSource')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'ancestor scroll suspends native controls until visible and settled',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.only(top: 100),
              child: SizedBox(
                height: 200,
                child: SingleChildScrollView(
                  controller: scroll,
                  child: const Column(
                    children: [
                      SizedBox(height: 80),
                      SizedBox(
                        width: 280,
                        child: NativeEditableSelectionHost(
                          child: SelectableText('Alpha beta gamma'),
                        ),
                      ),
                      SizedBox(height: 1400),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final editable = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      editable.widget.focusNode.requestFocus();
      await tester.pumpAndSettle();
      editable.widget.controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      await tester.pumpAndSettle();
      await nativeCall('ready', {'revision': updates.last['revision']! as int});
      await tester.pumpAndSettle();
      expect(find.byType(UiKitView), findsOneWidget);
      final before = updates.length;
      final textRect = tester.getRect(find.byType(SelectableText));
      final gesture = await tester.startGesture(
        Offset(textRect.right - 5, textRect.center.dy),
      );
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.moveBy(
        const Offset(0, -20),
        timeStamp: const Duration(milliseconds: 20),
      );
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.moveBy(
        const Offset(0, -20),
        timeStamp: const Duration(milliseconds: 40),
      );
      await tester.pump(const Duration(milliseconds: 20));
      expect(scroll.position.isScrollingNotifier.value, isTrue);
      expect(find.byType(UiKitView), findsNothing);
      expect(
        editable.renderEditable.selectionColor,
        editable.widget.selectionColor,
      );
      expect(updates, hasLength(before));
      await gesture.up(timeStamp: const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 16));
      expect(scroll.position.isScrollingNotifier.value, isTrue);
      expect(find.byType(UiKitView), findsNothing);
      expect(
        updates,
        hasLength(before),
        reason: 'No glyph rebuild during inertia',
      );
      await tester.pumpAndSettle();
      // The source is now behind the scroll viewport's header, though still
      // within the root overlay. Native controls must stay out of that header.
      scroll.jumpTo(110);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(SelectableText)).bottom, lessThan(100));
      expect(find.byType(UiKitView), findsNothing);
      expect(
        editable.widget.controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 5),
      );
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.byType(UiKitView), findsOneWidget);
      expect(
        editable.widget.controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 5),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('host preserves text bounds and baseline', (tester) async {
    const text = SelectableText('Native text', key: ValueKey('baselineText'));
    await tester.pumpWidget(const _HostFixture(hosted: false, child: text));
    await tester.pumpAndSettle();
    final original = tester.getRect(find.byType(EditableText));
    final originalRender = tester.renderObject<RenderBox>(
      find.byType(EditableText),
    );
    final baseline = originalRender.getDryBaseline(
      originalRender.constraints,
      TextBaseline.alphabetic,
    );
    await tester.pumpWidget(const _HostFixture(child: text));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(EditableText)), original);
    final hostedRender = tester.renderObject<RenderBox>(
      find.byType(NativeEditableSelectionHost),
    );
    expect(
      hostedRender.getDryBaseline(
        hostedRender.constraints,
        TextBaseline.alphabetic,
      ),
      baseline,
    );
    expect(find.byKey(const ValueKey('baselineText')), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
