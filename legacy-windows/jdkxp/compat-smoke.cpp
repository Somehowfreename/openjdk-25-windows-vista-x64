#define WIN32_LEAN_AND_MEAN
#define _WIN32_WINNT 0x0602
#include <windows.h>
#include <stdio.h>

int fail(int code) {
  printf("jdkxp compatibility smoke failed at check %d (Win32 error %lu)\n",
         code, static_cast<unsigned long>(GetLastError()));
  return code;
}

struct SharedState {
  SRWLOCK lock;
  CONDITION_VARIABLE condition;
  bool ready;
};

DWORD WINAPI signal_thread(void* parameter) {
  SharedState* state = static_cast<SharedState*>(parameter);
  Sleep(25);
  AcquireSRWLockExclusive(&state->lock);
  state->ready = true;
  WakeConditionVariable(&state->condition);
  ReleaseSRWLockExclusive(&state->lock);
  return 0;
}

BOOL CALLBACK initialize_once(PINIT_ONCE, PVOID parameter, PVOID*) {
  InterlockedIncrement(static_cast<volatile LONG*>(parameter));
  return TRUE;
}

int main() {
  printf("jdkxp compatibility smoke on Windows %lu.%lu\n",
         static_cast<unsigned long>(LOBYTE(LOWORD(GetVersion()))),
         static_cast<unsigned long>(HIBYTE(LOWORD(GetVersion()))));

  if (GetTickCount64() == 0) return fail(10);
  printf("  timing passed\n");

  SharedState state = {};
  InitializeSRWLock(&state.lock);
  InitializeConditionVariable(&state.condition);
  if (!TryAcquireSRWLockExclusive(&state.lock)) return fail(11);
  ReleaseSRWLockExclusive(&state.lock);
  if (!TryAcquireSRWLockShared(&state.lock)) return fail(12);
  ReleaseSRWLockShared(&state.lock);
  printf("  SRW try-acquire family passed\n");
  HANDLE thread = CreateThread(nullptr, 0, signal_thread, &state, 0, nullptr);
  if (thread == nullptr) return fail(13);
  AcquireSRWLockExclusive(&state.lock);
  while (!state.ready) {
    if (!SleepConditionVariableSRW(&state.condition, &state.lock, 2000, 0)) {
      ReleaseSRWLockExclusive(&state.lock);
      return fail(14);
    }
  }
  ReleaseSRWLockExclusive(&state.lock);
  WaitForSingleObject(thread, INFINITE);
  CloseHandle(thread);
  printf("  synchronization passed\n");

  INIT_ONCE once = INIT_ONCE_STATIC_INIT;
  volatile LONG initialization_count = 0;
  if (!InitOnceExecuteOnce(&once, initialize_once,
                           const_cast<LONG*>(&initialization_count), nullptr) ||
      !InitOnceExecuteOnce(&once, initialize_once,
                           const_cast<LONG*>(&initialization_count), nullptr) ||
      initialization_count != 1) {
    return fail(15);
  }
  printf("  one-time initialization passed\n");

  WCHAR image[MAX_PATH] = {};
  DWORD image_chars = MAX_PATH;
  if (!QueryFullProcessImageNameW(GetCurrentProcess(), 0, image, &image_chars)) {
    return fail(16);
  }
  HANDLE file = CreateFileW(image, FILE_READ_ATTRIBUTES,
                            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                            nullptr, OPEN_EXISTING, 0, nullptr);
  if (file == INVALID_HANDLE_VALUE) return fail(17);
  WCHAR final_path[1024] = {};
  DWORD final_chars = GetFinalPathNameByHandleW(file, final_path, 1024, 0);
  CloseHandle(file);
  if (final_chars == 0 || final_chars >= 1024) return fail(18);
  printf("  process and path queries passed\n");

  HANDLE port = CreateIoCompletionPort(INVALID_HANDLE_VALUE, nullptr, 0, 1);
  if (port == nullptr) return fail(19);
  if (!PostQueuedCompletionStatus(port, 123, 456, nullptr)) return fail(20);
  OVERLAPPED_ENTRY entry = {};
  ULONG removed = 0;
  if (!GetQueuedCompletionStatusEx(port, &entry, 1, &removed, 1000, FALSE) ||
      removed != 1 || entry.dwNumberOfBytesTransferred != 123 ||
      entry.lpCompletionKey != 456) {
    CloseHandle(port);
    return fail(21);
  }
  CloseHandle(port);
  printf("  completion-port compatibility passed\n");

  DYNAMIC_TIME_ZONE_INFORMATION timezone = {};
  if (GetDynamicTimeZoneInformation(&timezone) == TIME_ZONE_ID_INVALID) return fail(22);
  if (GetActiveProcessorCount(0xffff) == 0) return fail(23);

  printf("jdkxp compatibility smoke passed: %ls\n", final_path);
  return 0;
}
