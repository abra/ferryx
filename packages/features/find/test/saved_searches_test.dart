import 'dart:async';

import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:find_feature/find_feature.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operations_service/operations_service.dart';
import 'package:preferences_service/preferences_service.dart';

class _Find extends Mock implements FindService {}

void main() {
  final en = lookupFerryxLocalizations(const Locale('en'));
  const request = FindRequest(
    root: '/home/reports',
    name: r'.*\.txt',
    nameIsRegex: true,
    content: ContentQuery(
      text: 'invoice',
      caseSensitive: true,
      wholePhrase: false,
    ),
    size: SizeCondition(op: SizeOp.greater, bytes: 1537),
    includeHidden: true,
    includeFolders: false,
    useSpotlight: true,
    modifiedWithinDays: 7,
  );
  setUpAll(() => registerFallbackValue(request));
  testWidgets('loaded query retains exact options when sent to a panel tab', (
    tester,
  ) async {
    final service = _Find();
    when(() => service.updates).thenAnswer((_) => const Stream.empty());
    when(() => service.cancel(any())).thenAnswer((_) async {});
    FindRequest? opened;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPlatformStyle.macos),
        localizationsDelegates: FerryxSupportedLocales.delegates,
        supportedLocales: FerryxSupportedLocales.locales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showFindDialog(
              context,
              root: '/other',
              find: service,
              spotlight: true,
              initial: request,
              onView: (_) async {},
              onResults: (query) async => opened = query,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.searchOpenTab));
    await tester.pumpAndSettle();
    expect(opened, request);
    expect(tester.takeException(), isNull);
  });
  testWidgets('saved query manager creates, renames and removes entries', (
    tester,
  ) async {
    final catalog = await SavedProfiles.load<FindRequest>(
      InMemorySideStorage(),
      key: 'test',
      encode: (q) => q.toJson(),
      decode: FindRequest.fromJson,
    );
    addTearDown(catalog.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(AppPlatformStyle.macos),
        localizationsDelegates: FerryxSupportedLocales.delegates,
        supportedLocales: FerryxSupportedLocales.locales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showSavedSearchesDialog(
              context,
              catalog: catalog,
              current: request,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(AppTextField), 'Reports');
    await tester.tap(find.text(en.searchSaveCurrent));
    await tester.pumpAndSettle();
    expect(catalog.items.single.value, request);
    await tester.tap(
      find.descendant(
        of: find.byType(AppRowList),
        matching: find.text('Reports'),
      ),
    );
    await tester.pump();
    await tester.enterText(find.byType(AppTextField), 'Invoices');
    await tester.tap(find.text(en.actionRename));
    await tester.pumpAndSettle();
    expect(catalog.items.single.name, 'Invoices');
    await tester.tap(find.text(en.actionRemove));
    await tester.pumpAndSettle();
    expect(catalog.items, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text(en.actionClose));
    await tester.pumpAndSettle();
  });
}
