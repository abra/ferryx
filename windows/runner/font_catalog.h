#ifndef RUNNER_FONT_CATALOG_H_
#define RUNNER_FONT_CATALOG_H_

#include <flutter/binary_messenger.h>

// The locally installed DirectWrite families, over ferryx/platform.
void RegisterFontCatalog(flutter::BinaryMessenger* messenger);

#endif  // RUNNER_FONT_CATALOG_H_
