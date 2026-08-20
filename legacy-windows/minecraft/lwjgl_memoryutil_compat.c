#define WINVER 0x0502
#define _WIN32_WINNT 0x0502
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

/*
 * LWJGL 3.4.2 added MemoryUtil.ngetPageSize().  Minecraft 26.3 Snapshot 9
 * calls it while initializing MemoryUtil, but the XP-compatible LWJGL 3.4.1
 * native does not export the corresponding JNI entry point.
 *
 * Keep this shim deliberately narrow: all pre-existing exports are forwarded
 * to the certified XP native, while the two observed 3.4.2 methods use APIs
 * supported by XP Professional x64 Edition. Further compatibility additions
 * must be driven by an observed failure, not added speculatively.
 */
int __stdcall lwjgl_memoryutil_get_page_size(void *jni_environment, void *java_class)
{
    SYSTEM_INFO system_info;

    UNREFERENCED_PARAMETER(jni_environment);
    UNREFERENCED_PARAMETER(java_class);

    GetSystemInfo(&system_info);
    return (int)system_info.dwPageSize;
}

int __stdcall lwjgl_memoryutil_get_cache_line_size(void *jni_environment, void *java_class)
{
    DWORD byte_size = 0;
    DWORD index;
    SYSTEM_LOGICAL_PROCESSOR_INFORMATION *buffer;
    int fallback = 0;

    UNREFERENCED_PARAMETER(jni_environment);
    UNREFERENCED_PARAMETER(java_class);

    /* Match LWJGL 3.4.2's Windows query. GetLogicalProcessorInformation is
     * natively available on Windows XP Professional x64 Edition. */
    if (GetLogicalProcessorInformation(NULL, &byte_size) ||
        GetLastError() != ERROR_INSUFFICIENT_BUFFER ||
        byte_size == 0) {
        return 0;
    }

    buffer = (SYSTEM_LOGICAL_PROCESSOR_INFORMATION *)HeapAlloc(
        GetProcessHeap(),
        0,
        byte_size
    );
    if (buffer == NULL) {
        return 0;
    }

    if (!GetLogicalProcessorInformation(buffer, &byte_size)) {
        HeapFree(GetProcessHeap(), 0, buffer);
        return 0;
    }

    for (index = 0;
         index < byte_size / sizeof(SYSTEM_LOGICAL_PROCESSOR_INFORMATION);
         index++) {
        CACHE_DESCRIPTOR cache;

        if (buffer[index].Relationship != RelationCache) {
            continue;
        }

        cache = buffer[index].Cache;
        if (cache.LineSize == 0) {
            continue;
        }

        if (cache.Level == 1 &&
            (cache.Type == CacheData || cache.Type == CacheUnified)) {
            int line_size = (int)cache.LineSize;
            HeapFree(GetProcessHeap(), 0, buffer);
            return line_size;
        }

        if (fallback == 0) {
            fallback = (int)cache.LineSize;
        }
    }

    HeapFree(GetProcessHeap(), 0, buffer);
    return fallback;
}
