import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/widgets.dart';

import '../panel/file_icon.dart';

/// What hangs under the pointer while rows are dragged: the icon of the
/// row taken, with a count badge when there are several, as Finder's.
/// Painted off screen into the drag's picture.
class FileDragImage extends StatelessWidget {
  const FileDragImage({required this.entry, required this.count, super.key});

  /// The picture's size: the icon in the middle, with room on its right
  /// for the badge over its corner (a count of five figures fits).
  static const size = Size(_width, AppIconSize.xl + 2 * AppSpacing.sm);
  static const _width = AppIconSize.xl * 4;

  /// Where the badge starts: half its height left of the icon's edge.
  static const _badgeLeft = (_width + AppIconSize.xl) / 2 - AppIconSize.md / 2;

  final FileEntry entry;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final (icon, tint) = FileIcon.describe(entry, colors);
    return SizedBox.fromSize(
      size: size,
      child: Stack(
        children: [
          Center(
            child: Icon(icon, size: AppIconSize.xl, color: tint),
          ),
          if (count > 1)
            Positioned(
              top: 0,
              left: _badgeLeft,
              right: 0,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: _CountBadge(count: count),
              ),
            ),
        ],
      ),
    );
  }
}

/// The number of items dragged, white on red as macOS draws it.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // As wide as the count (a circle for one figure), its text centred.
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: AppIconSize.md,
        minHeight: AppIconSize.md,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.danger,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Align(
            widthFactor: 1,
            heightFactor: 1,
            child: Text(
              context.l10n.count(count),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
              style: context.text.labelSmall!
                  .copyWith(
                    color: colors.onAccent,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )
                  .weight(FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }
}
