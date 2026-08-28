#define WIN32_LEAN_AND_MEAN
#define _WIN32_WINNT 0x0502
#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <wchar.h>

/*
 * Start the real Minecraft Java launcher as a child process. This lets the
 * stable public entry point prepare process-local compatibility state before
 * Windows loads OpenAL and the rest of the native runtime in the child.
 *
 * The software renderer remains in a sibling directory with the original DLL
 * names (glfw.dll and opengl32.dll). The real Java launchers are kept in the
 * JDK's private executable directory. Users and third-party launchers select
 * only the stable public minecraft-java[w][-software].exe entry points.
 */

#define PRIVATE_EXECUTABLE_DIRECTORY \
    L"lib\\legacy-windows\\internal\\launcher\\executables"

#if defined(MINECRAFT_LAUNCHER_OLAUNCHER)
#define MINECRAFT_LAUNCHER_NAME L"olauncher"
#else
#define MINECRAFT_LAUNCHER_NAME L"multimc"
#endif

#if defined(MINECRAFT_VISTA_APPLICATION_COMPAT)
/*
 * Netty's Java-side Windows transport selection can stall local-channel
 * registration on Vista when Java reports 6.0. The JDK's native compatibility
 * layer still detects the real operating system and uses Vista exports where
 * they are available; this property only selects the proven application-level
 * compatibility path for Minecraft and its Java libraries.
 */
#define VISTA_APPLICATION_COMPAT_ARGUMENT L" -Dos.version=5.2"
#else
#define VISTA_APPLICATION_COMPAT_ARGUMENT L""
#endif

static const wchar_t *skip_program_name(const wchar_t *command_line) {
    int quoted = 0;

    while (*command_line == L' ' || *command_line == L'\t') {
        ++command_line;
    }
    while (*command_line != L'\0') {
        if (*command_line == L'"') {
            quoted = !quoted;
        } else if (!quoted && (*command_line == L' ' || *command_line == L'\t')) {
            break;
        }
        ++command_line;
    }
    return command_line;
}

static wchar_t ascii_lower(wchar_t value) {
    if (value >= L'A' && value <= L'Z') return value + (L'a' - L'A');
    return value;
}

static int contains_ignore_case(const wchar_t *value, const wchar_t *needle) {
    const wchar_t *candidate;
    if (value == NULL || needle == NULL || *needle == L'\0') return 0;
    for (candidate = value; *candidate != L'\0'; ++candidate) {
        const wchar_t *left = candidate;
        const wchar_t *right = needle;
        while (*right != L'\0' && *left != L'\0' &&
               ascii_lower(*left) == ascii_lower(*right)) {
            ++left;
            ++right;
        }
        if (*right == L'\0') return 1;
    }
    return 0;
}

enum minecraft_dispatch_profile {
    MINECRAFT_DISPATCH_UNKNOWN = 0,
    MINECRAFT_DISPATCH_120 = 120,
    MINECRAFT_DISPATCH_1202 = 1202,
    MINECRAFT_DISPATCH_121 = 121,
    MINECRAFT_DISPATCH_12111 = 12111,
    MINECRAFT_DISPATCH_26 = 260
};

static enum minecraft_dispatch_profile detect_profile_text(
        const wchar_t *arguments) {
    /* Test exact ABI boundaries before their broader release families. */
    if (contains_ignore_case(arguments, L"\\versions\\1.20.2") ||
        contains_ignore_case(arguments, L"/versions/1.20.2") ||
        contains_ignore_case(arguments, L"\\minecraft\\1.20.2") ||
        contains_ignore_case(arguments, L"/minecraft/1.20.2") ||
        contains_ignore_case(arguments,
                             L"-Dlegacy.windows.minecraft.version=1.20.2") ||
        contains_ignore_case(arguments, L"--version 1.20.2") ||
        contains_ignore_case(arguments, L"--version=1.20.2") ||
        contains_ignore_case(arguments, L"--version \"1.20.2")) {
        return MINECRAFT_DISPATCH_1202;
    }
    if (contains_ignore_case(arguments, L"\\versions\\1.21.11") ||
        contains_ignore_case(arguments, L"/versions/1.21.11") ||
        contains_ignore_case(arguments, L"\\minecraft\\1.21.11") ||
        contains_ignore_case(arguments, L"/minecraft/1.21.11") ||
        contains_ignore_case(arguments,
                             L"-Dlegacy.windows.minecraft.version=1.21.11") ||
        contains_ignore_case(arguments, L"--version 1.21.11") ||
        contains_ignore_case(arguments, L"--version=1.21.11") ||
        contains_ignore_case(arguments, L"--version \"1.21.11")) {
        return MINECRAFT_DISPATCH_12111;
    }
    if (contains_ignore_case(arguments, L"\\versions\\1.20") ||
        contains_ignore_case(arguments, L"/versions/1.20") ||
        contains_ignore_case(arguments, L"\\minecraft\\1.20") ||
        contains_ignore_case(arguments, L"/minecraft/1.20") ||
        contains_ignore_case(arguments,
                             L"-Dlegacy.windows.minecraft.version=1.20") ||
        contains_ignore_case(arguments, L"--version 1.20") ||
        contains_ignore_case(arguments, L"--version=1.20") ||
        contains_ignore_case(arguments, L"--version \"1.20")) {
        return MINECRAFT_DISPATCH_120;
    }
    if (contains_ignore_case(arguments, L"\\versions\\1.21") ||
        contains_ignore_case(arguments, L"/versions/1.21") ||
        contains_ignore_case(arguments, L"\\minecraft\\1.21") ||
        contains_ignore_case(arguments, L"/minecraft/1.21") ||
        contains_ignore_case(arguments,
                             L"-Dlegacy.windows.minecraft.version=1.21") ||
        contains_ignore_case(arguments, L"--version 1.21") ||
        contains_ignore_case(arguments, L"--version=1.21") ||
        contains_ignore_case(arguments, L"--version \"1.21")) {
        return MINECRAFT_DISPATCH_121;
    }
    if (contains_ignore_case(arguments, L"\\versions\\26") ||
        contains_ignore_case(arguments, L"/versions/26") ||
        contains_ignore_case(arguments, L"\\minecraft\\26") ||
        contains_ignore_case(arguments, L"/minecraft/26") ||
        contains_ignore_case(arguments,
                             L"-Dlegacy.windows.minecraft.version=26") ||
        contains_ignore_case(arguments, L"--version 26") ||
        contains_ignore_case(arguments, L"--version=26") ||
        contains_ignore_case(arguments, L"--version \"26")) {
        return MINECRAFT_DISPATCH_26;
    }
    return MINECRAFT_DISPATCH_UNKNOWN;
}

static const wchar_t *profile_runtime_directory(
        enum minecraft_dispatch_profile profile) {
    switch (profile) {
        case MINECRAFT_DISPATCH_120:
            return L"1.20";
        case MINECRAFT_DISPATCH_1202:
            return L"1.20.2";
        case MINECRAFT_DISPATCH_121:
            return L"1.21";
        case MINECRAFT_DISPATCH_12111:
            return L"1.21.11";
        default:
            return NULL;
    }
}

static enum minecraft_dispatch_profile detect_profile_argfiles(
        const wchar_t *arguments) {
    const wchar_t *cursor = arguments;
    while (cursor != NULL && *cursor != L'\0') {
        wchar_t path[32768];
        const wchar_t *marker;
        const wchar_t *start;
        const wchar_t *end;
        int quoted = 0;
        size_t path_length;
        HANDLE file;
        DWORD size;
        DWORD read = 0;
        char *bytes;
        wchar_t *wide = NULL;
        enum minecraft_dispatch_profile profile = MINECRAFT_DISPATCH_UNKNOWN;

        while (*cursor != L'\0' && *cursor != L'@') ++cursor;
        if (*cursor == L'\0') break;
        marker = cursor;
        ++cursor;
        if (*cursor == L'@') {
            ++cursor;
            continue;
        }
        if (*cursor == L'\"') {
            quoted = 1;
            ++cursor;
        } else if (marker > arguments && marker[-1] == L'\"') {
            /* Windows commonly renders a quoted argfile as "@C:\\...". */
            quoted = 1;
        }
        start = cursor;
        if (quoted) {
            while (*cursor != L'\0' && *cursor != L'\"') ++cursor;
        } else {
            while (*cursor != L'\0' && *cursor != L' ' &&
                   *cursor != L'\t') ++cursor;
        }
        end = cursor;
        path_length = (size_t)(end - start);
        if (path_length == 0 || path_length + 1 > sizeof(path) / sizeof(path[0])) {
            if (*cursor != L'\0') ++cursor;
            continue;
        }
        memcpy(path, start, path_length * sizeof(wchar_t));
        path[path_length] = L'\0';

        file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
                           NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
        if (file == INVALID_HANDLE_VALUE) {
            if (*cursor != L'\0') ++cursor;
            continue;
        }
        size = GetFileSize(file, NULL);
        if (size == INVALID_FILE_SIZE || size == 0 || size > 4 * 1024 * 1024) {
            CloseHandle(file);
            if (*cursor != L'\0') ++cursor;
            continue;
        }
        bytes = (char *)HeapAlloc(GetProcessHeap(), 0, (size_t)size + 2);
        if (bytes == NULL) {
            CloseHandle(file);
            return MINECRAFT_DISPATCH_UNKNOWN;
        }
        if (ReadFile(file, bytes, size, &read, NULL) && read == size) {
            int wide_length;
            bytes[size] = '\0';
            bytes[size + 1] = '\0';
            if (size >= 2 && (unsigned char)bytes[0] == 0xff &&
                (unsigned char)bytes[1] == 0xfe) {
                wide_length = (int)((size - 2) / sizeof(wchar_t));
                wide = (wchar_t *)HeapAlloc(
                    GetProcessHeap(), HEAP_ZERO_MEMORY,
                    ((size_t)wide_length + 1) * sizeof(wchar_t));
                if (wide != NULL) {
                    memcpy(wide, bytes + 2,
                           (size_t)wide_length * sizeof(wchar_t));
                }
            } else {
                wide_length = MultiByteToWideChar(CP_UTF8, 0, bytes, (int)size,
                                                   NULL, 0);
                if (wide_length == 0) {
                    wide_length = MultiByteToWideChar(CP_ACP, 0, bytes,
                                                       (int)size, NULL, 0);
                }
                if (wide_length > 0) {
                    wide = (wchar_t *)HeapAlloc(
                        GetProcessHeap(), HEAP_ZERO_MEMORY,
                        ((size_t)wide_length + 1) * sizeof(wchar_t));
                    if (wide != NULL) {
                        if (MultiByteToWideChar(CP_UTF8, 0, bytes, (int)size,
                                                wide, wide_length) == 0) {
                            MultiByteToWideChar(CP_ACP, 0, bytes, (int)size,
                                                wide, wide_length);
                        }
                    }
                }
            }
            if (wide != NULL) profile = detect_profile_text(wide);
        }
        CloseHandle(file);
        HeapFree(GetProcessHeap(), 0, bytes);
        if (wide != NULL) HeapFree(GetProcessHeap(), 0, wide);
        if (profile != MINECRAFT_DISPATCH_UNKNOWN) return profile;
        if (*cursor != L'\0') ++cursor;
    }
    return MINECRAFT_DISPATCH_UNKNOWN;
}

static int show_failure(int graphical, const wchar_t *operation, DWORD error) {
    wchar_t message[512];
    _snwprintf(message, sizeof(message) / sizeof(message[0]) - 1,
               L"%s failed (Windows error %lu).", operation,
               (unsigned long)error);
    message[(sizeof(message) / sizeof(message[0])) - 1] = L'\0';
    if (graphical) {
        MessageBoxW(NULL, message, L"Legacy OpenJDK Minecraft launcher",
                    MB_OK | MB_ICONERROR);
    } else {
        fwprintf(stderr, L"%s\n", message);
    }
    return error == 0 ? 1 : (int)error;
}

static int prepend_process_path(const wchar_t *directory) {
    DWORD existing_length;
    wchar_t *existing = NULL;
    wchar_t *updated;
    size_t directory_length = wcslen(directory);
    size_t capacity;
    int result = 0;

    SetLastError(ERROR_SUCCESS);
    existing_length = GetEnvironmentVariableW(L"PATH", NULL, 0);
    if (existing_length == 0 && GetLastError() != ERROR_ENVVAR_NOT_FOUND &&
        GetLastError() != ERROR_SUCCESS) {
        return 0;
    }
    if (existing_length != 0) {
        existing = (wchar_t *)HeapAlloc(GetProcessHeap(), 0,
                                        existing_length * sizeof(wchar_t));
        if (existing == NULL) return 0;
        if (GetEnvironmentVariableW(L"PATH", existing, existing_length) == 0) {
            HeapFree(GetProcessHeap(), 0, existing);
            return 0;
        }
    }

    capacity = directory_length + (existing_length != 0 ? existing_length + 1 : 1);
    updated = (wchar_t *)HeapAlloc(GetProcessHeap(), 0, capacity * sizeof(wchar_t));
    if (updated != NULL) {
        memcpy(updated, directory, directory_length * sizeof(wchar_t));
        if (existing_length != 0) {
            updated[directory_length] = L';';
            memcpy(updated + directory_length + 1, existing,
                   existing_length * sizeof(wchar_t));
        } else {
            updated[directory_length] = L'\0';
        }
        result = SetEnvironmentVariableW(L"PATH", updated) != 0;
        HeapFree(GetProcessHeap(), 0, updated);
    }
    if (existing != NULL) HeapFree(GetProcessHeap(), 0, existing);
    return result;
}

static int regular_file_exists(const wchar_t *path) {
    DWORD attributes = GetFileAttributesW(path);
    return attributes != INVALID_FILE_ATTRIBUTES &&
           (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

static int parent_directory(wchar_t *path) {
    wchar_t *slash = wcsrchr(path, L'\\');
    if (slash == NULL) slash = wcsrchr(path, L'/');
    if (slash == NULL || slash == path) return 0;
    *slash = L'\0';
    return 1;
}

/* Walk upward until the private runtime proves which directory is the JDK root. */
static int find_jdk_root(const wchar_t *executable, wchar_t *jdk_root,
                         size_t capacity) {
    wchar_t candidate[32768];
    wchar_t probe[32768];
    size_t length = wcslen(executable);
    unsigned int depth;

    if (length + 1 > capacity) return 0;
    memcpy(candidate, executable, (length + 1) * sizeof(wchar_t));
    if (!parent_directory(candidate)) return 0;

    for (depth = 0; depth < 8; ++depth) {
        _snwprintf(probe, sizeof(probe) / sizeof(probe[0]) - 1,
                   L"%s\\" PRIVATE_EXECUTABLE_DIRECTORY
                   L"\\minecraft-javaw-runtime.exe", candidate);
        probe[(sizeof(probe) / sizeof(probe[0])) - 1] = L'\0';
        if (regular_file_exists(probe)) {
            length = wcslen(candidate);
            if (length + 1 > capacity) return 0;
            memcpy(jdk_root, candidate, (length + 1) * sizeof(wchar_t));
            return 1;
        }
        if (!parent_directory(candidate)) break;
    }
    return 0;
}

static int run_minecraft_launcher(int graphical) {
    wchar_t module_path[32768];
    wchar_t bin_path[32768];
    wchar_t target_path[32768];
    wchar_t openal_config_path[32768];
    wchar_t *command_line;
    const wchar_t *arguments;
    size_t target_length;
    size_t compatibility_length;
    size_t arguments_length;
    STARTUPINFOW startup;
    PROCESS_INFORMATION process;
    DWORD exit_code = 1;
    DWORD length;
    enum minecraft_dispatch_profile profile;
    const wchar_t *profile_name;
    const wchar_t *runtime_directory;

    length = GetModuleFileNameW(NULL, module_path,
                                (DWORD)(sizeof(module_path) / sizeof(module_path[0])));
    if (length == 0 || length >= (DWORD)(sizeof(module_path) / sizeof(module_path[0]))) {
        return show_failure(graphical, L"Locating the installed JDK", GetLastError());
    }
    if (!find_jdk_root(module_path, module_path,
                       sizeof(module_path) / sizeof(module_path[0]))) {
        return show_failure(graphical, L"Resolving the installed JDK directory",
                            ERROR_BAD_PATHNAME);
    }
    _snwprintf(bin_path, sizeof(bin_path) / sizeof(bin_path[0]) - 1,
               L"%s\\bin", module_path);
    bin_path[(sizeof(bin_path) / sizeof(bin_path[0])) - 1] = L'\0';
    if (!prepend_process_path(bin_path)) {
        return show_failure(graphical, L"Preparing the private JDK search path",
                            GetLastError());
    }

    _snwprintf(openal_config_path,
               sizeof(openal_config_path) / sizeof(openal_config_path[0]) - 1,
               L"%s\\minecraft\\26.2\\compat\\alsoft-xp.ini", module_path);
    openal_config_path[(sizeof(openal_config_path) /
                        sizeof(openal_config_path[0])) - 1] = L'\0';
    if (GetFileAttributesW(openal_config_path) == INVALID_FILE_ATTRIBUTES) {
        return show_failure(graphical, L"Locating the XP OpenAL configuration",
                            GetLastError());
    }
    SetLastError(ERROR_SUCCESS);
    if (GetEnvironmentVariableW(L"ALSOFT_CONF", NULL, 0) == 0 &&
        GetLastError() == ERROR_ENVVAR_NOT_FOUND &&
        !SetEnvironmentVariableW(L"ALSOFT_CONF", openal_config_path)) {
        return show_failure(graphical, L"Preparing the XP OpenAL configuration",
                            GetLastError());
    }
    arguments = skip_program_name(GetCommandLineW());
    profile = detect_profile_text(arguments);
    if (profile == MINECRAFT_DISPATCH_UNKNOWN) {
        profile = detect_profile_argfiles(arguments);
    }
    /* Preserve the original public entry point's Minecraft 26 fallback. */
    if (profile == MINECRAFT_DISPATCH_UNKNOWN) {
        profile = MINECRAFT_DISPATCH_26;
    }
    if (profile == MINECRAFT_DISPATCH_120) {
        profile_name = L"1.20";
    } else if (profile == MINECRAFT_DISPATCH_1202) {
        profile_name = L"1.20.2";
    } else if (profile == MINECRAFT_DISPATCH_121) {
        profile_name = L"1.21";
    } else if (profile == MINECRAFT_DISPATCH_12111) {
        profile_name = L"1.21.11";
    } else {
        profile_name = L"26";
    }
    runtime_directory = profile_runtime_directory(profile);
    if (!SetEnvironmentVariableW(L"LEGACY_OPENJDK_MINECRAFT_PROFILE",
                                 profile_name)) {
        return show_failure(graphical, L"Selecting the Minecraft version profile",
                            GetLastError());
    }
    if (!SetEnvironmentVariableW(L"LEGACY_OPENJDK_MINECRAFT_LAUNCHER",
                                 MINECRAFT_LAUNCHER_NAME)) {
        return show_failure(graphical, L"Selecting the launcher profile",
                            GetLastError());
    }

#if defined(MINECRAFT_DISPATCH_HARDWARE) && defined(MINECRAFT_DISPATCH_WINDOWS)
    if (runtime_directory != NULL) {
        _snwprintf(target_path, sizeof(target_path) / sizeof(target_path[0]) - 1,
                   L"%s\\" PRIVATE_EXECUTABLE_DIRECTORY
                   L"\\%s\\minecraft-javaw-runtime.exe", module_path,
                   runtime_directory);
    } else {
        _snwprintf(target_path, sizeof(target_path) / sizeof(target_path[0]) - 1,
                   L"%s\\" PRIVATE_EXECUTABLE_DIRECTORY
                   L"\\minecraft-javaw-runtime.exe", module_path);
    }
#elif defined(MINECRAFT_DISPATCH_HARDWARE)
    if (runtime_directory != NULL) {
        _snwprintf(target_path, sizeof(target_path) / sizeof(target_path[0]) - 1,
                   L"%s\\" PRIVATE_EXECUTABLE_DIRECTORY
                   L"\\%s\\minecraft-java-runtime.exe", module_path,
                   runtime_directory);
    } else {
        _snwprintf(target_path, sizeof(target_path) / sizeof(target_path[0]) - 1,
                   L"%s\\" PRIVATE_EXECUTABLE_DIRECTORY
                   L"\\minecraft-java-runtime.exe", module_path);
    }
#elif defined(MINECRAFT_DISPATCH_WINDOWS)
    if (runtime_directory != NULL) {
        _snwprintf(target_path, sizeof(target_path) / sizeof(target_path[0]) - 1,
                   L"%s\\" PRIVATE_EXECUTABLE_DIRECTORY
                   L"\\%s\\software\\minecraft-javaw-software.exe",
                   module_path, runtime_directory);
    } else {
        _snwprintf(target_path, sizeof(target_path) / sizeof(target_path[0]) - 1,
                   L"%s\\" PRIVATE_EXECUTABLE_DIRECTORY
                   L"\\software\\minecraft-javaw-software.exe", module_path);
    }
#else
    if (runtime_directory != NULL) {
        _snwprintf(target_path, sizeof(target_path) / sizeof(target_path[0]) - 1,
                   L"%s\\" PRIVATE_EXECUTABLE_DIRECTORY
                   L"\\%s\\software\\minecraft-java-software.exe",
                   module_path, runtime_directory);
    } else {
        _snwprintf(target_path, sizeof(target_path) / sizeof(target_path[0]) - 1,
                   L"%s\\" PRIVATE_EXECUTABLE_DIRECTORY
                   L"\\software\\minecraft-java-software.exe", module_path);
    }
#endif
    target_path[(sizeof(target_path) / sizeof(target_path[0])) - 1] = L'\0';

    target_length = wcslen(target_path);
    compatibility_length = wcslen(VISTA_APPLICATION_COMPAT_ARGUMENT);
    arguments_length = wcslen(arguments);
    command_line = (wchar_t *)HeapAlloc(GetProcessHeap(), 0,
        (target_length + compatibility_length + arguments_length + 4) *
            sizeof(wchar_t));
    if (command_line == NULL) {
        return show_failure(graphical, L"Allocating the launch command", ERROR_NOT_ENOUGH_MEMORY);
    }
    command_line[0] = L'"';
    memcpy(command_line + 1, target_path, target_length * sizeof(wchar_t));
    command_line[target_length + 1] = L'"';
    memcpy(command_line + target_length + 2,
           VISTA_APPLICATION_COMPAT_ARGUMENT,
           compatibility_length * sizeof(wchar_t));
    memcpy(command_line + target_length + compatibility_length + 2, arguments,
           (arguments_length + 1) * sizeof(wchar_t));

    ZeroMemory(&startup, sizeof(startup));
    startup.cb = sizeof(startup);
    ZeroMemory(&process, sizeof(process));
    if (!CreateProcessW(target_path, command_line, NULL, NULL, TRUE, 0, NULL, NULL,
                        &startup, &process)) {
        DWORD error = GetLastError();
        HeapFree(GetProcessHeap(), 0, command_line);
        return show_failure(graphical, L"Starting the Minecraft Java runtime", error);
    }
    HeapFree(GetProcessHeap(), 0, command_line);
    CloseHandle(process.hThread);
    if (WaitForSingleObject(process.hProcess, INFINITE) != WAIT_OBJECT_0) {
        DWORD error = GetLastError();
        CloseHandle(process.hProcess);
        return show_failure(graphical, L"Waiting for the Java runtime", error);
    }
    if (!GetExitCodeProcess(process.hProcess, &exit_code)) {
        DWORD error = GetLastError();
        CloseHandle(process.hProcess);
        return show_failure(graphical, L"Reading the Java exit status", error);
    }
    CloseHandle(process.hProcess);
    return (int)exit_code;
}

#ifdef MINECRAFT_DISPATCH_WINDOWS
int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous, wchar_t *command_line, int show) {
    (void)instance;
    (void)previous;
    (void)command_line;
    (void)show;
    return run_minecraft_launcher(1);
}
#else
int wmain(void) {
    return run_minecraft_launcher(0);
}
#endif
