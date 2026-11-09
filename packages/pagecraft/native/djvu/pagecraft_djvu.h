#ifndef PAGECRAFT_DJVU_H
#define PAGECRAFT_DJVU_H

#include <stdint.h>

#if defined(_WIN32)
#define PAGECRAFT_DJVU_API __declspec(dllexport)
#else
#define PAGECRAFT_DJVU_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// All operations on a document are serialized by the caller's worker isolate.
// Functions return NULL / 0 on failure; last_error is thread-local, borrowed
// UTF-8 until the next call. Successful allocations belong to the caller.
PAGECRAFT_DJVU_API void *pagecraft_djvu_open(const char *path,
                                             int64_t timeout_ms);
PAGECRAFT_DJVU_API void pagecraft_djvu_close(void *document);
PAGECRAFT_DJVU_API const char *pagecraft_djvu_last_error(void);
PAGECRAFT_DJVU_API int32_t pagecraft_djvu_page_count(void *document);
PAGECRAFT_DJVU_API int32_t pagecraft_djvu_page_info(void *document,
                                                    int32_t page,
                                                    int32_t *width,
                                                    int32_t *height,
                                                    int32_t *dpi);

// Region coordinates use a top-left origin on the scaled full page. Returned
// pixels are tightly packed RGBA8888, with opaque alpha; release with free.
PAGECRAFT_DJVU_API uint8_t *
pagecraft_djvu_render(void *document, int32_t page, int32_t full_width,
                      int32_t full_height, int32_t x, int32_t y, int32_t width,
                      int32_t height);

// Text: {width,height,text,words:[{text,x,y,width,height}]}. Coordinates are
// top-left pixels in the oriented original page; text joins words with spaces.
// An absent text layer is a successful empty words array, not an OCR request.
PAGECRAFT_DJVU_API char *pagecraft_djvu_text(void *document, int32_t page);

// Outline: [{title,page,children}], with zero-based page or null for a target
// which does not resolve inside the document. Strings and pixels use free.
PAGECRAFT_DJVU_API char *pagecraft_djvu_outline(void *document);
// Document/first-page annotation metadata: {title,author}, nullable strings.
PAGECRAFT_DJVU_API char *pagecraft_djvu_metadata(void *document);
PAGECRAFT_DJVU_API void pagecraft_djvu_free(void *allocation);

#ifdef __cplusplus
}
#endif
#endif
