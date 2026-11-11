import 'package:component_library/component_library.dart';
import 'package:domain_models/domain_models.dart';
import 'package:ferryx_localizations/ferryx_localizations.dart';
import 'package:flutter/material.dart';
import 'package:preferences_service/preferences_service.dart';

Future<SavedProfile<FindRequest>?> showSavedSearchesDialog(
  BuildContext context, {
  required SavedProfiles<FindRequest> catalog,
  FindRequest? current,
}) async {
  final l10n = context.l10n;
  final name = await showAppDialog<String>(
    context,
    (_) => ListenableBuilder(
      listenable: catalog,
      builder: (context, _) => AppNamedItemsDialog(
        items: [
          for (final item in catalog.items)
            AppNamedItem(item.name, detail: item.value.root),
        ],
        labels: AppNamedItemsLabels(
          title: l10n.savedSearchesTitle,
          name: l10n.savedProfileName,
          empty: l10n.savedSearchesEmpty,
          create: l10n.searchSaveCurrent,
          update: l10n.searchUpdateCurrent,
          rename: l10n.actionRename,
          remove: l10n.actionRemove,
          open: l10n.actionOpen,
          close: l10n.actionClose,
          failure: l10n.savedProfileFailure,
        ),
        validateName: (name, replacing) {
          if (!SavedProfiles.validName(name)) {
            return l10n.savedProfileInvalidName;
          }
          if (catalog.contains(name) &&
              name.toLowerCase() != replacing?.toLowerCase()) {
            return l10n.savedProfileExists;
          }
          if (replacing == null &&
              catalog.items.length >= SavedProfiles.maxItems) {
            return l10n.savedProfileLimit;
          }
          return null;
        },
        onCreate: current == null
            ? null
            : (name) => catalog.save(name, current),
        onUpdate: current == null
            ? null
            : (name) => catalog.save(name, current, replace: true),
        onRename: catalog.rename,
        onRemove: catalog.remove,
      ),
    ),
  );
  return name == null
      ? null
      : catalog.items.where((item) => item.name == name).firstOrNull;
}
