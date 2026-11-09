import 'package:pdfium_dart/pdfium_dart.dart';
import 'package:test/test.dart';

PDFium? _pdfium;

void main() {
  setUp(() {
    _pdfium = getPdfium();
  });

  test('PDFium Initialization', () {
    _pdfium!.FPDF_InitLibrary();
    _pdfium!.FPDF_DestroyLibrary();
  });

  test('reports explicit module path load errors', () {
    expect(
      () => getPdfium(modulePath: 'missing_pdfium_for_test'),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          allOf(
            contains('Failed to load explicit PDFium module path'),
            contains('missing_pdfium_for_test'),
          ),
        ),
      ),
    );
  });
}
