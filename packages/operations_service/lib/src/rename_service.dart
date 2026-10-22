import 'package:domain_models/domain_models.dart';
import 'package:ferryx_backend/ferryx_backend.dart' as rust;

/// Batch rename: the preview the dialog shows and its application.
class RenameService {
  const RenameService();

  /// The new name of each path under [options], with any problem; an
  /// invalid search expression throws [FerryxException] with
  /// [FerryxErrorKind.invalidPattern].
  Future<List<RenameOutcome>> preview(
    List<String> paths,
    RenameOptions options,
  ) => rust.FerryxBackend.guard(() async {
    final outcomes = await rust.batchRenamePreview(
      items: [for (final path in paths) rust.RenameItemView(path: path)],
      options: rust.renameOptionsToView(options),
    );
    return outcomes.map(rust.renameOutcomeFromView).toList(growable: false);
  });

  /// Renames every outcome that changes its name; answers what failed.
  Future<List<RenameFailure>> apply(List<RenameOutcome> outcomes) =>
      rust.FerryxBackend.guard(() async {
        final failures = await rust.batchRenameApply(
          pairs: [
            for (final o in outcomes)
              if (o.changes && o.problem == null)
                rust.RenamePairView(path: o.path, newName: o.newName),
          ],
        );
        return failures.map(rust.renameFailureFromView).toList(growable: false);
      });
}
