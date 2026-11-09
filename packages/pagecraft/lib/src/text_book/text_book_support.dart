/// Content the text renderer cannot lay out. The host handles the error;
/// Pagecraft does not select an alternate renderer.
library;

import '../pagecraft_exception.dart';

/// Why the text renderer cannot lay out a book or section.
enum TextBookUnsupported {
  /// Pages of a fixed size (`rendition:layout` `pre-paginated`, KF8's
  /// fixed layout), which require a format-specific fixed-layout renderer.
  fixedLayout,

  /// Vertical lines (`writing-mode: vertical-rl` on the body): pagecraft
  /// lays out horizontal lines only.
  verticalWriting,
}

/// Raised by `TextPagesController` (as its `error`) when the book, or a
/// section turned to, needs what pagecraft does not lay out.
class UnsupportedTextBookException extends PagecraftException {
  const UnsupportedTextBookException(this.reason)
    : super('Not laid out by pagecraft');

  final TextBookUnsupported reason;

  @override
  String toString() => 'UnsupportedTextBookException: ${reason.name}';
}
