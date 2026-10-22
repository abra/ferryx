/// The two panels of the window.
enum PanelSide {
  left,
  right;

  PanelSide get opposite => this == left ? right : left;

  /// The key the preferences keep the panel's state under.
  String get key => name;
}
