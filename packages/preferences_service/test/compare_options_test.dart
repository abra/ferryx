import 'package:flutter_test/flutter_test.dart';
import 'package:preferences_service/preferences_service.dart';

void main() {
  test('compare options round-trip through the preferences', () {
    const options = CompareOptions(
      quickContents: true,
      recursive: false,
      byContent: true,
      fatTime: true,
      includeHidden: true,
      direction: SyncDirection.rightToLeft,
      deleteMissing: true,
      showLeftOnly: false,
      showIdentical: true,
    );
    final prefs = const Preferences().copyWith(compareOptions: options);
    final back = Preferences.fromJson(prefs.toJson());
    expect(back.compareOptions, options);
    expect(back, prefs);
  });

  test('missing or damaged options fall back field by field', () {
    expect(CompareOptions.fromJson(null), const CompareOptions());
    expect(CompareOptions.fromJson('nonsense'), const CompareOptions());
    final partial = CompareOptions.fromJson({
      'recursive': false,
      'direction': 'sideways',
      'showNewer': 3,
    });
    expect(partial.recursive, isFalse);
    expect(partial.direction, SyncDirection.bothWays);
    expect(partial.showNewer, isTrue);
    // A file written before the options existed reads the defaults.
    expect(
      Preferences.fromJson(const {'version': 1}).compareOptions,
      const CompareOptions(),
    );
  });
}
