import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_text_selection/native_text_selection.dart';

const _viewType = 'io.github.abra.native_text_selection/surface';
const _capabilities = MethodChannel(
  'io.github.abra.native_text_selection/capabilities',
);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;

  setUp(() {
    NativeSelectionPlatform.resetAvailability();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_capabilities, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
  });

  testWidgets('an unregistered host keeps the original selectable child', (
    tester,
  ) async {
    messenger.setMockMethodCallHandler(
      _capabilities,
      (_) async => throw MissingPluginException(),
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: NativeSelectionSurface(
          snapshot: _snapshot(),
          onSelectionChanged: (_) => fail('No native callbacks expected'),
          child: const Text('Hello'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hello'), findsOneWidget);
    expect(find.byType(UiKitView), findsNothing);
    expect(await NativeSelectionPlatform.isAvailable, isFalse);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('range updates reuse geometry and stale events are ignored', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    final ranges = <TextSelection?>[];
    final active = <bool>[];
    final adjusting = <bool>[];
    final actions = <String>[];
    var backgroundTaps = 0;
    var viewId = -1;
    Completer<bool>? delayedUpdate;
    messenger.setMockMethodCallHandler(_capabilities, (_) async => true);
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method == 'create') {
        viewId = (call.arguments as Map)['id'] as int;
        final channel = MethodChannel('$_viewType/$viewId');
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'update' &&
              (call.arguments as Map)['revision'] == 3 &&
              delayedUpdate != null) {
            return delayedUpdate.future;
          }
          return call.method == 'update' ? true : null;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      }
      return null;
    });

    Future<void> show(NativeSelectionSnapshot? snapshot) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: NativeSelectionSurface(
            snapshot: snapshot,
            onSelectionChanged: ranges.add,
            onAdjusting: adjusting.add,
            onActiveChanged: active.add,
            onAction: actions.add,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => backgroundTaps++,
              child: const SizedBox.expand(child: Text('Hello')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> event(String method, Map<String, Object> values) async {
      await messenger.handlePlatformMessage(
        '$_viewType/$viewId',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall(method, values),
        ),
        (_) {},
      );
      await tester.pumpAndSettle();
    }

    await show(_snapshot());
    expect(viewId, greaterThanOrEqualTo(0));
    expect(calls.where((call) => call.method == 'update'), hasLength(1));
    expect(active, isEmpty, reason: 'Accepted data does not prove native UI');
    await event('ready', {'revision': 1});
    expect(active, [true]);
    await tester.tapAt(
      tester.getBottomRight(find.byType(NativeSelectionSurface)) -
          const Offset(15, 15),
    );
    expect(backgroundTaps, 1, reason: 'Page taps pass behind native controls');
    await tester.tapAt(const Offset(11, 35));
    expect(backgroundTaps, 1, reason: 'Native handles own their gestures');

    await show(_snapshot(base: 0, extent: 4));
    expect(calls.where((call) => call.method == 'update'), hasLength(1));
    expect(calls.last.method, 'select');
    expect(calls.last.arguments, {'base': 0, 'extent': 4});

    await event('selectionChanged', {'revision': 0, 'base': 0, 'extent': 3});
    expect(ranges, isEmpty);
    await event('selectionChanged', {'revision': 1, 'base': 0, 'extent': 50});
    expect(
      ranges,
      isEmpty,
      reason: 'Reject ranges outside original UTF-16 text',
    );
    await event('adjusting', {'revision': 1, 'value': true});
    await event('selectionChanged', {'revision': 1, 'base': 0, 'extent': 3});
    await event('adjusting', {'revision': 1, 'value': false});
    expect(ranges, [const TextSelection(baseOffset: 0, extentOffset: 3)]);
    expect(adjusting, [true, false]);
    final beforeEcho = calls.length;
    await show(_snapshot(base: 0, extent: 3));
    expect(
      calls,
      hasLength(beforeEcho),
      reason: 'Native ranges are not echoed',
    );
    await event('selectionChanged', {'revision': 1, 'base': 3, 'extent': 0});
    await show(_snapshot(base: 0, extent: 3));
    expect(
      calls,
      hasLength(beforeEcho),
      reason: 'Normalizing native handle order must not reset the drag',
    );
    await event('action', {'revision': 1, 'action': 'copy'});
    expect(actions, ['copy']);

    await event('unsupportedGeometry', {'revision': 1, 'reason': 'columns'});
    expect(find.byType(UiKitView), findsNothing);
    expect(find.text('Hello'), findsOneWidget);
    expect(active, [true, false]);
    await show(_snapshot(revision: 2));
    expect(find.byType(UiKitView), findsOneWidget);
    expect(calls.where((call) => call.method == 'update'), hasLength(2));
    final staleReply = Completer<bool>();
    delayedUpdate = staleReply;
    await show(_snapshot(revision: 3));
    await show(_snapshot(revision: 4));
    staleReply.complete(false);
    await tester.pumpAndSettle();
    expect(
      find.byType(UiKitView),
      findsOneWidget,
      reason: 'A stale failure must not reject newer geometry',
    );
    await show(_snapshot(revision: 5, text: 'Hello\n', extent: 6));
    await tester.tapAt(const Offset(61, 45));
    expect(
      backgroundTaps,
      1,
      reason: 'The end handle remains interactive after an unboxed newline',
    );
    await show(null);
    expect(find.byType(UiKitView), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  test(
    'geometry preserves source offsets, direction and native menu policy',
    () {
      final message = _snapshot().toMessage();
      expect(message['text'], 'Hello');
      expect(message['showMenu'], isFalse);
      expect(message['editable'], isFalse);
      final box = (message['boxes'] as List).first as Map;
      expect(box['start'], 0);
      expect(box['end'], 1);
      expect(box['rtl'], isFalse);
      expect(box['left'], 10.0);
    },
  );
}

NativeSelectionSnapshot _snapshot({
  int revision = 1,
  int base = 0,
  int extent = 2,
  String text = 'Hello',
}) => NativeSelectionSnapshot(
  revision: revision,
  text: text,
  boxes: [
    for (var index = 0; index < 5; index++)
      NativeTextBox(
        start: index,
        end: index + 1,
        rect: Rect.fromLTWH(10 + index * 10, 20, 10, 20),
      ),
  ],
  selection: TextSelection(baseOffset: base, extentOffset: extent),
  accent: const Color(0xFF007AFF),
  selectionColor: const Color(0x44007AFF),
);
