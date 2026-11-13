import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:panels_feature/panels_feature.dart';

import 'support/workspace_harness.dart';

void main() {
  setUpAll(WorkspaceHarness.registerFallbacks);
  late WorkspaceHarness h;
  final en = lookupFerryxLocalizations(const Locale('en'));

  setUp(() async {
    h = WorkspaceHarness();
    await h.setUp();
    h.addFolder('/home/first');
    h.addFolder('/home/second');
    await h.preferences.update((p) => p.copyWith(showTabBarAlways: true));
  });
  tearDown(() => h.tearDown());

  Finder tabLabel(String name) => find.descendant(
    of: find.byType(AppTabStrip).first,
    matching: find.text(name),
  );

  Future<PanelCubit> threeTabs(WidgetTester tester) async {
    await h.pump(tester);
    final cubit = tester
        .element(find.byType(PanelView).first)
        .read<PanelCubit>();
    await cubit.newTab(location: const Location.native('/home/first'));
    await cubit.newTab(location: const Location.native('/home/second'));
    await tester.pumpAndSettle();
    return cubit;
  }

  Future<void> menu(WidgetTester tester, String name) async {
    await tester.tap(
      tabLabel(name),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('cancel preserves active tab; close targets the clicked tab '
      'even after a reorder, and reopen restores its location', (tester) async {
    final cubit = await threeTabs(tester);
    final targetId = cubit.state.tabs[1].id;
    final activeId = cubit.state.active!.id;
    await menu(tester, 'first');
    await h.press(tester, LogicalKeyboardKey.escape);
    expect(cubit.state.active!.id, activeId);
    expect(cubit.state.tabs, hasLength(3));

    await menu(tester, 'first');
    cubit.moveTab(1, 0);
    await tester.pump();
    await tester.tap(find.text(en.cmdCloseTab));
    await tester.pumpAndSettle();
    expect(cubit.state.tabs.map((t) => t.id), isNot(contains(targetId)));
    expect(cubit.state.tabs, hasLength(2));
    expect(cubit.state.active!.id, activeId);
    expect(cubit.state.closedTabs, [const Location.native('/home/first')]);

    await menu(tester, 'second');
    await tester.tap(find.text(en.cmdReopenClosedTab));
    await tester.pumpAndSettle();
    expect(cubit.state.active!.location, const Location.native('/home/first'));
    expect(cubit.state.tabs, hasLength(3));
    expect(cubit.state.closedTabs, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('close others keeps the clicked inactive tab', (tester) async {
    final cubit = await threeTabs(tester);
    final targetId = cubit.state.tabs[1].id;
    await menu(tester, 'first');
    await tester.tap(find.text(en.cmdCloseOtherTabs));
    await tester.pumpAndSettle();
    expect(cubit.state.tabs.map((t) => t.id), [targetId]);
    expect(cubit.state.active!.location, const Location.native('/home/first'));
    expect(
      cubit.state.closedTabs,
      containsAll([
        const Location.native('/home/docs'),
        const Location.native('/home/second'),
      ]),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the menu key targets the focused inactive tab; '
      'a vanished target cannot close other tabs', (tester) async {
    final cubit = await threeTabs(tester);
    final activeId = cubit.state.active!.id;
    Focus.of(tester.element(tabLabel('first'))).requestFocus();
    await tester.pump();
    await h.press(tester, LogicalKeyboardKey.enter, control: true);
    await tester.tap(find.text(en.cmdCloseTab));
    await tester.pumpAndSettle();
    expect(cubit.state.tabs.map((t) => t.location), [
      const Location.native('/home/docs'),
      const Location.native('/home/second'),
    ]);
    expect(cubit.state.active!.id, activeId);

    await cubit.newTab(location: const Location.native('/home/first'));
    await tester.pumpAndSettle();
    await menu(tester, 'docs');
    await cubit.closeTab(0);
    await tester.pump();
    final remaining = cubit.state.tabs.map((t) => t.id).toList();
    expect(remaining, hasLength(2));
    await tester.tap(find.text(en.cmdCloseOtherTabs));
    await tester.pumpAndSettle();
    expect(cubit.state.tabs.map((t) => t.id), remaining);
    expect(tester.takeException(), isNull);
  });
}
