#include "font_catalog.h"

#include <dwrite_1.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <wrl/client.h>

#include <string>
#include <utility>
#include <vector>

#include "utils.h"

namespace {

using Microsoft::WRL::ComPtr;

HRESULT ReadMonospaceFontFamilies(flutter::EncodableList* families) {
  ComPtr<IDWriteFactory> factory;
  HRESULT status =
      DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory),
                          reinterpret_cast<IUnknown**>(factory.GetAddressOf()));
  if (FAILED(status)) return status;

  ComPtr<IDWriteFontCollection> collection;
  // Check for fonts installed since the settings page was last opened.
  status = factory->GetSystemFontCollection(collection.GetAddressOf(), TRUE);
  if (FAILED(status)) return status;

  for (UINT32 i = 0; i < collection->GetFontFamilyCount(); ++i) {
    ComPtr<IDWriteFontFamily> family;
    if (FAILED(collection->GetFontFamily(i, family.GetAddressOf()))) continue;
    ComPtr<IDWriteFont> regular;
    if (FAILED(family->GetFirstMatchingFont(
            DWRITE_FONT_WEIGHT_NORMAL, DWRITE_FONT_STRETCH_NORMAL,
            DWRITE_FONT_STYLE_NORMAL, regular.GetAddressOf()))) {
      continue;
    }
    ComPtr<IDWriteFont1> font;
    if (FAILED(regular.As(&font)) || !font->IsMonospacedFont()) continue;

    ComPtr<IDWriteLocalizedStrings> names;
    if (FAILED(family->GetFamilyNames(names.GetAddressOf())) ||
        names->GetCount() == 0) {
      continue;
    }
    // A stable family name also survives changing the application's language.
    UINT32 index = 0;
    BOOL exists = FALSE;
    if (FAILED(names->FindLocaleName(L"en-us", &index, &exists)) || !exists) {
      index = 0;
    }
    UINT32 length = 0;
    if (FAILED(names->GetStringLength(index, &length))) continue;
    std::vector<wchar_t> buffer(static_cast<size_t>(length) + 1);
    if (FAILED(names->GetString(index, buffer.data(), length + 1))) continue;
    auto name = Utf8FromUtf16(buffer.data());
    if (!name.empty()) families->emplace_back(std::move(name));
  }
  return S_OK;
}

}  // namespace

void RegisterFontCatalog(flutter::BinaryMessenger* messenger) {
  flutter::MethodChannel<> channel(
      messenger, "ferryx/platform",
      &flutter::StandardMethodCodec::GetInstance());
  // The messenger owns this stateless handler until the engine is destroyed.
  channel.SetMethodCallHandler([](const auto& call, auto result) {
    if (call.method_name() != "fonts.monospaceFamilies") {
      result->NotImplemented();
      return;
    }
    flutter::EncodableList families;
    if (FAILED(ReadMonospaceFontFamilies(&families))) {
      result->Error("font_catalog_unavailable",
                    "The system font collection could not be read.");
      return;
    }
    result->Success(flutter::EncodableValue(std::move(families)));
  });
}
