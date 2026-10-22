import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

/// An editor F4 opens files with, picked by the file's extension.
@immutable
class ExternalEditor extends Equatable {
  const ExternalEditor({
    required this.name,
    required this.path,
    this.mask = '*',
    this.inTerminal = false,
    this.arguments = '%p',
  });

  final String name;

  /// An application bundle, or an executable for [inTerminal].
  final String path;

  /// The file masks the editor takes (`*.md;*.txt`); `*` for everything.
  final String mask;
  final bool inTerminal;

  /// Placeholders as the tools take them (`%p` the file's path).
  final String arguments;

  Map<String, Object?> toJson() => {
    'name': name,
    'path': path,
    'mask': mask,
    'inTerminal': inTerminal,
    'arguments': arguments,
  };

  static ExternalEditor? fromJson(Map<String, Object?> json) {
    final name = json['name'];
    final path = json['path'];
    if (name is! String || path is! String) return null;
    return ExternalEditor(
      name: name,
      path: path,
      mask: json['mask'] is String ? json['mask']! as String : '*',
      inTerminal: json['inTerminal'] == true,
      arguments: json['arguments'] is String
          ? json['arguments']! as String
          : '%p',
    );
  }

  @override
  List<Object?> get props => [name, path, mask, inTerminal, arguments];
}

/// A program the user runs on the panels' items from the Tools menu.
@immutable
class ExternalTool extends Equatable {
  const ExternalTool({
    required this.title,
    required this.path,
    this.parameters = '',
    this.inTerminal = false,
    this.shortcut,
  });

  final String title;
  final String path;

  /// Placeholders: `%p` the focused item's path, `%f` its name, `%n` the
  /// name without extension, `%e` the extension, `%r` the panel's path,
  /// `%P` / `%F` the selected paths / names, `%-…` the same of the
  /// opposite panel, `%?` a value asked for, `%%` a percent sign.
  final String parameters;
  final bool inTerminal;

  /// An encoded chord (see `ChordCodec`), or none.
  final String? shortcut;

  Map<String, Object?> toJson() => {
    'title': title,
    'path': path,
    'parameters': parameters,
    'inTerminal': inTerminal,
    if (shortcut != null) 'shortcut': shortcut,
  };

  static ExternalTool? fromJson(Map<String, Object?> json) {
    final title = json['title'];
    final path = json['path'];
    if (title is! String || path is! String) return null;
    return ExternalTool(
      title: title,
      path: path,
      parameters: json['parameters'] is String
          ? json['parameters']! as String
          : '',
      inTerminal: json['inTerminal'] == true,
      shortcut: json['shortcut'] is String ? json['shortcut']! as String : null,
    );
  }

  @override
  List<Object?> get props => [title, path, parameters, inTerminal, shortcut];
}
