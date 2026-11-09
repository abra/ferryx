import 'package:domain_models/domain_models.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

@immutable
class ArchiverPreferences extends Equatable {
  const ArchiverPreferences({
    this.manual = const [],
    this.disabled = const [],
    this.format = ArchiveType.zip,
    this.compressTool = '',
    this.extractTool = '',
    this.options = const {},
  });
  final List<ArchiveTool> manual;
  final List<String> disabled;
  final ArchiveType format;
  final String compressTool;
  final String extractTool;
  final Map<String, ArchiverOptions> options;
  ArchiverOptions optionsFor(String id) =>
      options[id] ?? const ArchiverOptions();

  ArchiverPreferences copyWith({
    List<ArchiveTool>? manual,
    List<String>? disabled,
    ArchiveType? format,
    String? compressTool,
    String? extractTool,
    Map<String, ArchiverOptions>? options,
  }) => ArchiverPreferences(
    manual: manual ?? this.manual,
    disabled: disabled ?? this.disabled,
    format: format ?? this.format,
    compressTool: compressTool ?? this.compressTool,
    extractTool: extractTool ?? this.extractTool,
    options: options ?? this.options,
  );

  Map<String, Object?> toJson() => {
    'manual': [for (final tool in manual) tool.toJson()],
    'disabled': disabled,
    'format': format.name,
    'compressTool': compressTool,
    'extractTool': extractTool,
    'options': options.map((id, value) => MapEntry(id, value.toJson())),
  };
  factory ArchiverPreferences.fromJson(Object? json) {
    if (json is! Map<String, Object?>) return const ArchiverPreferences();
    final manual = <ArchiveTool>[];
    if (json['manual'] case final List items) {
      for (final item in items) {
        if (item is Map<String, Object?>) {
          final tool = ArchiveTool.fromJson(item);
          if (tool != null && !manual.any((t) => t.id == tool.id)) {
            manual.add(tool);
          }
        }
      }
    }
    return ArchiverPreferences(
      manual: List.unmodifiable(manual),
      disabled: json['disabled'] is List
          ? (json['disabled'] as List).whereType<String>().toList()
          : const [],
      format: json['format'] is String
          ? ArchiveType.parse(json['format'] as String) ?? ArchiveType.zip
          : ArchiveType.zip,
      compressTool: json['compressTool'] is String
          ? json['compressTool'] as String
          : '',
      extractTool: json['extractTool'] is String
          ? json['extractTool'] as String
          : '',
      options: json['options'] is Map<String, Object?>
          ? Map.unmodifiable(
              (json['options'] as Map<String, Object?>).map(
                (id, value) => MapEntry(id, ArchiverOptions.fromJson(value)),
              ),
            )
          : const {},
    );
  }
  @override
  List<Object?> get props => [
    manual,
    disabled,
    format,
    compressTool,
    extractTool,
    options,
  ];
}
