import 'package:component_library/component_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ScrollController scroll;
  late AppScrollReveal follow;
  var built = 0;
  setUp(() {
    scroll = ScrollController();
    follow = AppScrollReveal(scroll);
    built = 0;
  });
  tearDown(() {
    follow.dispose();
    scroll.dispose();
  });

  Future<void> mount(WidgetTester tester, {Axis axis = Axis.vertical}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 200,
              height: 200,
              child: NotificationListener<UserScrollNotification>(
                onNotification: follow.onUserScroll,
                child: ListView.builder(
                  controller: scroll,
                  scrollDirection: axis,
                  padding: EdgeInsets.zero,
                  itemExtent: 20,
                  itemCount: 10000,
                  scrollCacheExtent: const ScrollCacheExtent.pixels(0),
                  itemBuilder: (_, index) {
                    built++;
                    return Text('$index');
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final axis in Axis.values) {
    testWidgets(
      '${axis.name}: a nearby range moves through intermediate frames; visible items stay put',
      (tester) async {
        await mount(tester, axis: axis);
        follow.reveal(start: 200, end: 220);
        expect(scroll.offset, 0);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        expect(scroll.offset, inExclusiveRange(0, 20));
        await tester.pumpAndSettle();
        expect(scroll.offset, 20);
        follow.reveal(start: 100, end: 120);
        await tester.pumpAndSettle();
        expect(scroll.offset, 20);
      },
    );
  }

  testWidgets(
    'retargeting and reversing finish at the latest target without an old completion taking over',
    (tester) async {
      await mount(tester);
      follow.reveal(start: 300, end: 320);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final first = scroll.offset;
      follow.reveal(start: 380, end: 400);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(scroll.offset, greaterThan(first));
      follow.reveal(start: 100, end: 120);
      await tester.pumpAndSettle();
      expect(scroll.offset, 100);
      expect(follow.isAnimating, isFalse);
      await tester.pump(const Duration(seconds: 1));
      expect(scroll.offset, 100);
    },
  );

  testWidgets('a reversed cursor already in view cancels the old movement', (
    tester,
  ) async {
    await mount(tester);
    follow.reveal(start: 300, end: 320);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final current = scroll.offset;
    follow.reveal(start: current + 20, end: current + 40);
    await tester.pumpAndSettle();
    expect(scroll.offset, current);
    expect(follow.isAnimating, isFalse);
  });

  testWidgets(
    'repeated reveals of the same range do not restart the animation',
    (tester) async {
      await mount(tester);
      follow.reveal(start: 300, end: 320);
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 40));
        follow.reveal(start: 300, end: 320);
      }
      expect(scroll.offset, 120);
      await tester.pumpAndSettle();
      expect(follow.isAnimating, isFalse);
    },
  );

  testWidgets(
    'a distant jump skips intermediate items and Reduce Motion finishes a nearby movement immediately',
    (tester) async {
      await mount(tester);
      final before = built;
      follow.reveal(start: 190000, end: 190020);
      expect(scroll.offset, 189820);
      await tester.pumpAndSettle();
      expect(built - before, lessThan(25));
      expect(follow.isAnimating, isFalse);
      scroll.jumpTo(0);
      follow.reveal(start: 300, end: 320);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(scroll.offset, inExclusiveRange(0, 120));
      follow.reveal(start: 300, end: 320, reduceMotion: true);
      expect(scroll.offset, 120);
      await tester.pumpAndSettle();
      expect(scroll.offset, 120);
    },
  );

  testWidgets(
    'alignment clamps to the extents and oversized ranges settle on their start',
    (tester) async {
      await mount(tester);
      for (final (alignment, expected) in [
        (0.0, 300.0),
        (0.5, 210.0),
        (1.0, 120.0),
      ]) {
        follow.reveal(
          start: 300,
          end: 320,
          alignment: alignment,
          immediate: true,
        );
        expect(scroll.offset, expected);
      }
      follow.reveal(start: -20, end: 0, alignment: 0, immediate: true);
      expect(scroll.offset, 0);
      follow.reveal(start: 20, end: 600, reduceMotion: true);
      expect(scroll.offset, 20);
      follow.reveal(start: 20, end: 600);
      expect(scroll.offset, 20);
      follow.reveal(start: 999999, end: 1000000, immediate: true);
      expect(scroll.offset, scroll.position.maxScrollExtent);
    },
  );

  testWidgets(
    'requests coalesce after layout and disposed views drop pending callbacks',
    (tester) async {
      await mount(tester);
      var calls = 0;
      follow.schedule(() {
        calls++;
        follow.reveal(start: 300, end: 320);
      });
      follow.schedule(() {
        calls++;
        follow.reveal(start: 380, end: 400);
      });
      await tester.pump();
      expect(calls, 1);
      await tester.pumpAndSettle();
      expect(scroll.offset, 200);
      follow.schedule(() => calls++);
      follow.dispose();
      await tester.pump();
      expect(calls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'native pointer scrolling cancels a running and a queued keyboard reveal',
    (tester) async {
      await mount(tester);
      follow.reveal(start: 300, end: 320);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      follow.schedule(() => follow.reveal(start: 1800, end: 1820));
      scroll.position.pointerScroll(20);
      final current = scroll.offset;
      await tester.pumpAndSettle();
      expect(scroll.offset, current);
      expect(follow.isAnimating, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
