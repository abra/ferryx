/// A file that cannot be read as the format it claims to be.
///
/// Repositories map it to the domain's exceptions; the message is for logs,
/// not for the screen.
class PagecraftException implements Exception {
  const PagecraftException(this.message);

  final String message;

  @override
  String toString() => 'PagecraftException: $message';
}
