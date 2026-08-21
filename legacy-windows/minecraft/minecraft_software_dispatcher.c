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
 * names (glfw.dll and opengl32.dll). The hardware runtime remains in bin under
 * a private name. Users and third-party launchers select only the stable public
 * minecraft-java[w][-software].exe entry points.
 */

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

static int run_minecraft_launcher(int graphical) {
    wchar_t module_path[32768];
    wchar_t bin_path[32768];
    wchar_t target_path[32768];
    wchar_t openal_config_path[32768];
    wchar_t *slash;
    wchar_t *command_line;
    const wchar_t *arguments;
    size_t target_length;
    size_t arguments_length;
    STARTUPINFOW startup;
    PROCESS_INFORMATION process;
    DWORD exit_code = 1;
    DWORD length;

    length = GetModuleFileNameW(NULL, module_path,
                                (DWORD)(sizeof(module_path) / sizeof(module_path[0])));
    if (length == 0 || length >= (DWORD)(sizeof(module_path) / sizeof(module_path[0]))) {
        return show_failure(graphical, L"Locating the installed JDK", GetLastError());
    }
    slash = wcsrchr(module_path, L'\\');
    if (slash == NULL) {
        return show_failure(graphical, L"Resolving the installed JDK directory",
                            ERROR_BAD_PATHNAME);
    }
    *slash = L'\0';
    memcpy(bin_path, module_path, (wcslen(module_path) + 1) * sizeof(wchar_t));
    slash = wcsrchr(module_path, L'\\');
    if (slash == NULL) {
        return show_failure(graphical, L"Resolving the installed JDK directory",
                            ERROR_BAD_PATHNAME);
    }
    *slash = L'\0';
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

#if defined(MINECRAFT_DISPATCH_HARDWARE) && defined(MINECRAFT_DISPATCH_WINDOWS)
    _snwprintf(target_path, sizeof(target_path) / sizeof(target_path[0]) - 1,
               L"%s\\bin\\minecraft-javaw-runtime.exe", module_path);
#elif defined(MINECRAFT_DISPATCH_HARDWARE)
    _snwprintf(target_path, sizeof(target_path) / sizeof(target_path[0]) - 1,
               L"%s\\bin\\minecraft-java-runtime.exe", module_path);
#elif defined(MINECRAFT_DISPATCH_WINDOWS)
    _snwprintf(target_path, sizeof(target_path) / sizeof(target_path[0]) - 1,
               L"%s\\minecraft-software\\minecraft-javaw-software.exe", module_path);
#else
    _snwprintf(target_path, sizeof(target_path) / sizeof(target_path[0]) - 1,
               L"%s\\minecraft-software\\minecraft-java-software.exe", module_path);
#endif
    target_path[(sizeof(target_path) / sizeof(target_path[0])) - 1] = L'\0';

    arguments = skip_program_name(GetCommandLineW());
    target_length = wcslen(target_path);
    arguments_length = wcslen(arguments);
    command_line = (wchar_t *)HeapAlloc(GetProcessHeap(), 0,
        (target_length + arguments_length + 4) * sizeof(wchar_t));
    if (command_line == NULL) {
        return show_failure(graphical, L"Allocating the launch command", ERROR_NOT_ENOUGH_MEMORY);
    }
    command_line[0] = L'"';
    memcpy(command_line + 1, target_path, target_length * sizeof(wchar_t));
    command_line[target_length + 1] = L'"';
    memcpy(command_line + target_length + 2, arguments,
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
