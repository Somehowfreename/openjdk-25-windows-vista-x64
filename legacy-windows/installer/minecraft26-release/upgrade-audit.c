#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

typedef struct {
  wchar_t *path;
  char hash[65];
} ExpectedFile;

typedef struct {
  const char *kind;
  wchar_t *path;
} Issue;

typedef struct {
  ExpectedFile *expected;
  size_t expected_count;
  Issue *issues;
  size_t issue_count;
  unsigned modified;
  unsigned missing;
  unsigned extra;
} Audit;

typedef struct {
  unsigned long state[8];
  unsigned long long bit_count;
  unsigned char block[64];
  unsigned block_used;
} Sha256;

static const unsigned long k256[64] = {
    0x428a2f98UL, 0x71374491UL, 0xb5c0fbcfUL, 0xe9b5dba5UL,
    0x3956c25bUL, 0x59f111f1UL, 0x923f82a4UL, 0xab1c5ed5UL,
    0xd807aa98UL, 0x12835b01UL, 0x243185beUL, 0x550c7dc3UL,
    0x72be5d74UL, 0x80deb1feUL, 0x9bdc06a7UL, 0xc19bf174UL,
    0xe49b69c1UL, 0xefbe4786UL, 0x0fc19dc6UL, 0x240ca1ccUL,
    0x2de92c6fUL, 0x4a7484aaUL, 0x5cb0a9dcUL, 0x76f988daUL,
    0x983e5152UL, 0xa831c66dUL, 0xb00327c8UL, 0xbf597fc7UL,
    0xc6e00bf3UL, 0xd5a79147UL, 0x06ca6351UL, 0x14292967UL,
    0x27b70a85UL, 0x2e1b2138UL, 0x4d2c6dfcUL, 0x53380d13UL,
    0x650a7354UL, 0x766a0abbUL, 0x81c2c92eUL, 0x92722c85UL,
    0xa2bfe8a1UL, 0xa81a664bUL, 0xc24b8b70UL, 0xc76c51a3UL,
    0xd192e819UL, 0xd6990624UL, 0xf40e3585UL, 0x106aa070UL,
    0x19a4c116UL, 0x1e376c08UL, 0x2748774cUL, 0x34b0bcb5UL,
    0x391c0cb3UL, 0x4ed8aa4aUL, 0x5b9cca4fUL, 0x682e6ff3UL,
    0x748f82eeUL, 0x78a5636fUL, 0x84c87814UL, 0x8cc70208UL,
    0x90befffaUL, 0xa4506cebUL, 0xbef9a3f7UL, 0xc67178f2UL};

static unsigned long ror32(unsigned long value, unsigned bits) {
  return (value >> bits) | (value << (32U - bits));
}

static void sha256_transform(Sha256 *ctx, const unsigned char *block) {
  unsigned long w[64];
  unsigned long a, b, c, d, e, f, g, h;
  unsigned i;
  for (i = 0; i < 16; ++i) {
    w[i] = ((unsigned long)block[i * 4] << 24) |
           ((unsigned long)block[i * 4 + 1] << 16) |
           ((unsigned long)block[i * 4 + 2] << 8) |
           (unsigned long)block[i * 4 + 3];
  }
  for (i = 16; i < 64; ++i) {
    unsigned long s0 = ror32(w[i - 15], 7) ^ ror32(w[i - 15], 18) ^
                       (w[i - 15] >> 3);
    unsigned long s1 = ror32(w[i - 2], 17) ^ ror32(w[i - 2], 19) ^
                       (w[i - 2] >> 10);
    w[i] = w[i - 16] + s0 + w[i - 7] + s1;
  }
  a = ctx->state[0]; b = ctx->state[1]; c = ctx->state[2]; d = ctx->state[3];
  e = ctx->state[4]; f = ctx->state[5]; g = ctx->state[6]; h = ctx->state[7];
  for (i = 0; i < 64; ++i) {
    unsigned long s1 = ror32(e, 6) ^ ror32(e, 11) ^ ror32(e, 25);
    unsigned long ch = (e & f) ^ ((~e) & g);
    unsigned long t1 = h + s1 + ch + k256[i] + w[i];
    unsigned long s0 = ror32(a, 2) ^ ror32(a, 13) ^ ror32(a, 22);
    unsigned long maj = (a & b) ^ (a & c) ^ (b & c);
    unsigned long t2 = s0 + maj;
    h = g; g = f; f = e; e = d + t1;
    d = c; c = b; b = a; a = t1 + t2;
  }
  ctx->state[0] += a; ctx->state[1] += b; ctx->state[2] += c;
  ctx->state[3] += d; ctx->state[4] += e; ctx->state[5] += f;
  ctx->state[6] += g; ctx->state[7] += h;
}

static void sha256_init(Sha256 *ctx) {
  static const unsigned long initial[8] = {
      0x6a09e667UL, 0xbb67ae85UL, 0x3c6ef372UL, 0xa54ff53aUL,
      0x510e527fUL, 0x9b05688cUL, 0x1f83d9abUL, 0x5be0cd19UL};
  memcpy(ctx->state, initial, sizeof(initial));
  ctx->bit_count = 0;
  ctx->block_used = 0;
}

static void sha256_update(Sha256 *ctx, const unsigned char *data, size_t size) {
  while (size != 0) {
    size_t room = 64U - ctx->block_used;
    size_t take = size < room ? size : room;
    memcpy(ctx->block + ctx->block_used, data, take);
    ctx->block_used += (unsigned)take;
    ctx->bit_count += (unsigned long long)take * 8ULL;
    data += take;
    size -= take;
    if (ctx->block_used == 64U) {
      sha256_transform(ctx, ctx->block);
      ctx->block_used = 0;
    }
  }
}

static void sha256_final(Sha256 *ctx, unsigned char digest[32]) {
  unsigned i;
  unsigned long long bits = ctx->bit_count;
  ctx->block[ctx->block_used++] = 0x80;
  if (ctx->block_used > 56U) {
    while (ctx->block_used < 64U) ctx->block[ctx->block_used++] = 0;
    sha256_transform(ctx, ctx->block);
    ctx->block_used = 0;
  }
  while (ctx->block_used < 56U) ctx->block[ctx->block_used++] = 0;
  for (i = 0; i < 8; ++i) {
    ctx->block[63U - i] = (unsigned char)(bits & 0xffU);
    bits >>= 8;
  }
  sha256_transform(ctx, ctx->block);
  for (i = 0; i < 8; ++i) {
    digest[i * 4] = (unsigned char)(ctx->state[i] >> 24);
    digest[i * 4 + 1] = (unsigned char)(ctx->state[i] >> 16);
    digest[i * 4 + 2] = (unsigned char)(ctx->state[i] >> 8);
    digest[i * 4 + 3] = (unsigned char)ctx->state[i];
  }
}

static wchar_t *duplicate_wide(const wchar_t *value) {
  size_t bytes = (wcslen(value) + 1U) * sizeof(wchar_t);
  wchar_t *copy = (wchar_t *)malloc(bytes);
  if (copy != NULL) memcpy(copy, value, bytes);
  return copy;
}

static void normalize_path(wchar_t *path) {
  while (*path != L'\0') {
    if (*path == L'/') *path = L'\\';
    ++path;
  }
}

static int safe_relative_path(const wchar_t *path) {
  const wchar_t *cursor = path;
  if (*path == L'\0' || *path == L'\\' || wcschr(path, L':') != NULL) return 0;
  while (*cursor != L'\0') {
    const wchar_t *end = wcschr(cursor, L'\\');
    size_t length = end == NULL ? wcslen(cursor) : (size_t)(end - cursor);
    if (length == 0U || (length == 2U && cursor[0] == L'.' && cursor[1] == L'.')) return 0;
    if (end == NULL) break;
    cursor = end + 1;
  }
  return 1;
}

static int add_issue(Audit *audit, const char *kind, const wchar_t *path) {
  Issue *grown = (Issue *)realloc(audit->issues,
      (audit->issue_count + 1U) * sizeof(Issue));
  if (grown == NULL) return 0;
  audit->issues = grown;
  audit->issues[audit->issue_count].kind = kind;
  audit->issues[audit->issue_count].path = duplicate_wide(path);
  if (audit->issues[audit->issue_count].path == NULL) return 0;
  ++audit->issue_count;
  if (strcmp(kind, "MODIFIED") == 0 || strcmp(kind, "UNREADABLE") == 0)
    ++audit->modified;
  else if (strcmp(kind, "MISSING") == 0)
    ++audit->missing;
  else
    ++audit->extra;
  return 1;
}

static int load_manifest(Audit *audit, const wchar_t *manifest) {
  FILE *stream = _wfopen(manifest, L"rb");
  char line[8192];
  if (stream == NULL) return 0;
  while (fgets(line, sizeof(line), stream) != NULL) {
    size_t length = strlen(line);
    char *relative;
    wchar_t wide[4096];
    ExpectedFile *grown;
    while (length != 0U && (line[length - 1U] == '\r' || line[length - 1U] == '\n'))
      line[--length] = '\0';
    if (length == 0U) continue;
    if (length < 67U || line[64] != ' ' || line[65] != ' ') {
      fclose(stream);
      return 0;
    }
    line[64] = '\0';
    relative = line + 66;
    if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, relative, -1,
                            wide, (int)(sizeof(wide) / sizeof(wide[0]))) == 0) {
      fclose(stream);
      return 0;
    }
    normalize_path(wide);
    if (!safe_relative_path(wide)) {
      fclose(stream);
      return 0;
    }
    grown = (ExpectedFile *)realloc(audit->expected,
        (audit->expected_count + 1U) * sizeof(ExpectedFile));
    if (grown == NULL) {
      fclose(stream);
      return 0;
    }
    audit->expected = grown;
    audit->expected[audit->expected_count].path = duplicate_wide(wide);
    if (audit->expected[audit->expected_count].path == NULL) {
      fclose(stream);
      return 0;
    }
    memcpy(audit->expected[audit->expected_count].hash, line, 65U);
    ++audit->expected_count;
  }
  fclose(stream);
  return audit->expected_count != 0U;
}

static int hash_file(const wchar_t *path, char output[65]) {
  HANDLE file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL,
                            OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
  unsigned char buffer[65536];
  unsigned char digest[32];
  DWORD read_count;
  Sha256 sha;
  unsigned i;
  static const char hex[] = "0123456789ABCDEF";
  if (file == INVALID_HANDLE_VALUE) return 0;
  sha256_init(&sha);
  for (;;) {
    if (!ReadFile(file, buffer, sizeof(buffer), &read_count, NULL)) {
      CloseHandle(file);
      return 0;
    }
    if (read_count == 0U) break;
    sha256_update(&sha, buffer, read_count);
  }
  CloseHandle(file);
  sha256_final(&sha, digest);
  for (i = 0; i < 32; ++i) {
    output[i * 2] = hex[digest[i] >> 4];
    output[i * 2 + 1] = hex[digest[i] & 15U];
  }
  output[64] = '\0';
  return 1;
}

static int combine_path(wchar_t *output, size_t capacity,
                        const wchar_t *first, const wchar_t *second) {
  int result = _snwprintf(output, capacity, L"%s\\%s", first, second);
  if (result < 0 || (size_t)result >= capacity) return 0;
  output[result] = L'\0';
  return 1;
}

static int expected_index(const Audit *audit, const wchar_t *path) {
  size_t i;
  for (i = 0; i < audit->expected_count; ++i) {
    if (_wcsicmp(audit->expected[i].path, path) == 0) return (int)i;
  }
  return -1;
}

static int is_installer_metadata(const wchar_t *path) {
  static const wchar_t *allowed[] = {
      L".legacy-openjdk-install", L"LICENSE", L"ADDITIONAL_LICENSE_INFO",
      L"ASSEMBLY_EXCEPTION", L"PAYLOAD-SHA256SUMS.txt",
      L"LEGACY-WINDOWS-PORT.txt", L"uninstall.exe"};
  size_t i;
  for (i = 0; i < sizeof(allowed) / sizeof(allowed[0]); ++i) {
    if (_wcsicmp(path, allowed[i]) == 0) return 1;
  }
  return 0;
}

static int walk_files(Audit *audit, const wchar_t *root,
                      const wchar_t *relative) {
  wchar_t directory[4096];
  wchar_t pattern[4096];
  WIN32_FIND_DATAW data;
  HANDLE find;
  DWORD final_error;
  if (relative[0] == L'\0') {
    if (_snwprintf(directory, 4096, L"%s", root) < 0) return 0;
  } else if (!combine_path(directory, 4096, root, relative)) {
    return 0;
  }
  if (_snwprintf(pattern, 4096, L"%s\\*", directory) < 0) return 0;
  find = FindFirstFileW(pattern, &data);
  if (find == INVALID_HANDLE_VALUE) return GetLastError() == ERROR_FILE_NOT_FOUND;
  do {
    wchar_t child[4096];
    if (wcscmp(data.cFileName, L".") == 0 || wcscmp(data.cFileName, L"..") == 0)
      continue;
    if (relative[0] == L'\0') {
      if (_snwprintf(child, 4096, L"%s", data.cFileName) < 0) {
        FindClose(find); return 0;
      }
    } else if (!combine_path(child, 4096, relative, data.cFileName)) {
      FindClose(find); return 0;
    }
    if ((data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
      if ((data.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
        if (!add_issue(audit, "EXTRA", child)) { FindClose(find); return 0; }
      } else if (!walk_files(audit, root, child)) {
        FindClose(find); return 0;
      }
    } else if (expected_index(audit, child) < 0 && !is_installer_metadata(child)) {
      if (!add_issue(audit, "EXTRA", child)) { FindClose(find); return 0; }
    }
  } while (FindNextFileW(find, &data));
  final_error = GetLastError();
  FindClose(find);
  return final_error == ERROR_NO_MORE_FILES;
}

static void write_utf8(FILE *stream, const wchar_t *value) {
  int needed = WideCharToMultiByte(CP_UTF8, 0, value, -1, NULL, 0, NULL, NULL);
  char *buffer;
  if (needed <= 0) return;
  buffer = (char *)malloc((size_t)needed);
  if (buffer == NULL) return;
  if (WideCharToMultiByte(CP_UTF8, 0, value, -1, buffer, needed, NULL, NULL) != 0)
    fputs(buffer, stream);
  free(buffer);
}

static int write_report(const Audit *audit, const wchar_t *report) {
  FILE *stream = _wfopen(report, L"wb");
  size_t i;
  if (stream == NULL) return 0;
  fprintf(stream, "SUMMARY: %u modified or unreadable, %u missing, %u additional.\r\n",
          audit->modified, audit->missing, audit->extra);
  for (i = 0; i < audit->issue_count; ++i) {
    fprintf(stream, "%s: ", audit->issues[i].kind);
    write_utf8(stream, audit->issues[i].path);
    fputs("\r\n", stream);
  }
  fclose(stream);
  return 1;
}

static void release_audit(Audit *audit) {
  size_t i;
  for (i = 0; i < audit->expected_count; ++i) free(audit->expected[i].path);
  for (i = 0; i < audit->issue_count; ++i) free(audit->issues[i].path);
  free(audit->expected);
  free(audit->issues);
}

int wmain(int argc, wchar_t **argv) {
  Audit audit;
  size_t i;
  int result = 20;
  memset(&audit, 0, sizeof(audit));
  if (argc != 4) return 20;
  if (!load_manifest(&audit, argv[1])) goto done;
  for (i = 0; i < audit.expected_count; ++i) {
    wchar_t full[4096];
    DWORD attributes;
    char actual[65];
    if (!combine_path(full, 4096, argv[2], audit.expected[i].path)) goto done;
    attributes = GetFileAttributesW(full);
    if (attributes == INVALID_FILE_ATTRIBUTES ||
        (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
      if (!add_issue(&audit, "MISSING", audit.expected[i].path)) goto done;
    } else if (!hash_file(full, actual)) {
      if (!add_issue(&audit, "UNREADABLE", audit.expected[i].path)) goto done;
    } else if (_stricmp(actual, audit.expected[i].hash) != 0) {
      if (!add_issue(&audit, "MODIFIED", audit.expected[i].path)) goto done;
    }
  }
  if (!walk_files(&audit, argv[2], L"")) goto done;
  if (!write_report(&audit, argv[3])) goto done;
  result = audit.issue_count == 0U ? 0 : 10;
done:
  release_audit(&audit);
  return result;
}
