import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:preferences_service/preferences_service.dart';

Future<SavedProfiles<int>> load(SideStorage storage) => SavedProfiles.load<int>(
  storage,
  key: 'test.profiles',
  encode: (value) => {'number': value},
  decode: (json) => json['number'] is int ? json['number']! as int : null,
);

void main() {
  test('create, rename, replace and remove survive a reload', () async {
    final storage = InMemorySideStorage();
    final catalog = await load(storage);
    await catalog.save(' Documents ', 1);
    expect(catalog.contains('DOCUMENTS'), isTrue);
    await expectLater(catalog.save('documents', 2), throwsStateError);
    await catalog.rename('Documents', 'Reading');
    await catalog.save('Reading', 3, replace: true);
    final restored = await load(storage);
    expect(restored.items.single.name, 'Reading');
    expect(restored.items.single.value, 3);
    await restored.remove('Reading');
    final empty = await load(storage);
    expect(empty.items, isEmpty);
    catalog.dispose();
    restored.dispose();
    empty.dispose();
  });

  test(
    'parallel writes serialize without losing newly created records',
    () async {
      final storage = InMemorySideStorage();
      final catalog = await load(storage);
      await Future.wait([catalog.save('one', 1), catalog.save('two', 2)]);
      final restored = await load(storage);
      expect(restored.items.map((item) => item.value), [1, 2]);
      catalog.dispose();
      restored.dispose();
    },
  );

  test('failed persistence leaves the published collection unchanged and '
      'does not poison later writes', () async {
    final storage = _FailingStorage();
    final catalog = await load(storage);
    await expectLater(catalog.save('one', 1), throwsA(isA<Exception>()));
    expect(catalog.items, isEmpty);
    storage.fail = false;
    await catalog.save('two', 2);
    expect(catalog.items.single.name, 'two');
    catalog.dispose();
  });

  test(
    'invalid records, duplicate names and unknown versions are ignored',
    () async {
      final storage = InMemorySideStorage({
        'test.profiles': jsonEncode({
          'version': 1,
          'items': [
            {
              'name': '',
              'value': {'number': 0},
            },
            {
              'name': 'one',
              'value': {'number': 1},
            },
            {
              'name': 'ONE',
              'value': {'number': 2},
            },
            {
              'name': 'bad',
              'value': {'number': 'text'},
            },
            {
              'name': 'bad\nname',
              'value': {'number': 3},
            },
          ],
        }),
      });
      final catalog = await load(storage);
      expect(catalog.items.single.value, 1);
      catalog.dispose();
      for (final value in ['{', '{"version":2,"items":[]}', '[]']) {
        storage.values['test.profiles'] = value;
        final restored = await load(storage);
        expect(restored.items, isEmpty);
        restored.dispose();
      }
    },
  );

  test('invalid names and collection limits never reach storage', () async {
    final storage = InMemorySideStorage();
    final catalog = await load(storage);
    for (final name in ['', ' ', 'a\nb', 'x' * 81]) {
      await expectLater(catalog.save(name, 1), throwsArgumentError);
    }
    expect(storage.writes, 0);
    for (var i = 0; i < SavedProfiles.maxItems; i++) {
      await catalog.save('item $i', i);
    }
    await expectLater(catalog.save('overflow', 1), throwsStateError);
    expect(catalog.items.length, SavedProfiles.maxItems);
    catalog.dispose();
  });
}

class _FailingStorage extends InMemorySideStorage {
  bool fail = true;
  @override
  Future<void> write(String key, String value) async {
    if (fail) throw Exception('storage unavailable');
    await super.write(key, value);
  }
}
