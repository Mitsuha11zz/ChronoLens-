#include <moonbit.h>

#include <stdint.h>

#ifdef _WIN32
#include <windows.h>

MOONBIT_FFI_EXPORT int64_t chronolens_input_file_size(moonbit_string_t path) {
  WIN32_FILE_ATTRIBUTE_DATA attributes;
  if (!GetFileAttributesExW(path, GetFileExInfoStandard, &attributes)) {
    return -1;
  }
  if ((attributes.nFileSizeHigh & 0x80000000U) != 0) {
    return INT64_MAX;
  }
  return ((int64_t)attributes.nFileSizeHigh << 32) |
         (int64_t)attributes.nFileSizeLow;
}

#else
#include <sys/stat.h>

MOONBIT_FFI_EXPORT int64_t chronolens_input_file_size(moonbit_bytes_t path) {
  struct stat attributes;
  if (stat((const char *)path, &attributes) != 0 || attributes.st_size < 0) {
    return -1;
  }
  return (int64_t)attributes.st_size;
}
#endif
