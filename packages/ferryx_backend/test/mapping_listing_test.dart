import 'dart:typed_data';

import 'package:domain_models/domain_models.dart';
import 'package:ferryx_backend/ferryx_backend.dart' as rust;
import 'package:flutter_test/flutter_test.dart';

rust.EntryView row(String name) => rust.EntryView(
  name: name,
  path: '/f/$name',
  kind: rust.EntryKindView.file,
  isDir: false,
  isParent: false,
  mode: 0x81a4,
  uid: 501,
  gid: 20,
  owner: 'me',
  group: 'staff',
  flags: 0,
  isHidden: false,
  extension_: '',
  tags: const [],
);

rust.ListingView view(
  List<rust.EntryView> entries, {
  List<int>? order,
  int base = 0,
  int version = 1,
}) => rust.ListingView(
  location: const rust.LocationView(
    kind: rust.LocationKind.native,
    path: '/f',
  ),
  entries: entries,
  order: order == null ? null : Int32List.fromList(order),
  base: base,
  version: version,
  watched: true,
);

void main() {
  test('an update keeps the rows it names by index and makes only the '
      'rows it sends', () {
    final before = rust
        .listingFromView(view([row('a'), row('b'), row('c')]))
        .entries;
    final update = view(
      [row('b'), row('new')],
      order: [-1, 0, -2, 2],
      base: 1,
      version: 2,
    );
    final after = rust.rowsAfter(update, before);
    expect(after.map((e) => e.name), ['b', 'a', 'new', 'c']);
    expect(identical(after[1], before[0]), isTrue);
    expect(identical(after[3], before[2]), isTrue);
    expect(after[0], isNot(same(before[1])));
    final listing = rust.listingFromView(update, entries: after);
    expect(listing.entries, same(after));
    expect(listing.location, const Location.native('/f'));
  });
}
