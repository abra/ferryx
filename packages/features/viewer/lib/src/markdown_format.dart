/// Whole-document rendering is bounded; larger files keep Text/Hex available.
const maxMarkdownPreviewBytes = 512 * 1024;

bool isMarkdownName(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0) return false;
  final extension = name.substring(dot + 1).toLowerCase();
  return const {'md', 'markdown', 'mdown', 'mkd', 'mkdn'}.contains(extension);
}
