# Native text selection

Platform selection controls over text laid out by Flutter. The package has no
document parser, repository, domain model or state-management dependency.
Pagecraft supplies exact UTF-16 ranges and visual cells; ordinary read-only
`SelectableText` uses `NativeEditableSelectionHost`.

This local package was copied with Pagecraft from Readflex commit
`99bedcfdd246d8570f89744034f098dec7312063` on 2026-11-09. Pagecraft resolves
it through `path: ../native_text_selection`; its sources and MIT license
are part of Ferryx's repository.

## Boundary

- Dart owns the text, document anchors, layout and initial long-press selection.
- iOS uses `UITextInput` geometry, system handle/highlight views from
  `UITextSelectionDisplayInteraction` and the system `UITextLoupeSession`.
  Native pan gestures update the fixed UTF-16 range through the supplied cells;
  no handles or magnifier are drawn by the adapter. These APIs require iOS 17
  or later; older supported iOS releases retain Flutter selection.
- Android uses a real selectable `TextView` and its system `Editor`. Invisible
  replacement spans reproduce supplied cells without replacing Flutter's
  text layout. Its native layout is validated before activating the controls.
  The active view uses Hybrid Composition (`initExpensiveAndroidView`): texture
  composition makes the system magnifier sample the wrong surface. The native
  magnifier sees the original Flutter pixels; no page bitmap is copied.
- The application's action menu remains in Flutter. Production hosts pass
  `showMenu: false`; system menus are suppressed independently of handles.

The platform view exists only while a range is selected. Only touches near
selection endpoints are claimed by its gesture recognizer. Other taps and
drags continue to the existing page-turn, table and scrolling controls.

Read-only text hosts suspend native controls during ancestor scrolling and
refresh cached geometry after it settles. Offscreen endpoints retain Flutter
selection until the selected text is visible again.

## Protocol and lifetime

`NativeSelectionSnapshot` contains visible text, visual cells, physical page
regions, colours and a geometry revision. Cell offsets refer to the exact
supplied UTF-16 text. A cell normally represents a grapheme; a scan's hidden
text may only provide whole-word cells. No character coordinates are invented
for those scans.

`NativeSelectionSurface` registers a per-view method channel. A new geometry
revision sends `update`; subsequent boundary changes send `select` with two
offsets. Native callbacks carry the revision, so obsolete pages cannot update
the current document. Native `ready` means the platform has activated selection
display; accepting an `update` alone does not suppress Flutter controls.

Removing the range disposes the platform view, gesture observers and native
selection state. A rejected geometry retains the existing Flutter controls and
can be retried for a different range or revision.

## Supported limits

Android's public selection APIs assume a conventional text layout. A range
crossing separate side-by-side page regions, overlapping cells or geometry that
the native layout cannot reproduce uses Flutter selection. Exact mapping is
preferred over displaying misplaced system handles. Mixed-direction text and
source-provided word cells require the same validation.

Vertically overlapping font cells use spacing-aware native caret metrics on
Android 14+. Older Android releases retain Flutter controls for that geometry.
Physical view coordinates stay LTR; each cell supplies its own writing
direction, independently of application locale.

Editable `TextField`s keep their existing Flutter selection, native keyboard
and IME connection. The read-only host deliberately refuses editable and
obscured fields; an editing bridge must also preserve composing text, Cut/Paste
and keyboard configuration. Android's system selection additionally requires
native focus, which cannot simply replace an active Flutter input connection.

The adapter does not create OCR text for comics or image-only scans.

## Checks

Run Dart protocol, host and fallback tests with `fvm flutter test` in this
directory. Pagecraft tests verify range-to-document mapping separately.
Android geometry tests run from the app's `android/` directory:

```sh
./gradlew :native_text_selection:testDebugUnitTest
```

Use a Gradle-supported JDK (the project uses Java 21). iOS XCTest sources live
under `ios/native_text_selection/Tests/`. Both CocoaPods and Swift Package
Manager are supported. Generate the small UIKit gesture-test host under an
ignored directory from the repository root:

```sh
ruby packages/native_text_selection/test_support/ios/create_project.rb \
  .local/native-selection-ios
xcodebuild test \
  -project .local/native-selection-ios/NativeSelectionHarness.xcodeproj \
  -scheme NativeSelectionHarness -destination 'id=<simulator-id>' \
  -derivedDataPath .local/native-selection-ios/build
```

The generator uses the CocoaPods `xcodeproj` Ruby gem. Native tests exercise
system handles, gesture callbacks, menu suppression and highlight preview.
`integration_test/native_selection_controls_test.dart` checks the real plugin
inside Reader with an original Cyrillic PDF fixture and exact source anchors.
Run it with `make test-native-selection DEVICE=<device-id>` from the repository
root on iOS 17+ or Android.
Mocked Dart channels do not prove system handle gestures,
the native magnifier, menu suppression or accessibility on a device.
