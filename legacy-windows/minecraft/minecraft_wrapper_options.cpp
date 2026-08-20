/*
 * Copyright (c) 2026 Legacy Windows OpenJDK contributors.
 *
 * This code is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 only, as
 * published by the Free Software Foundation.  OpenJDK's Classpath Exception
 * applies when this file is linked into an OpenJDK launcher.
 *
 * Relocatable Minecraft launcher configuration for the XP/Vista JDK images.
 * The executable remains a normal OpenJDK launcher.  Before JLI creates the
 * VM, this translation unit appends the compatibility options to
 * _JAVA_OPTIONS so they are parsed after launcher-provided JVM options.
 *
 * No machine-wide state is changed.  The environment changes exist only in
 * this process and are inherited only by children that Minecraft may create.
 */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <stdlib.h>
#include <string.h>
#include <wchar.h>

extern "C" void* JLI_MemAlloc(size_t size);

#ifndef MINECRAFT_JAVA_MAJOR
#error MINECRAFT_JAVA_MAJOR must be 17, 21, or 25
#endif

#if MINECRAFT_JAVA_MAJOR == 17
#define MC_VERSION_W L"1.20.1"
#define MC_NATIVE_RELATIVE_W L"minecraft\\1.20.1\\natives-xp-x64"
#elif MINECRAFT_JAVA_MAJOR == 21
#define MC_VERSION_W L"1.21.1"
#define MC_NATIVE_RELATIVE_W L"minecraft\\1.21.1\\natives-xp-x64"
#elif MINECRAFT_JAVA_MAJOR == 25
#define MC_VERSION_W L"26.2"
#define MC_NATIVE_RELATIVE_W L"minecraft\\26.2\\natives-xp-x64"
#define MC_JTRACY_RELATIVE_W \
  L"minecraft\\26.2\\compat\\jtracy-1.0.37-natives-windows-xp.jar"
#else
#error Unsupported MINECRAFT_JAVA_MAJOR
#endif

// These imports force the DLLs into the process-loader startup set.  XP x64
// does not correctly allocate static TLS for affected DLLs first introduced
// later with LoadLibrary.  Java 17/21 need the minimal set; the certified
// Java 25 route needs the full LWJGL binding set as well.
extern "C" void* __cdecl alcOpenDevice(const char* device_name);
extern "C" int __cdecl glfwInit();

#if MINECRAFT_JAVA_MAJOR == 25
extern "C" void __cdecl Java_org_lwjgl_system_JNI_callBBBBV__BBBBJ();
extern "C" void __cdecl
    Java_org_lwjgl_opengl_AMDDebugOutput_nglDebugMessageCallbackAMD();
extern "C" void __cdecl Java_org_lwjgl_stb_LibSTB_setupMalloc();
extern "C" void __cdecl
    Java_org_lwjgl_util_tinyfd_TinyFileDialogs_ntinyfd_1colorChooser();
#endif

extern "C" void** minecraft_legacy_native_preload_anchor() {
  static void* imports[] = {
      reinterpret_cast<void*>(&alcOpenDevice),
      reinterpret_cast<void*>(&glfwInit),
      reinterpret_cast<void*>(&::wglGetProcAddress),
#if MINECRAFT_JAVA_MAJOR == 25
      reinterpret_cast<void*>(&Java_org_lwjgl_system_JNI_callBBBBV__BBBBJ),
      reinterpret_cast<void*>(
          &Java_org_lwjgl_opengl_AMDDebugOutput_nglDebugMessageCallbackAMD),
      reinterpret_cast<void*>(&Java_org_lwjgl_stb_LibSTB_setupMalloc),
      reinterpret_cast<void*>(
          &Java_org_lwjgl_util_tinyfd_TinyFileDialogs_ntinyfd_1colorChooser),
#endif
  };
  return imports;
}

namespace {

constexpr size_t kEnvironmentLimit = 32767;

bool append(wchar_t* destination, size_t capacity, const wchar_t* value) {
  const size_t used = wcslen(destination);
  const size_t incoming = wcslen(value);
  if (used + incoming + 1 > capacity) return false;
  memcpy(destination + used, value, (incoming + 1) * sizeof(wchar_t));
  return true;
}

bool parent_directory(wchar_t* path) {
  wchar_t* slash = wcsrchr(path, L'\\');
  if (slash == nullptr) slash = wcsrchr(path, L'/');
  if (slash == nullptr) return false;
  *slash = L'\0';
  return true;
}

bool join_path(wchar_t* output, size_t capacity, const wchar_t* left,
               const wchar_t* right) {
  output[0] = L'\0';
  return append(output, capacity, left) && append(output, capacity, L"\\") &&
         append(output, capacity, right);
}

void make_cache_directory(wchar_t* output, size_t capacity) {
  output[0] = L'\0';
  wchar_t temporary[MAX_PATH + 1] = {0};
  const DWORD length = GetTempPathW(MAX_PATH, temporary);
  if (length == 0 || length > MAX_PATH) return;
  if (!append(output, capacity, temporary) ||
      !append(output, capacity, L"LegacyOpenJDK-Minecraft")) {
    output[0] = L'\0';
    return;
  }
  CreateDirectoryW(output, nullptr);
  if (!append(output, capacity, L"\\" MC_VERSION_W)) {
    output[0] = L'\0';
    return;
  }
  CreateDirectoryW(output, nullptr);
}

char* to_ansi_argument(const wchar_t* value) {
  const int bytes = WideCharToMultiByte(CP_ACP, WC_NO_BEST_FIT_CHARS, value,
                                        -1, nullptr, 0, nullptr, nullptr);
  if (bytes <= 0) return nullptr;
  char* output = static_cast<char*>(JLI_MemAlloc(static_cast<size_t>(bytes)));
  if (WideCharToMultiByte(CP_ACP, WC_NO_BEST_FIT_CHARS, value, -1, output,
                          bytes, nullptr, nullptr) == 0) {
    return nullptr;
  }
  return output;
}

bool add_literal(char** options, int* count, int capacity,
                 const wchar_t* value) {
  if (*count >= capacity) return false;
  char* converted = to_ansi_argument(value);
  if (converted == nullptr) return false;
  options[(*count)++] = converted;
  return true;
}

bool add_property(char** options, int* count, int capacity,
                  const wchar_t* name, const wchar_t* value) {
  wchar_t argument[kEnvironmentLimit] = {0};
  if (!append(argument, kEnvironmentLimit, L"-D") ||
      !append(argument, kEnvironmentLimit, name) ||
      !append(argument, kEnvironmentLimit, L"=") ||
      !append(argument, kEnvironmentLimit, value)) {
    return false;
  }
  return add_literal(options, count, capacity, argument);
}

bool is_insertion_boundary(const char* argument) {
  return strcmp(argument, "-cp") == 0 ||
         strcmp(argument, "-classpath") == 0 ||
         strcmp(argument, "--class-path") == 0 ||
         strcmp(argument, "-jar") == 0 ||
         strcmp(argument, "-m") == 0 ||
         strcmp(argument, "--module") == 0 ||
         strcmp(argument, "-version") == 0 ||
         strcmp(argument, "--version") == 0 ||
         strcmp(argument, "-help") == 0 ||
         strcmp(argument, "--help") == 0 ||
         strcmp(argument, "-?") == 0;
}

void inject_minecraft_options(int* argc, char*** argv) {
  if (argc == nullptr || argv == nullptr || *argv == nullptr || *argc < 1) {
    return;
  }
  wchar_t disabled[2] = {0};
  if (GetEnvironmentVariableW(L"LEGACY_OPENJDK_DISABLE_MINECRAFT_OPTIONS",
                              disabled, 2) == 1 &&
      disabled[0] == L'1') {
    return;
  }

  wchar_t executable[kEnvironmentLimit] = {0};
  const DWORD executable_length =
      GetModuleFileNameW(nullptr, executable, kEnvironmentLimit);
  if (executable_length == 0 || executable_length >= kEnvironmentLimit) return;
  const bool software_renderer = wcsstr(executable, L"-software.exe") != nullptr;

  // The launcher is installed in <java.home>\bin.
  wchar_t bin[kEnvironmentLimit] = {0};
  memcpy(bin, executable, (executable_length + 1) * sizeof(wchar_t));
  if (!parent_directory(bin)) return;

  wchar_t java_home[kEnvironmentLimit] = {0};
  if (!append(java_home, kEnvironmentLimit, bin) ||
      !parent_directory(java_home)) {
    return;
  }

  wchar_t natives[kEnvironmentLimit] = {0};
  if (!join_path(natives, kEnvironmentLimit, java_home,
                 MC_NATIVE_RELATIVE_W)) {
    return;
  }

  wchar_t freetype[kEnvironmentLimit] = {0};
  if (!join_path(freetype, kEnvironmentLimit, natives, L"freetype.dll")) {
    return;
  }

  wchar_t cache[kEnvironmentLimit] = {0};
  make_cache_directory(cache, kEnvironmentLimit);
  if (cache[0] == L'\0') return;

  constexpr int kMaximumOptions = 24;
  char* options[kMaximumOptions] = {0};
  int option_count = 0;

#if MINECRAFT_JAVA_MAJOR == 25
  if (!add_literal(options, &option_count, kMaximumOptions, L"-Xshare:off") ||
      !add_property(options, &option_count, kMaximumOptions,
                    L"org.lwjgl.system.allocator", L"system") ||
      // LWJGL 3.4.1 finds its bundled native resources before consulting
      // org.lwjgl.librarypath.  Those stock DLLs target newer Windows and
      // fail on XP with ERROR_PROC_NOT_FOUND.  The built-in legacy mapper
      // deliberately makes the bundled resource lookup miss, after which
      // LWJGL uses the XP-compatible modules installed beside this launcher.
      !add_property(options, &option_count, kMaximumOptions,
                    L"org.lwjgl.system.bundledLibrary.pathMapper", L"legacy") ||
      !add_literal(options, &option_count, kMaximumOptions,
                   L"--sun-misc-unsafe-memory-access=allow") ||
      !add_literal(options, &option_count, kMaximumOptions,
                   L"--enable-native-access=ALL-UNNAMED")) {
    return;
  }
#endif

  if (software_renderer) {
#if !defined(MINECRAFT_SOFTWARE_ORIGINAL_MODULES)
    if (!add_property(options, &option_count, kMaximumOptions,
                      L"org.lwjgl.glfw.libname", L"glfw_mesa")) {
      return;
    }
#endif
    SetEnvironmentVariableW(L"GALLIUM_DRIVER", L"llvmpipe");
    _wputenv_s(L"GALLIUM_DRIVER", L"llvmpipe");
    SetEnvironmentVariableW(L"LIBGL_ALWAYS_SOFTWARE", L"true");
    _wputenv_s(L"LIBGL_ALWAYS_SOFTWARE", L"true");
  }

  if (!add_property(options, &option_count, kMaximumOptions,
                    L"org.lwjgl.librarypath", bin) ||
      !add_property(options, &option_count, kMaximumOptions,
                    L"jna.boot.library.path", bin) ||
      !add_property(options, &option_count, kMaximumOptions,
                    L"java.library.path", bin) ||
      !add_property(options, &option_count, kMaximumOptions,
                    L"jna.tmpdir", cache) ||
      !add_property(options, &option_count, kMaximumOptions,
                    L"org.lwjgl.system.SharedLibraryExtractPath", cache) ||
      !add_property(options, &option_count, kMaximumOptions,
                    L"io.netty.native.workdir", cache)) {
    return;
  }

#if MINECRAFT_JAVA_MAJOR >= 21
  if (!add_property(options, &option_count, kMaximumOptions,
                    L"org.lwjgl.freetype.libname", freetype) ||
      !add_property(options, &option_count, kMaximumOptions,
                    L"jna.nounpack", L"true")) {
    return;
  }
#endif

#if MINECRAFT_JAVA_MAJOR == 25
  wchar_t jtracy[kEnvironmentLimit] = {0};
  wchar_t bootclasspath[kEnvironmentLimit] = {0};
  if (!join_path(jtracy, kEnvironmentLimit, java_home,
                 MC_JTRACY_RELATIVE_W) ||
      !append(bootclasspath, kEnvironmentLimit, L"-Xbootclasspath/a:") ||
      !append(bootclasspath, kEnvironmentLimit, jtracy) ||
      !add_literal(options, &option_count, kMaximumOptions, bootclasspath)) {
    return;
  }
#endif

  if (!add_property(options, &option_count, kMaximumOptions,
                    L"legacy.windows.minecraft.wrapper", L"true")) {
    return;
  }

  SetEnvironmentVariableW(L"LEGACY_OPENJDK_MINECRAFT_NATIVES", natives);
  _wputenv_s(L"LEGACY_OPENJDK_MINECRAFT_NATIVES", natives);

  int insertion = *argc;
  for (int index = 1; index < *argc; ++index) {
    if (is_insertion_boundary((*argv)[index])) {
      insertion = index;
      break;
    }
  }

  char** rewritten = static_cast<char**>(JLI_MemAlloc(
      static_cast<size_t>(*argc + option_count + 1) * sizeof(char*)));
  int output = 0;
  for (int index = 0; index < insertion; ++index) {
    rewritten[output++] = (*argv)[index];
  }
  for (int index = 0; index < option_count; ++index) {
    rewritten[output++] = options[index];
  }
  for (int index = insertion; index < *argc; ++index) {
    rewritten[output++] = (*argv)[index];
  }
  rewritten[output] = nullptr;
  *argc = output;
  *argv = rewritten;
}

}  // namespace

extern "C" void minecraft_legacy_inject_options(int* argc, char*** argv) {
  inject_minecraft_options(argc, argv);
}
