import 'package:pdfrx/pdfrx.dart';

/// Loads pdfium for the app ahead of the first `PdfBook.open`.
///
/// Opening a book loads the engine itself when needed; an
/// app that wants that cost at startup rather than on the first PDF calls
/// this once. On iOS and macOS the library is the XCFramework
/// `pdfium_flutter` links into the app; on Android it is the native asset
/// the same package bundles. Safe to call again. Tests use
/// `preparePdfEngineForTests()` from `package:pagecraft/testing.dart` instead.
Future<void> initializePdfEngine() => pdfrxFlutterInitialize();
