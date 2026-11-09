import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

/// Where the integrated terminal is in the window, as in Nimble Commander.
enum TerminalPlace {
  hidden,

  /// Under the panels.
  overlapped,

  /// In the panels' place; they come back over it.
  panelsHidden,

  /// Over the whole window.
  fullWindow,

  /// A tab beside the file tabs of the hosting panel.
  panelTab,
}

/// The terminal can share the window width or belong to one file panel.
enum TerminalHost { window, left, right }

/// The integrated terminal's settings and its place in the window.
@immutable
class TerminalPreferences extends Equatable {
  const TerminalPreferences({
    this.shell = '',
    this.fontFamily = '',
    this.fontSize = 12,
    this.scrollback = 10000,
    this.lines = defaultLines,
    this.place = TerminalPlace.hidden,
    this.host = TerminalHost.window,
    this.tabIndex = -1,
    this.tabSelected = true,
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

  /// An installed font family; empty for the platform's monospace face.
  final String fontFamily;
  final double fontSize;

  /// Lines kept above the screen to scroll back to.
  final int scrollback;

  /// The terminal's height under the panels, in lines.
  final int lines;

  /// Where the terminal was when the window closed.
  final TerminalPlace place;
  final TerminalHost host;

  /// Position among file tabs; -1 appends the terminal after them.
  final int tabIndex;
  final bool tabSelected;

  TerminalPreferences copyWith({
    String? shell,
    String? fontFamily,
    double? fontSize,
    int? scrollback,
    int? lines,
    TerminalPlace? place,
    TerminalHost? host,
    int? tabIndex,
    bool? tabSelected,
  }) => TerminalPreferences(
    shell: shell ?? this.shell,
    fontFamily: fontFamily ?? this.fontFamily,
    fontSize: fontSize ?? this.fontSize,
    scrollback: scrollback ?? this.scrollback,
    lines: lines ?? this.lines,
    place: place ?? this.place,
    host: host ?? this.host,
    tabIndex: tabIndex ?? this.tabIndex,
    tabSelected: tabSelected ?? this.tabSelected,
  );

  Map<String, Object?> toJson() => {
    'shell': shell,
    'fontFamily': fontFamily,
    'fontSize': fontSize,
    'scrollback': scrollback,
    'lines': lines,
    'place': place.name,
    'host': host.name,
    'tabIndex': tabIndex,
    'tabSelected': tabSelected,
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
      fontFamily: json['fontFamily'] is String
          ? (json['fontFamily']! as String).trim()
          : defaults.fontFamily,
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
      place: TerminalPlace.values.asNameMap()[json['place']] ?? defaults.place,
      host: TerminalHost.values.asNameMap()[json['host']] ?? defaults.host,
      tabIndex: numberOr(
        json['tabIndex'],
        defaults.tabIndex,
      ).round().clamp(-1, 10000),
      tabSelected: json['tabSelected'] is bool
          ? json['tabSelected']! as bool
          : defaults.tabSelected,
    );
  }

  @override
  List<Object?> get props => [
    shell,
    fontFamily,
    fontSize,
    scrollback,
    lines,
    place,
    host,
    tabIndex,
    tabSelected,
  ];
}
