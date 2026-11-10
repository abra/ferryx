/// Design tokens, theme and reusable desktop UI widgets.
///
/// Screens use roles, never raw values: `context.colors`, `context.appColors`,
/// `context.text`, `context.metrics` and the shared `App*` tokens. The theme
/// follows the platform's own conventions (`AppPlatformStyle`: macOS HIG,
/// Fluent, GNOME HIG); platform differences stay in the theme and in these
/// widgets, never in feature code.
library;

export 'src/app_dialog.dart';
export 'src/app_divider.dart';
export 'src/app_empty_state.dart';
export 'src/app_fit_or_else.dart';
export 'src/app_focus_area.dart';
export 'src/app_form_field.dart';
export 'src/app_label_and_detail.dart';
export 'src/app_label_row.dart';
export 'src/app_icon_button.dart';
export 'src/app_icons.dart';
export 'src/app_identity.dart';
export 'src/app_tab_strip.dart';
export 'src/app_key_cap.dart';
export 'src/app_key_hints.dart';
export 'src/app_checkbox.dart';
export 'src/app_context_menu.dart';
export 'src/app_menu.dart';
export 'src/app_notice.dart';
export 'src/app_page_tabs.dart';
export 'src/app_popover.dart';
export 'src/app_menu_button.dart';
export 'src/app_middle_ellipsis.dart';
export 'src/app_window_activity.dart';
export 'src/app_spinner.dart';
export 'src/app_status_bar.dart';
export 'src/app_control_row.dart';
export 'src/app_popup_button.dart';
export 'src/app_nav_item.dart';
export 'src/app_scroll_keys.dart';
export 'src/app_search_field.dart';
export 'src/app_text_field.dart';
export 'src/app_splitter.dart';
export 'src/app_progress_bar.dart';
export 'src/app_quick_picker.dart';
export 'src/pixel_snap.dart';
export 'src/popup_focus.dart';
export 'src/app_section_label.dart';
export 'src/app_segmented_control.dart';
export 'src/app_toggle.dart';
export 'src/app_tag_dots.dart';
export 'src/app_tooltip.dart';
export 'src/app_top_bar_row.dart';
export 'src/app_value_tip.dart';
export 'src/focus_highlight.dart';
export 'src/app_drop_outline.dart';
export 'src/file_drag_source.dart';
export 'src/file_drop_target.dart';
export 'src/focus_ring.dart';
export 'src/tap_outside_keeps_focus.dart';
export 'src/hints/hint_mode_host.dart';
export 'src/hints/hint_overlay.dart';
export 'src/hints/hint_registry.dart';
export 'src/theme/app_button_styles.dart';
export 'src/theme/app_platform_style.dart';
export 'src/theme/app_theme.dart';
export 'src/window_decor.dart';
export 'src/theme/app_typography.dart';
export 'src/theme/fluent_borders.dart';
export 'src/theme/hairlines.dart';
export 'src/theme/extensions/app_colors_ext.dart';
export 'src/theme/extensions/app_metrics.dart';
export 'src/theme/extensions/app_terminal_colors.dart';
export 'src/theme/extensions/build_context_ext.dart';
export 'src/theme/tokens/app_icon_size.dart';
export 'src/theme/tokens/app_motion.dart';
export 'src/theme/tokens/app_palette.dart';
export 'src/theme/tokens/app_radius.dart';
export 'src/theme/tokens/app_sizes.dart';
export 'src/theme/tokens/app_spacing.dart';
export 'src/app_row_list.dart';
