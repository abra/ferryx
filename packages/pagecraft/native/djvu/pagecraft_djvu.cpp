// SPDX-License-Identifier: GPL-2.0-or-later
// This adapter links the vendored DjVuLibre decoder; see upstream/COPYING.
#include "pagecraft_djvu.h"

#include "ddjvuapi.h"
#include "miniexp.h"

#include <algorithm>
#include <cctype>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <fstream>
#ifdef _WIN32
#include <filesystem>
#endif
#include <limits>
#include <memory>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

namespace {
using Clock = std::chrono::steady_clock;
thread_local std::string last_error;
constexpr int64_t max_render_pixels = 6000000;
constexpr int64_t max_source_pixels = 100000000;
constexpr int max_pages = 100000;
constexpr size_t max_text_bytes = 8 * 1024 * 1024;
constexpr size_t max_nodes = 100000;

struct Document {
  ddjvu_context_t *context = nullptr;
  ddjvu_document_t *document = nullptr;
  int64_t timeout_ms = 30000;
  ~Document() {
    if (document) {
      ddjvu_job_stop(ddjvu_document_job(document));
      ddjvu_document_release(document);
    }
    if (context)
      ddjvu_context_release(context);
  }
};

struct Page {
  ddjvu_page_t *page;
  ~Page() {
    if (page) {
      ddjvu_job_stop(ddjvu_page_job(page));
      ddjvu_page_release(page);
    }
  }
};

struct Expression {
  Document &owner;
  miniexp_t value;
  ~Expression() { ddjvu_miniexp_release(owner.document, value); }
};

Document &document_of(void *opaque) {
  if (!opaque)
    throw std::runtime_error("DjVu document is closed");
  return *static_cast<Document *>(opaque);
}

void messages(Document &doc) {
  std::string error;
  while (const auto *message = ddjvu_message_peek(doc.context)) {
    if (message->m_any.tag == DDJVU_ERROR && error.empty()) {
      const auto *text = message->m_error.message;
      error = text ? std::string(text).substr(0, 1024) : "DjVu decoding failed";
    }
    ddjvu_message_pop(doc.context);
  }
  if (!error.empty())
    throw std::runtime_error(error);
}

template <typename Predicate> void wait_for(Document &doc, Predicate ready) {
  const auto deadline =
      Clock::now() + std::chrono::milliseconds(doc.timeout_ms);
  while (!ready()) {
    messages(doc);
    if (Clock::now() >= deadline)
      throw std::runtime_error("DjVu decoding timed out");
    // ddjvu_message_wait has no timeout. Poll only while this operation runs.
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
  messages(doc);
}

uint32_t big_endian(const unsigned char *bytes) {
  return (uint32_t(bytes[0]) << 24) | (uint32_t(bytes[1]) << 16) |
         (uint32_t(bytes[2]) << 8) | uint32_t(bytes[3]);
}

void read_at(std::ifstream &file, uint64_t offset, unsigned char *out,
             size_t n) {
  file.seekg(static_cast<std::streamoff>(offset));
  if (!file.read(reinterpret_cast<char *>(out),
                 static_cast<std::streamsize>(n)))
    throw std::runtime_error("Truncated DjVu container");
}

void validate_container(const char *path) {
  if (!path || !*path)
    throw std::runtime_error("Missing DjVu file path");
#ifdef _WIN32
  std::ifstream file(std::filesystem::u8path(path),
                     std::ios::binary | std::ios::ate);
#else
  std::ifstream file(path, std::ios::binary | std::ios::ate);
#endif
  if (!file)
    throw std::runtime_error("Cannot open DjVu file");
  const auto length = file.tellg();
  if (length < 16)
    throw std::runtime_error("Not a DjVu document");
  unsigned char header[25] = {};
  read_at(file, 0, header, 16);
  if (std::memcmp(header, "AT&TFORM", 8) != 0)
    throw std::runtime_error("Not a DjVu document");
  const uint64_t end = 12ULL + big_endian(header + 8);
  if (end < 16 || end > static_cast<uint64_t>(length))
    throw std::runtime_error("Truncated DjVu container");
  if (std::memcmp(header + 12, "DJVM", 4) == 0) {
    read_at(file, 16, header + 16, 9);
    if (end < 25 || std::memcmp(header + 16, "DIRM", 4) != 0 ||
        big_endian(header + 20) < 1 || !(header[24] & 0x80))
      throw std::runtime_error("Indirect DjVu documents are not supported");
  } else if (std::memcmp(header + 12, "DJVU", 4) == 0) {
    // Standalone INCL chunks can name arbitrary sibling files. Bundled INCLs
    // are resolved inside DIRM by DjVuLibre and retain random-access loading.
    uint64_t offset = 16;
    size_t chunks = 0;
    while (offset + 8 <= end) {
      if (++chunks > max_nodes)
        throw std::runtime_error("Too many DjVu chunks");
      unsigned char chunk[8];
      read_at(file, offset, chunk, sizeof(chunk));
      const uint64_t size = big_endian(chunk + 4);
      if (size > end - offset - 8)
        throw std::runtime_error("Invalid DjVu chunk size");
      if (std::memcmp(chunk, "INCL", 4) == 0 ||
          std::memcmp(chunk, "NDIR", 4) == 0)
        throw std::runtime_error("External DjVu components are not supported");
      offset += 8 + size + (size & 1);
    }
  } else {
    throw std::runtime_error("Unsupported DjVu container type");
  }
}

void check_page(Document &doc, int index) {
  if (index < 0 || index >= ddjvu_document_get_pagenum(doc.document))
    throw std::runtime_error("DjVu page index is out of range");
}

ddjvu_pageinfo_t page_info(Document &doc, int index) {
  check_page(doc, index);
  ddjvu_pageinfo_t info = {};
  ddjvu_status_t status;
  wait_for(doc, [&] {
    status = ddjvu_document_get_pageinfo(doc.document, index, &info);
    return status >= DDJVU_JOB_OK;
  });
  if (status != DDJVU_JOB_OK || info.width <= 0 || info.height <= 0 ||
      int64_t(info.width) * info.height > max_source_pixels)
    throw std::runtime_error("Invalid or oversized DjVu page");
  return info;
}

std::pair<int, int> oriented_size(const ddjvu_pageinfo_t &info) {
  // ddjvu_document_get_pageinfo already applies the initial orientation.
  return std::make_pair(info.width, info.height);
}

std::string json_string(const std::string &value) {
  if (value.size() > max_text_bytes)
    throw std::runtime_error("DjVu text exceeds its size limit");
  static constexpr char hex[] = "0123456789abcdef";
  std::string result = "\"";
  for (unsigned char ch : value) {
    if (ch == '"' || ch == '\\') {
      result += '\\';
      result += static_cast<char>(ch);
    } else if (ch < 0x20) {
      result += "\\u00";
      result += hex[ch >> 4];
      result += hex[ch & 15];
    } else {
      result += static_cast<char>(ch);
    }
  }
  return result + '"';
}

char *allocated(const std::string &text) {
  if (text.size() > max_text_bytes * 4)
    throw std::runtime_error("DjVu result exceeds its size limit");
  auto *result = static_cast<char *>(std::malloc(text.size() + 1));
  if (!result)
    throw std::bad_alloc();
  std::memcpy(result, text.c_str(), text.size() + 1);
  return result;
}

template <typename Getter> miniexp_t expression(Document &doc, Getter get) {
  miniexp_t value;
  wait_for(doc, [&] {
    value = get();
    return value != miniexp_dummy;
  });
  if (miniexp_symbolp(value))
    throw std::runtime_error("Cannot read DjVu text data");
  return value;
}

struct Word {
  std::string text;
  int x, y, width, height;
};

void collect_words(miniexp_t node, const ddjvu_pageinfo_t &info,
                   std::vector<Word> &words, size_t &visited, size_t &bytes,
                   int depth) {
  if (++visited > max_nodes || depth > 64)
    throw std::runtime_error("DjVu text structure exceeds its limit");
  if (!miniexp_consp(node))
    return;
  const auto kind = miniexp_nth(0, node);
  if (!miniexp_symbolp(kind))
    return;
  auto children =
      miniexp_cdr(miniexp_cdr(miniexp_cdr(miniexp_cdr(miniexp_cdr(node)))));
  while (miniexp_consp(children)) {
    if (++visited > max_nodes)
      throw std::runtime_error("DjVu text exceeds its node limit");
    const auto child = miniexp_car(children);
    if (miniexp_stringp(child)) {
      bool rectangle = true;
      for (int i = 1; i <= 4; ++i)
        rectangle = rectangle && miniexp_numberp(miniexp_nth(i, node));
      if (rectangle) {
        const int x1 = miniexp_to_int(miniexp_nth(1, node));
        const int y1 = miniexp_to_int(miniexp_nth(2, node));
        const int x2 = miniexp_to_int(miniexp_nth(3, node));
        const int y2 = miniexp_to_int(miniexp_nth(4, node));
        const int raw_width = (info.rotation & 1) ? info.height : info.width;
        const int raw_height = (info.rotation & 1) ? info.width : info.height;
        int x = std::clamp(x1, 0, raw_width);
        int y = raw_height - std::clamp(y2, 0, raw_height);
        int w = std::clamp(x2, x, raw_width) - x;
        int h = std::max(0, std::clamp(y2, 0, raw_height) -
                                std::clamp(y1, 0, raw_height));
        switch (info.rotation & 3) {
        case 1: {
          const int old_x = x;
          x = y;
          y = raw_width - old_x - w;
          std::swap(w, h);
          break;
        }
        case 2:
          x = raw_width - x - w;
          y = raw_height - y - h;
          break;
        case 3: {
          const int old_x = x;
          x = raw_height - y - h;
          y = old_x;
          std::swap(w, h);
          break;
        }
        }
        const char *text = miniexp_to_str(child);
        const size_t length = std::strlen(text);
        if (length > max_text_bytes - bytes)
          throw std::runtime_error("DjVu text exceeds its size limit");
        bytes += length;
        if (w > 0 && h > 0 && length > 0)
          words.push_back({text, x, y, w, h});
      }
    } else {
      collect_words(child, info, words, visited, bytes, depth + 1);
    }
    children = miniexp_cdr(children);
  }
}

int outline_page(Document &doc, const char *target) {
  if (!target || target[0] != '#')
    return -1;
  const char *value = target + 1;
  char *end = nullptr;
  const long number = std::strtol(value, &end, 10);
  const int pages = ddjvu_document_get_pagenum(doc.document);
  if (end != value && *end == '\0')
    return number >= 1 && number <= pages ? static_cast<int>(number - 1) : -1;
  const int files = ddjvu_document_get_filenum(doc.document);
  for (int i = 0; i < files; ++i) {
    ddjvu_fileinfo_t info = {};
    if (ddjvu_document_get_fileinfo(doc.document, i, &info) == DDJVU_JOB_OK &&
        info.pageno >= 0 && info.pageno < pages &&
        ((info.id && std::strcmp(info.id, value) == 0) ||
         (info.name && std::strcmp(info.name, value) == 0) ||
         (info.title && std::strcmp(info.title, value) == 0)))
      return info.pageno;
  }
  return -1;
}

std::string outline_items(Document &doc, miniexp_t items, size_t &visited,
                          int depth) {
  if (depth > 64)
    throw std::runtime_error("DjVu outline exceeds its depth limit");
  std::string result = "[";
  bool comma = false;
  while (miniexp_consp(items)) {
    if (++visited > max_nodes)
      throw std::runtime_error("DjVu outline exceeds its size limit");
    const auto item = miniexp_car(items);
    const auto title = miniexp_nth(0, item);
    const auto target = miniexp_nth(1, item);
    if (miniexp_stringp(title)) {
      if (comma)
        result += ',';
      comma = true;
      const int page = miniexp_stringp(target)
                           ? outline_page(doc, miniexp_to_str(target))
                           : -1;
      result +=
          "{\"title\":" + json_string(miniexp_to_str(title)) + ",\"page\":";
      result += page < 0 ? "null" : std::to_string(page);
      result += ",\"children\":" +
                outline_items(doc, miniexp_cdr(miniexp_cdr(item)), visited,
                              depth + 1) +
                '}';
    }
    if (result.size() > max_text_bytes)
      throw std::runtime_error("DjVu outline exceeds its size limit");
    items = miniexp_cdr(items);
  }
  return result + ']';
}

template <typename Value, typename Operation>
Value guarded(Value failed, Operation operation) {
  last_error.clear();
  try {
    return operation();
  } catch (const std::exception &error) {
    last_error = error.what();
  } catch (...) {
    last_error = "DjVu operation failed";
  }
  return failed;
}
} // namespace

extern "C" {
void *pagecraft_djvu_open(const char *path, int64_t timeout_ms) {
  return guarded<void *>(nullptr, [&]() -> void * {
    validate_container(path);
    auto doc = std::make_unique<Document>();
    doc->timeout_ms = std::clamp<int64_t>(timeout_ms, 1, 120000);
    doc->context = ddjvu_context_create("pagecraft");
    if (!doc->context)
      throw std::runtime_error("Cannot create DjVu decoder");
    ddjvu_cache_set_size(doc->context, 32 * 1024 * 1024);
    doc->document =
        ddjvu_document_create_by_filename_utf8(doc->context, path, 1);
    if (!doc->document)
      throw std::runtime_error("Cannot open DjVu document");
    wait_for(*doc, [&] { return ddjvu_document_decoding_done(doc->document); });
    if (ddjvu_document_decoding_error(doc->document))
      throw std::runtime_error("Cannot decode DjVu document");
    const auto type = ddjvu_document_get_type(doc->document);
    const int count = ddjvu_document_get_pagenum(doc->document);
    if ((type != DDJVU_DOCTYPE_BUNDLED && type != DDJVU_DOCTYPE_SINGLEPAGE) ||
        count <= 0 || count > max_pages)
      throw std::runtime_error("Unsupported DjVu document structure");
    return doc.release();
  });
}

void pagecraft_djvu_close(void *document) {
  delete static_cast<Document *>(document);
}
const char *pagecraft_djvu_last_error() { return last_error.c_str(); }
void pagecraft_djvu_free(void *allocation) { std::free(allocation); }

int32_t pagecraft_djvu_page_count(void *document) {
  return guarded<int32_t>(0, [&] {
    return ddjvu_document_get_pagenum(document_of(document).document);
  });
}

int32_t pagecraft_djvu_page_info(void *document, int32_t page, int32_t *width,
                                 int32_t *height, int32_t *dpi) {
  return guarded<int32_t>(0, [&] {
    if (!width || !height || !dpi)
      throw std::runtime_error("Missing DjVu page output");
    const auto info = page_info(document_of(document), page);
    const auto size = oriented_size(info);
    *width = size.first;
    *height = size.second;
    *dpi = info.dpi;
    return 1;
  });
}

uint8_t *pagecraft_djvu_render(void *document, int32_t index,
                               int32_t full_width, int32_t full_height,
                               int32_t x, int32_t y, int32_t width,
                               int32_t height) {
  return guarded<uint8_t *>(nullptr, [&] {
    auto &doc = document_of(document);
    page_info(doc, index);
    if (full_width <= 0 || full_height <= 0 || full_width > 131072 ||
        full_height > 131072 || x < 0 || y < 0 || width <= 0 || height <= 0 ||
        int64_t(x) + width > full_width || int64_t(y) + height > full_height ||
        int64_t(width) * height > max_render_pixels)
      throw std::runtime_error("Invalid or oversized DjVu render region");
    Page page{ddjvu_page_create_by_pageno(doc.document, index)};
    if (!page.page)
      throw std::runtime_error("Cannot open DjVu page");
    wait_for(doc, [&] { return ddjvu_page_decoding_done(page.page); });
    if (ddjvu_page_decoding_error(page.page))
      throw std::runtime_error("Cannot decode DjVu page");
    unsigned int masks[] = {0x000000ff, 0x0000ff00, 0x00ff0000, 0xff000000};
    auto format =
        std::unique_ptr<ddjvu_format_t, decltype(&ddjvu_format_release)>(
            ddjvu_format_create(DDJVU_FORMAT_RGBMASK32, 4, masks),
            ddjvu_format_release);
    if (!format)
      throw std::runtime_error("Cannot create DjVu pixel format");
    ddjvu_format_set_row_order(format.get(), 1);
    ddjvu_format_set_y_direction(format.get(), 1);
    const ddjvu_rect_t whole{0, 0, static_cast<unsigned>(full_width),
                             static_cast<unsigned>(full_height)};
    const ddjvu_rect_t region{x, y, static_cast<unsigned>(width),
                              static_cast<unsigned>(height)};
    const size_t length = static_cast<size_t>(width) * height * 4;
    auto pixels = std::unique_ptr<uint8_t, decltype(&std::free)>(
        static_cast<uint8_t *>(std::malloc(length)), std::free);
    if (!pixels)
      throw std::bad_alloc();
    if (!ddjvu_page_render(page.page, DDJVU_RENDER_COLOR, &whole, &region,
                           format.get(), width * 4,
                           reinterpret_cast<char *>(pixels.get())))
      throw std::runtime_error("Cannot render DjVu page");
    return pixels.release();
  });
}

char *pagecraft_djvu_text(void *document, int32_t page) {
  return guarded<char *>(nullptr, [&] {
    auto &doc = document_of(document);
    const auto info = page_info(doc, page);
    Expression text{doc, expression(doc, [&] {
                      return ddjvu_document_get_pagetext(doc.document, page,
                                                         "word");
                    })};
    std::vector<Word> words;
    size_t visited = 0;
    size_t bytes = 0;
    collect_words(text.value, info, words, visited, bytes, 0);
    const auto size = oriented_size(info);
    std::string result = "{\"width\":" + std::to_string(size.first) +
                         ",\"height\":" + std::to_string(size.second) +
                         ",\"words\":[";
    std::string content;
    for (const auto &word : words) {
      if (!content.empty()) {
        result += ',';
        content += ' ';
      }
      content += word.text;
      if (content.size() > max_text_bytes)
        throw std::runtime_error("DjVu text exceeds its size limit");
      result += "{\"text\":" + json_string(word.text) +
                ",\"x\":" + std::to_string(word.x) +
                ",\"y\":" + std::to_string(word.y) +
                ",\"width\":" + std::to_string(word.width) +
                ",\"height\":" + std::to_string(word.height) + '}';
    }
    return allocated(result + "],\"text\":" + json_string(content) + '}');
  });
}

char *pagecraft_djvu_outline(void *document) {
  return guarded<char *>(nullptr, [&] {
    auto &doc = document_of(document);
    Expression value{doc, expression(doc, [&] {
                       return ddjvu_document_get_outline(doc.document);
                     })};
    size_t visited = 0;
    return allocated(outline_items(doc, miniexp_cdr(value.value), visited, 0));
  });
}

char *pagecraft_djvu_metadata(void *document) {
  return guarded<char *>(nullptr, [&] {
    auto &doc = document_of(document);
    Expression global{doc, expression(doc, [&] {
                        return ddjvu_document_get_anno(doc.document, 1);
                      })};
    Expression first{doc, expression(doc, [&] {
                       return ddjvu_document_get_pageanno(doc.document, 0);
                     })};
    auto field = [&](const char *key) {
      for (const auto annotation : {global.value, first.value}) {
        auto keys = std::unique_ptr<miniexp_t, decltype(&std::free)>(
            ddjvu_anno_get_metadata_keys(annotation), std::free);
        if (!keys)
          continue;
        for (size_t i = 0; keys.get()[i] && i < max_nodes; ++i) {
          const auto name = miniexp_to_name(keys.get()[i]);
          if (!name)
            continue;
          std::string folded(name);
          std::transform(folded.begin(), folded.end(), folded.begin(),
                         [](unsigned char c) {
                           return static_cast<char>(std::tolower(c));
                         });
          if (folded == key) {
            const auto value =
                ddjvu_anno_get_metadata(annotation, keys.get()[i]);
            if (value)
              return json_string(value);
          }
        }
      }
      return std::string("null");
    };
    return allocated("{\"title\":" + field("title") +
                     ",\"author\":" + field("author") + '}');
  });
}
}
