#include "font_catalog.h"

namespace {

void FontMethodCall(FlMethodChannel*, FlMethodCall* call, gpointer user_data) {
  if (g_strcmp0(fl_method_call_get_name(call), "fonts.monospaceFamilies") !=
      0) {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }

  auto* font_map = PANGO_FONT_MAP(user_data);
  if (font_map == nullptr) {
    fl_method_call_respond_error(call, "font_catalog_unavailable",
                                 "The desktop has no font map.", nullptr,
                                 nullptr);
    return;
  }

  g_autofree PangoFontFamily** families = nullptr;
  int count = 0;
  pango_font_map_list_families(font_map, &families, &count);
  g_autoptr(FlValue) names = fl_value_new_list();
  for (int i = 0; i < count; ++i) {
    if (pango_font_family_is_monospace(families[i])) {
      fl_value_append_take(
          names, fl_value_new_string(pango_font_family_get_name(families[i])));
    }
  }
  fl_method_call_respond_success(call, names, nullptr);
}

}  // namespace

void RegisterFontCatalog(FlView* view) {
  auto* messenger = fl_engine_get_binary_messenger(fl_view_get_engine(view));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      messenger, "ferryx/platform", FL_METHOD_CODEC(codec));
  auto* context = gtk_widget_get_pango_context(GTK_WIDGET(view));
  auto* font_map = pango_context_get_font_map(context);
  // Retain the map, not the view: the channel lives with the engine.
  fl_method_channel_set_method_call_handler(
      channel, FontMethodCall,
      font_map == nullptr ? nullptr : g_object_ref(font_map),
      font_map == nullptr ? nullptr : g_object_unref);
}
