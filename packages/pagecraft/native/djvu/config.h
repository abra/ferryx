#ifndef PAGECRAFT_DJVULIBRE_CONFIG_H
#define PAGECRAFT_DJVULIBRE_CONFIG_H

// Modern compiler configuration; Windows uses upstream's Win32 thread APIs.
// Optional JPEG-in-DjVu and command-line tools are not enabled by this decoder.
#define AUTOCONF 1
#define HAVE_BOOL 1
#define HAVE_EXCEPTIONS 1
#define HAVE_NAMESPACES 1
#define HAVE_MEMBER_TEMPLATES 1
#define HAVE_TYPENAME 1
#define HAVE_STDINCLUDES 1
#define HAVE_LONG_LONG_INT 1
#define HAVE_INTEL_ATOMIC_BUILTINS 1
#define HAVE_INTTYPES_H 1
#define HAVE_ISWSPACE 1
#define HAVE_MBSTATE_T 1
#define HAVE_SNPRINTF 1
#define HAVE_STDINT_H 1
#define HAVE_STDIO_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRERROR 1
#define HAVE_STRFTIME 1
#define HAVE_STRING_H 1
#define HAVE_VSNPRINTF 1
#define HAVE_WCHAR_H 1
#define HAVE_WCHAR_T 1
#define HAVE_WCRTOMB 1
#define HAVE_WCTYPE_H 1
#define HAS_WCHAR 1
#define HAS_WCTYPE 1
#define HAS_MBSTATE 1
#define HAS_ICONV 0
#ifdef _WIN32
#define DJVUAPI_EXPORT 1
#define DDJVUAPI_EXPORT 1
#define MINILISPAPI_EXPORT 1
#define HAS_MEMMAP 0
#else
#define UNIX 1
#define HAVE_PTHREAD 1
#define HAVE_DIRENT_H 1
#define HAVE_FSEEKO 1
#define HAVE_GETHOSTNAME 1
#define HAVE_GETPAGESIZE 1
#define HAVE_GETPWUID 1
#define HAVE_LANGINFO_H 1
#define HAVE_MKSTEMP 1
#define HAVE_MMAP 1
#define HAVE_NL_LANGINFO 1
#define HAVE_PUTC_UNLOCKED 1
#define HAVE_SCHED_H 1
#define HAVE_SCHED_YIELD 1
#define HAVE_SETENV 1
#define HAVE_STRINGS_H 1
#define HAVE_SYS_MMAN_H 1
#define HAVE_SYS_PARAM_H 1
#define HAVE_SYS_STAT_H 1
#define HAVE_SYS_TIME_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_UNISTD_H 1
#define HAS_MEMMAP 1
#endif
#define HAS_CTRL_C_IN_ERR_MSG 0
#define PACKAGE_NAME "DjVuLibre"
#define PACKAGE_VERSION "3.5.30"
#define VERSION "3.5.30"
#define DIR_DATADIR ""

#endif
