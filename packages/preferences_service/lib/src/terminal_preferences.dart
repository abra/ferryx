import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

/// The integrated terminal's settings and its place in the window.
@immutable
class TerminalPreferences extends Equatable {
  const TerminalPreferences({
    this.shell = '',
    this.fontSize = 12,
    this.scrollback = 10000,
    this.lines = defaultLines,
    this.shown = false,
  });

  static const defaultLines = 12;
  static const minFontSize = 9.0;
  static const maxFontSize = 24.0;
  static const minScrollback = 1000;
  static const maxScrollback = 100000;
  static const minLines = 2;
  static const maxLines = 200;

  /// The shell to run: a path or a name on `PATH`; empty for the user's
  /// login shell.
  final String shell;
  final double fontSize;

  /// Lines kept above the screen to scroll back to.
  final int scrollback;

  /// The terminal's height under the panels, in lines.
  final int lines;

  /// The terminal was shown under the panels when the window closed.
  final bool shown;

  TerminalPreferences copyWith({
    String? shell,
    double? fontSize,
    int? scrollback,
    int? lines,
    bool? shown,
  }) => TerminalPreferences(
    shell: shell ?? this.shell,
    fontSize: fontSize ?? this.fontSize,
    scrollback: scrollback ?? this.scrollback,
    lines: lines ?? this.lines,
    shown: shown ?? this.shown,
  );

  Map<String, Object?> toJson() => {
    'shell': shell,
    'fontSize': fontSize,
    'scrollback': scrollback,
    'lines': lines,
    'shown': shown,
  };

  /// Tolerant: what is missing or malformed takes its default, numbers are
  /// kept in range.
  factory TerminalPreferences.fromJson(Object? json) {
    const defaults = TerminalPreferences();
    if (json is! Map<String, Object?>) return defaults;
    num numberOr(Object? value, num fallback) =>
        value is num && value.isFinite ? value : fallback;
    return TerminalPreferences(
      shell: json['shell'] is String
          ? (json['shell']! as String).trim()
          : defaults.shell,
      fontSize: numberOr(
        json['fontSize'],
        defaults.fontSize,
      ).toDouble().clamp(minFontSize, maxFontSize),
      scrollback: numberOr(
        json['scrollback'],
        defaults.scrollback,
      ).round().clamp(minScrollback, maxScrollback),
      lines: numberOr(
        json['lines'],
        defaults.lines,
      ).round().clamp(minLines, maxLines),
      shown: json['shown'] is bool ? json['shown']! as bool : defaults.shown,
    );
  }

  @override
  List<Object?> get props => [shell, fontSize, scrollback, lines, shown];
}
