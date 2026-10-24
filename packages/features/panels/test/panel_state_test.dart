import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panels_feature/panels_feature.dart';

void main() {
  PanelTabState tab(Set<String> selected) => PanelTabState(
    id: 't',
    location: const Location.native('/home'),
    sort: const SortOptions(),
    selected: selected,
  );

  test('two tabs with the same big selection in sets of their own compare '
      'equal in linear time, as every emit compares them', () {
    final names = [for (var i = 0; i < 50000; i++) 'file $i.txt'];
    final a = tab(names.toSet());
    final b = tab(names.reversed.toSet());
    final clock = Stopwatch()..start();
    expect(a, b);
    // Pairwise, as Equatable compares sets, this takes minutes.
    expect(clock.elapsed, lessThan(const Duration(seconds: 2)));
    expect(a, isNot(tab({...names.skip(1), 'other.txt'})));
    expect(a.hashCode, b.hashCode);
  });
}
