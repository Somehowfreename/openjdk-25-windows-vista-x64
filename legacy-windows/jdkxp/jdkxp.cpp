#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#define _WIN32_WINNT 0x0502
#define NTDDI_VERSION 0x05020100

#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <iphlpapi.h>
#include <icmpapi.h>
#include <netioapi.h>
#include <psapi.h>
#include <stdint.h>
#include <stddef.h>
#include <wchar.h>

// JDKXP is a process-local Kernel32 compatibility proxy.  JDK binaries are
// post-linked to import Kernel32 functions through this DLL.  Functions that
// exist as a complete, representation-compatible family on the running OS are
// dispatched to the native implementation.  XP/Server 2003 use the fallbacks
// below.  Vista also uses the SRW/condition-variable fallbacks because it has
// the original SRW API but not the TryAcquireSRWLock* additions introduced in
// Windows 7; mixing native and fallback operations on one opaque lock corrupts
// its representation.

namespace {

template <typename T>
T kernel_proc(const char* name) {
  return reinterpret_cast<T>(GetProcAddress(GetModuleHandleW(L"kernel32.dll"), name));
}

template <typename T>
T ntdll_proc(const char* name) {
  return reinterpret_cast<T>(GetProcAddress(GetModuleHandleW(L"ntdll.dll"), name));
}

HMODULE iphlpapi_module() {
  static HMODULE module = LoadLibraryW(L"iphlpapi.dll");
  return module;
}

template <typename T>
T iphlpapi_proc(const char* name) {
  HMODULE module = iphlpapi_module();
  return module == nullptr
             ? nullptr
             : reinterpret_cast<T>(GetProcAddress(module, name));
}

typedef ULONG(WINAPI* GetAdaptersAddressesFn)(
    ULONG, ULONG, PVOID, PIP_ADAPTER_ADDRESSES, PULONG);

DWORD load_xp_adapters(ULONG family, PIP_ADAPTER_ADDRESSES* adapters) {
  if (adapters == nullptr) return ERROR_INVALID_PARAMETER;
  *adapters = nullptr;
  GetAdaptersAddressesFn get_adapters =
      iphlpapi_proc<GetAdaptersAddressesFn>("GetAdaptersAddresses");
  if (get_adapters == nullptr) return ERROR_CALL_NOT_IMPLEMENTED;

  ULONG size = 16 * 1024;
  PIP_ADAPTER_ADDRESSES buffer = static_cast<PIP_ADAPTER_ADDRESSES>(
      HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, size));
  if (buffer == nullptr) return ERROR_NOT_ENOUGH_MEMORY;

  const ULONG flags = GAA_FLAG_INCLUDE_PREFIX | GAA_FLAG_SKIP_DNS_SERVER |
                      GAA_FLAG_SKIP_MULTICAST;
  DWORD result = get_adapters(family, flags, nullptr, buffer, &size);
  if (result == ERROR_BUFFER_OVERFLOW) {
    HeapFree(GetProcessHeap(), 0, buffer);
    buffer = static_cast<PIP_ADAPTER_ADDRESSES>(
        HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, size));
    if (buffer == nullptr) return ERROR_NOT_ENOUGH_MEMORY;
    result = get_adapters(family, flags, nullptr, buffer, &size);
  }
  if (result != NO_ERROR) {
    HeapFree(GetProcessHeap(), 0, buffer);
    return result;
  }
  *adapters = buffer;
  return NO_ERROR;
}

ULONG adapter_index(const IP_ADAPTER_ADDRESSES* adapter) {
  return adapter->IfIndex != 0 ? adapter->IfIndex : adapter->Ipv6IfIndex;
}

NET_LUID adapter_luid(const IP_ADAPTER_ADDRESSES* adapter) {
  NET_LUID luid = {};
  const ULONG index = adapter_index(adapter) & 0x00ffffffUL;
  const ULONG type = adapter->IfType & 0x0000ffffUL;
  luid.Value = (static_cast<ULONG64>(type) << 48) |
               (static_cast<ULONG64>(index) << 24);
  return luid;
}

ULONG luid_index(const NET_LUID* luid) {
  return luid == nullptr
             ? 0
             : static_cast<ULONG>((luid->Value >> 24) & 0x00ffffffULL);
}

void interface_name(ULONG index, PWSTR name, SIZE_T length) {
  if (name == nullptr || length == 0) return;
  WCHAR digits[16] = {};
  SIZE_T count = 0;
  do {
    digits[count++] = static_cast<WCHAR>(L'0' + (index % 10));
    index /= 10;
  } while (index != 0 && count < ARRAYSIZE(digits));

  SIZE_T output = 0;
  if (output + 1 < length) name[output++] = L'i';
  if (output + 1 < length) name[output++] = L'f';
  while (count != 0 && output + 1 < length) {
    name[output++] = digits[--count];
  }
  name[output] = L'\0';
}

bool parse_interface_name(PCWSTR name, ULONG* index) {
  if (name == nullptr || index == nullptr || name[0] != L'i' ||
      name[1] != L'f' || name[2] < L'0' || name[2] > L'9') {
    return false;
  }
  ULONG value = 0;
  for (SIZE_T position = 2; name[position] != L'\0'; ++position) {
    if (name[position] < L'0' || name[position] > L'9') return false;
    const ULONG digit = static_cast<ULONG>(name[position] - L'0');
    if (value > (0xffffffffUL - digit) / 10) return false;
    value = value * 10 + digit;
  }
  *index = value;
  return value != 0;
}

bool address_family_matches(ADDRESS_FAMILY requested, ADDRESS_FAMILY actual) {
  return requested == AF_UNSPEC || requested == actual;
}

void copy_socket_address(SOCKADDR_INET* destination,
                         const SOCKET_ADDRESS* source) {
  ZeroMemory(destination, sizeof(*destination));
  if (source == nullptr || source->lpSockaddr == nullptr) return;
  SIZE_T bytes = source->lpSockaddr->sa_family == AF_INET
                     ? sizeof(SOCKADDR_IN)
                     : sizeof(SOCKADDR_IN6);
  if (source->iSockaddrLength > 0 &&
      static_cast<SIZE_T>(source->iSockaddrLength) < bytes) {
    bytes = static_cast<SIZE_T>(source->iSockaddrLength);
  }
  CopyMemory(destination, source->lpSockaddr, bytes);
}

bool prefix_matches(const SOCKADDR* address, const SOCKADDR* prefix,
                    UINT8 prefix_length) {
  if (address == nullptr || prefix == nullptr ||
      address->sa_family != prefix->sa_family) {
    return false;
  }
  const BYTE* address_bytes = nullptr;
  const BYTE* prefix_bytes = nullptr;
  SIZE_T byte_count = 0;
  if (address->sa_family == AF_INET) {
    address_bytes = reinterpret_cast<const BYTE*>(
        &reinterpret_cast<const SOCKADDR_IN*>(address)->sin_addr);
    prefix_bytes = reinterpret_cast<const BYTE*>(
        &reinterpret_cast<const SOCKADDR_IN*>(prefix)->sin_addr);
    byte_count = 4;
  } else if (address->sa_family == AF_INET6) {
    address_bytes = reinterpret_cast<const BYTE*>(
        &reinterpret_cast<const SOCKADDR_IN6*>(address)->sin6_addr);
    prefix_bytes = reinterpret_cast<const BYTE*>(
        &reinterpret_cast<const SOCKADDR_IN6*>(prefix)->sin6_addr);
    byte_count = 16;
  } else {
    return false;
  }
  if (prefix_length > byte_count * 8) return false;
  const SIZE_T whole_bytes = prefix_length / 8;
  const UINT8 remainder = prefix_length % 8;
  if (whole_bytes != 0 &&
      memcmp(address_bytes, prefix_bytes, whole_bytes) != 0) {
    return false;
  }
  if (remainder != 0) {
    const BYTE mask = static_cast<BYTE>(0xffU << (8 - remainder));
    if ((address_bytes[whole_bytes] & mask) !=
        (prefix_bytes[whole_bytes] & mask)) {
      return false;
    }
  }
  return true;
}

UINT8 adapter_prefix_length(const IP_ADAPTER_ADDRESSES* adapter,
                            const SOCKADDR* address) {
  for (PIP_ADAPTER_PREFIX prefix = adapter->FirstPrefix; prefix != nullptr;
       prefix = prefix->Next) {
    if (prefix_matches(address, prefix->Address.lpSockaddr,
                       static_cast<UINT8>(prefix->PrefixLength))) {
      return static_cast<UINT8>(prefix->PrefixLength);
    }
  }
  return address != nullptr && address->sa_family == AF_INET ? 32 : 128;
}

void fill_interface_row(MIB_IF_ROW2* row,
                        const IP_ADAPTER_ADDRESSES* adapter) {
  ZeroMemory(row, sizeof(*row));
  row->InterfaceLuid = adapter_luid(adapter);
  row->InterfaceIndex = adapter_index(adapter);
  interface_name(row->InterfaceIndex, row->Alias, ARRAYSIZE(row->Alias));
  PCWSTR description = adapter->Description != nullptr
                           ? adapter->Description
                           : adapter->FriendlyName;
  if (description != nullptr) {
    lstrcpynW(row->Description, description, ARRAYSIZE(row->Description));
  }
  row->PhysicalAddressLength = adapter->PhysicalAddressLength;
  if (row->PhysicalAddressLength > ARRAYSIZE(row->PhysicalAddress)) {
    row->PhysicalAddressLength = ARRAYSIZE(row->PhysicalAddress);
  }
  CopyMemory(row->PhysicalAddress, adapter->PhysicalAddress,
             row->PhysicalAddressLength);
  CopyMemory(row->PermanentPhysicalAddress, adapter->PhysicalAddress,
             row->PhysicalAddressLength);
  row->Mtu = adapter->Mtu;
  row->Type = adapter->IfType;
  row->OperStatus = adapter->OperStatus;
  row->AdminStatus = NET_IF_ADMIN_STATUS_UP;
  row->AccessType = adapter->IfType == IF_TYPE_SOFTWARE_LOOPBACK
                        ? NET_IF_ACCESS_LOOPBACK
                    : (adapter->IfType == IF_TYPE_PPP ||
                       adapter->IfType == IF_TYPE_SLIP ||
                       adapter->IfType == IF_TYPE_TUNNEL)
                        ? NET_IF_ACCESS_POINT_TO_POINT
                        : NET_IF_ACCESS_BROADCAST;

  typedef DWORD(WINAPI* GetIfEntryFn)(PMIB_IFROW);
  GetIfEntryFn get_if_entry = iphlpapi_proc<GetIfEntryFn>("GetIfEntry");
  if (get_if_entry != nullptr && adapter->IfIndex != 0) {
    MIB_IFROW legacy = {};
    legacy.dwIndex = adapter->IfIndex;
    if (get_if_entry(&legacy) == NO_ERROR) {
      row->AdminStatus =
          legacy.dwAdminStatus == MIB_IF_ADMIN_STATUS_UP
              ? NET_IF_ADMIN_STATUS_UP
              : NET_IF_ADMIN_STATUS_DOWN;
    }
  }
}

DWORD xp_get_if_table2(PMIB_IF_TABLE2* table) {
  if (table == nullptr) return ERROR_INVALID_PARAMETER;
  *table = nullptr;
  PIP_ADAPTER_ADDRESSES adapters = nullptr;
  DWORD result = load_xp_adapters(AF_UNSPEC, &adapters);
  if (result != NO_ERROR) return result;
  ULONG count = 0;
  for (PIP_ADAPTER_ADDRESSES current = adapters; current != nullptr;
       current = current->Next) {
    if (adapter_index(current) != 0) ++count;
  }
  const SIZE_T size = offsetof(MIB_IF_TABLE2, Table) +
                      static_cast<SIZE_T>(count) * sizeof(MIB_IF_ROW2);
  PMIB_IF_TABLE2 output = static_cast<PMIB_IF_TABLE2>(
      HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, size));
  if (output == nullptr) {
    HeapFree(GetProcessHeap(), 0, adapters);
    return ERROR_NOT_ENOUGH_MEMORY;
  }
  for (PIP_ADAPTER_ADDRESSES current = adapters; current != nullptr;
       current = current->Next) {
    if (adapter_index(current) != 0) {
      fill_interface_row(&output->Table[output->NumEntries++], current);
    }
  }
  HeapFree(GetProcessHeap(), 0, adapters);
  *table = output;
  return NO_ERROR;
}

DWORD xp_get_if_entry2(PMIB_IF_ROW2 row) {
  if (row == nullptr) return ERROR_INVALID_PARAMETER;
  ULONG requested = row->InterfaceIndex;
  if (requested == 0) requested = luid_index(&row->InterfaceLuid);
  if (requested == 0) return ERROR_INVALID_PARAMETER;
  PIP_ADAPTER_ADDRESSES adapters = nullptr;
  DWORD result = load_xp_adapters(AF_UNSPEC, &adapters);
  if (result != NO_ERROR) return result;
  result = ERROR_FILE_NOT_FOUND;
  for (PIP_ADAPTER_ADDRESSES current = adapters; current != nullptr;
       current = current->Next) {
    if (current->IfIndex == requested || current->Ipv6IfIndex == requested ||
        adapter_index(current) == requested) {
      fill_interface_row(row, current);
      result = NO_ERROR;
      break;
    }
  }
  HeapFree(GetProcessHeap(), 0, adapters);
  return result;
}

DWORD xp_get_unicast_table(ADDRESS_FAMILY family,
                           PMIB_UNICASTIPADDRESS_TABLE* table) {
  if (table == nullptr) return ERROR_INVALID_PARAMETER;
  *table = nullptr;
  PIP_ADAPTER_ADDRESSES adapters = nullptr;
  DWORD result = load_xp_adapters(family, &adapters);
  if (result != NO_ERROR) return result;
  ULONG count = 0;
  for (PIP_ADAPTER_ADDRESSES adapter = adapters; adapter != nullptr;
       adapter = adapter->Next) {
    for (PIP_ADAPTER_UNICAST_ADDRESS address = adapter->FirstUnicastAddress;
         address != nullptr; address = address->Next) {
      if (address->Address.lpSockaddr != nullptr &&
          address_family_matches(
              family, address->Address.lpSockaddr->sa_family)) {
        ++count;
      }
    }
  }
  const SIZE_T size = offsetof(MIB_UNICASTIPADDRESS_TABLE, Table) +
                      static_cast<SIZE_T>(count) *
                          sizeof(MIB_UNICASTIPADDRESS_ROW);
  PMIB_UNICASTIPADDRESS_TABLE output =
      static_cast<PMIB_UNICASTIPADDRESS_TABLE>(
          HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, size));
  if (output == nullptr) {
    HeapFree(GetProcessHeap(), 0, adapters);
    return ERROR_NOT_ENOUGH_MEMORY;
  }
  for (PIP_ADAPTER_ADDRESSES adapter = adapters; adapter != nullptr;
       adapter = adapter->Next) {
    for (PIP_ADAPTER_UNICAST_ADDRESS address = adapter->FirstUnicastAddress;
         address != nullptr; address = address->Next) {
      if (address->Address.lpSockaddr == nullptr ||
          !address_family_matches(
              family, address->Address.lpSockaddr->sa_family)) {
        continue;
      }
      MIB_UNICASTIPADDRESS_ROW* row =
          &output->Table[output->NumEntries++];
      copy_socket_address(&row->Address, &address->Address);
      row->InterfaceLuid = adapter_luid(adapter);
      row->InterfaceIndex = adapter_index(adapter);
      row->PrefixOrigin = address->PrefixOrigin;
      row->SuffixOrigin = address->SuffixOrigin;
      row->ValidLifetime = address->ValidLifetime;
      row->PreferredLifetime = address->PreferredLifetime;
      row->OnLinkPrefixLength =
          adapter_prefix_length(adapter, address->Address.lpSockaddr);
      row->DadState = address->DadState;
    }
  }
  HeapFree(GetProcessHeap(), 0, adapters);
  *table = output;
  return NO_ERROR;
}

DWORD xp_get_anycast_table(ADDRESS_FAMILY family,
                           PMIB_ANYCASTIPADDRESS_TABLE* table) {
  if (table == nullptr) return ERROR_INVALID_PARAMETER;
  *table = nullptr;
  PIP_ADAPTER_ADDRESSES adapters = nullptr;
  DWORD result = load_xp_adapters(family, &adapters);
  if (result != NO_ERROR) return result;
  ULONG count = 0;
  for (PIP_ADAPTER_ADDRESSES adapter = adapters; adapter != nullptr;
       adapter = adapter->Next) {
    for (PIP_ADAPTER_ANYCAST_ADDRESS address = adapter->FirstAnycastAddress;
         address != nullptr; address = address->Next) {
      if (address->Address.lpSockaddr != nullptr &&
          address_family_matches(
              family, address->Address.lpSockaddr->sa_family)) {
        ++count;
      }
    }
  }
  const SIZE_T size = offsetof(MIB_ANYCASTIPADDRESS_TABLE, Table) +
                      static_cast<SIZE_T>(count) *
                          sizeof(MIB_ANYCASTIPADDRESS_ROW);
  PMIB_ANYCASTIPADDRESS_TABLE output =
      static_cast<PMIB_ANYCASTIPADDRESS_TABLE>(
          HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, size));
  if (output == nullptr) {
    HeapFree(GetProcessHeap(), 0, adapters);
    return ERROR_NOT_ENOUGH_MEMORY;
  }
  for (PIP_ADAPTER_ADDRESSES adapter = adapters; adapter != nullptr;
       adapter = adapter->Next) {
    for (PIP_ADAPTER_ANYCAST_ADDRESS address = adapter->FirstAnycastAddress;
         address != nullptr; address = address->Next) {
      if (address->Address.lpSockaddr == nullptr ||
          !address_family_matches(
              family, address->Address.lpSockaddr->sa_family)) {
        continue;
      }
      MIB_ANYCASTIPADDRESS_ROW* row =
          &output->Table[output->NumEntries++];
      copy_socket_address(&row->Address, &address->Address);
      row->InterfaceLuid = adapter_luid(adapter);
      row->InterfaceIndex = adapter_index(adapter);
    }
  }
  HeapFree(GetProcessHeap(), 0, adapters);
  *table = output;
  return NO_ERROR;
}

bool native_srw_family_available() {
  static const bool available =
      kernel_proc<FARPROC>("InitializeSRWLock") != nullptr &&
      kernel_proc<FARPROC>("AcquireSRWLockExclusive") != nullptr &&
      kernel_proc<FARPROC>("AcquireSRWLockShared") != nullptr &&
      kernel_proc<FARPROC>("TryAcquireSRWLockExclusive") != nullptr &&
      kernel_proc<FARPROC>("TryAcquireSRWLockShared") != nullptr &&
      kernel_proc<FARPROC>("ReleaseSRWLockExclusive") != nullptr &&
      kernel_proc<FARPROC>("ReleaseSRWLockShared") != nullptr;
  return available;
}

bool native_condition_family_available() {
  static const bool available =
      native_srw_family_available() &&
      kernel_proc<FARPROC>("InitializeConditionVariable") != nullptr &&
      kernel_proc<FARPROC>("SleepConditionVariableCS") != nullptr &&
      kernel_proc<FARPROC>("SleepConditionVariableSRW") != nullptr &&
      kernel_proc<FARPROC>("WakeConditionVariable") != nullptr &&
      kernel_proc<FARPROC>("WakeAllConditionVariable") != nullptr;
  return available;
}

struct XpSrwLock {
  CRITICAL_SECTION lock;
};

XpSrwLock* xp_srw(PSRWLOCK value) {
  XpSrwLock* current = static_cast<XpSrwLock*>(value->Ptr);
  if (current != nullptr) return current;

  XpSrwLock* created = static_cast<XpSrwLock*>(
      HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof(XpSrwLock)));
  if (created == nullptr) RaiseException(0xC0000017UL, 0, 0, nullptr);
  InitializeCriticalSection(&created->lock);

  current = static_cast<XpSrwLock*>(InterlockedCompareExchangePointer(
      &value->Ptr, created, nullptr));
  if (current != nullptr) {
    DeleteCriticalSection(&created->lock);
    HeapFree(GetProcessHeap(), 0, created);
    return current;
  }
  return created;
}

struct XpConditionWaiter {
  XpConditionWaiter* next;
  HANDLE event;
  bool signaled;
};

struct XpConditionVariable {
  CRITICAL_SECTION lock;
  XpConditionWaiter* head;
  XpConditionWaiter* tail;
};

XpConditionVariable* xp_condition(PCONDITION_VARIABLE value) {
  XpConditionVariable* current =
      static_cast<XpConditionVariable*>(value->Ptr);
  if (current != nullptr) return current;

  XpConditionVariable* created = static_cast<XpConditionVariable*>(
      HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY,
                sizeof(XpConditionVariable)));
  if (created == nullptr) RaiseException(0xC0000017UL, 0, 0, nullptr);
  InitializeCriticalSection(&created->lock);

  current = static_cast<XpConditionVariable*>(InterlockedCompareExchangePointer(
      &value->Ptr, created, nullptr));
  if (current != nullptr) {
    DeleteCriticalSection(&created->lock);
    HeapFree(GetProcessHeap(), 0, created);
    return current;
  }
  return created;
}

void unlink_waiter(XpConditionVariable* condition,
                   XpConditionWaiter* waiter) {
  XpConditionWaiter* previous = nullptr;
  for (XpConditionWaiter* current = condition->head; current != nullptr;
       current = current->next) {
    if (current == waiter) {
      if (previous == nullptr) condition->head = current->next;
      else previous->next = current->next;
      if (condition->tail == current) condition->tail = previous;
      return;
    }
    previous = current;
  }
}

enum class ExternalLockKind { CriticalSection, SrwExclusive, SrwShared };

void release_external(void* lock, ExternalLockKind kind) {
  if (kind == ExternalLockKind::CriticalSection) {
    LeaveCriticalSection(static_cast<LPCRITICAL_SECTION>(lock));
  } else {
    LeaveCriticalSection(&xp_srw(static_cast<PSRWLOCK>(lock))->lock);
  }
}

void acquire_external(void* lock, ExternalLockKind kind) {
  if (kind == ExternalLockKind::CriticalSection) {
    EnterCriticalSection(static_cast<LPCRITICAL_SECTION>(lock));
  } else {
    EnterCriticalSection(&xp_srw(static_cast<PSRWLOCK>(lock))->lock);
  }
}

BOOL xp_sleep_condition(PCONDITION_VARIABLE value, void* external_lock,
                        DWORD timeout, ExternalLockKind kind) {
  XpConditionVariable* condition = xp_condition(value);
  XpConditionWaiter waiter = {};
  waiter.event = CreateEventW(nullptr, FALSE, FALSE, nullptr);
  if (waiter.event == nullptr) return FALSE;

  EnterCriticalSection(&condition->lock);
  if (condition->tail == nullptr) condition->head = &waiter;
  else condition->tail->next = &waiter;
  condition->tail = &waiter;

  // Enqueue before releasing the caller's lock.  An early signal is retained
  // by the event, so there is no lost-wakeup window.
  release_external(external_lock, kind);
  LeaveCriticalSection(&condition->lock);

  DWORD result = WaitForSingleObject(waiter.event, timeout);

  EnterCriticalSection(&condition->lock);
  unlink_waiter(condition, &waiter);
  LeaveCriticalSection(&condition->lock);
  CloseHandle(waiter.event);
  acquire_external(external_lock, kind);

  if (result == WAIT_OBJECT_0) return TRUE;
  if (result == WAIT_TIMEOUT) SetLastError(ERROR_TIMEOUT);
  return FALSE;
}

struct XpInitOnce {
  CRITICAL_SECTION lock;
  bool complete;
  void* context;
};

XpInitOnce* xp_once(PINIT_ONCE value) {
  XpInitOnce* current = static_cast<XpInitOnce*>(value->Ptr);
  if (current != nullptr) return current;

  XpInitOnce* created = static_cast<XpInitOnce*>(
      HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof(XpInitOnce)));
  if (created == nullptr) RaiseException(0xC0000017UL, 0, 0, nullptr);
  InitializeCriticalSection(&created->lock);
  current = static_cast<XpInitOnce*>(InterlockedCompareExchangePointer(
      &value->Ptr, created, nullptr));
  if (current != nullptr) {
    DeleteCriticalSection(&created->lock);
    HeapFree(GetProcessHeap(), 0, created);
    return current;
  }
  return created;
}

typedef LONG NTSTATUS;
typedef enum _OBJECT_INFORMATION_CLASS_XP {
  ObjectBasicInformationXp = 0,
  ObjectNameInformationXp = 1
} OBJECT_INFORMATION_CLASS_XP;

typedef struct _UNICODE_STRING_XP {
  USHORT Length;
  USHORT MaximumLength;
  PWSTR Buffer;
} UNICODE_STRING_XP;

typedef struct _OBJECT_NAME_INFORMATION_XP {
  UNICODE_STRING_XP Name;
  WCHAR Buffer[1];
} OBJECT_NAME_INFORMATION_XP;

typedef NTSTATUS(NTAPI* NtQueryObjectFn)(HANDLE, OBJECT_INFORMATION_CLASS_XP,
                                         PVOID, ULONG, PULONG);
typedef ULONG(WINAPI* RtlNtStatusToDosErrorFn)(NTSTATUS);

// These Win32 wrapper types are hidden by the SDK when targeting Server 2003,
// but their ABI is stable and is needed for the exported compatibility entry.
enum FileInfoByHandleClassXp {
  FileBasicInfoXp = 0,
  FileStandardInfoXp = 1,
  FileNameInfoXp = 2,
  FileRenameInfoXp = 3,
  FileDispositionInfoXp = 4,
  FileAllocationInfoXp = 5,
  FileEndOfFileInfoXp = 6
};

struct XpFileEndOfFileInfo {
  LARGE_INTEGER EndOfFile;
};

struct XpFileBasicInfo {
  LARGE_INTEGER CreationTime;
  LARGE_INTEGER LastAccessTime;
  LARGE_INTEGER LastWriteTime;
  LARGE_INTEGER ChangeTime;
  DWORD FileAttributes;
};

struct XpFileStandardInfo {
  LARGE_INTEGER AllocationSize;
  LARGE_INTEGER EndOfFile;
  DWORD NumberOfLinks;
  BOOLEAN DeletePending;
  BOOLEAN Directory;
};

struct XpFileNameInfo {
  DWORD FileNameLength;
  WCHAR FileName[1];
};

LARGE_INTEGER file_time_as_large_integer(const FILETIME& time) {
  LARGE_INTEGER result = {};
  result.LowPart = time.dwLowDateTime;
  result.HighPart = static_cast<LONG>(time.dwHighDateTime);
  return result;
}

LCID xp_lcid_for_locale_name(LPCWSTR locale_name) {
  if (locale_name == nullptr) return GetUserDefaultLCID();
  if (*locale_name == L'\0') return LOCALE_INVARIANT;

  // Preserve the user's configured locale when the caller supplies its
  // language-country name. XP exposes the ISO components even though it does
  // not expose LocaleNameToLCID.
  WCHAR language[16] = {};
  WCHAR country[16] = {};
  LCID user = GetUserDefaultLCID();
  if (GetLocaleInfoW(user, LOCALE_SISO639LANGNAME, language,
                     static_cast<int>(sizeof(language) / sizeof(language[0]))) &&
      GetLocaleInfoW(user, LOCALE_SISO3166CTRYNAME, country,
                     static_cast<int>(sizeof(country) / sizeof(country[0])))) {
    WCHAR user_name[40] = {};
    lstrcpyW(user_name, language);
    lstrcatW(user_name, L"-");
    lstrcatW(user_name, country);
    if (_wcsicmp(locale_name, user_name) == 0) return user;
  }

  // English (United States) is the locale used by the Mojang runtime and is
  // also the invariant fallback used by the MSVC standard library.
  if (_wcsicmp(locale_name, L"en-US") == 0 ||
      _wcsicmp(locale_name, L"en_US") == 0) {
    return MAKELCID(MAKELANGID(LANG_ENGLISH, SUBLANG_ENGLISH_US), SORT_DEFAULT);
  }
  return user;
}

bool nt_success(NTSTATUS status) { return status >= 0; }

void set_nt_error(NTSTATUS status) {
  static RtlNtStatusToDosErrorFn convert =
      ntdll_proc<RtlNtStatusToDosErrorFn>("RtlNtStatusToDosError");
  SetLastError(convert != nullptr ? convert(status) : ERROR_GEN_FAILURE);
}

bool query_handle_name(HANDLE handle, WCHAR** result) {
  *result = nullptr;
  static NtQueryObjectFn query = ntdll_proc<NtQueryObjectFn>("NtQueryObject");
  if (query == nullptr) {
    SetLastError(ERROR_CALL_NOT_IMPLEMENTED);
    return false;
  }

  ULONG size = 1024;
  for (int attempt = 0; attempt < 4; ++attempt) {
    BYTE* storage = static_cast<BYTE*>(HeapAlloc(GetProcessHeap(), 0, size));
    if (storage == nullptr) {
      SetLastError(ERROR_NOT_ENOUGH_MEMORY);
      return false;
    }
    ULONG required = 0;
    NTSTATUS status = query(handle, ObjectNameInformationXp, storage, size,
                            &required);
    if (nt_success(status)) {
      OBJECT_NAME_INFORMATION_XP* info =
          reinterpret_cast<OBJECT_NAME_INFORMATION_XP*>(storage);
      DWORD chars = info->Name.Length / sizeof(WCHAR);
      WCHAR* copy = static_cast<WCHAR*>(HeapAlloc(
          GetProcessHeap(), 0, (static_cast<SIZE_T>(chars) + 1) * sizeof(WCHAR)));
      if (copy == nullptr) {
        HeapFree(GetProcessHeap(), 0, storage);
        SetLastError(ERROR_NOT_ENOUGH_MEMORY);
        return false;
      }
      CopyMemory(copy, info->Name.Buffer, chars * sizeof(WCHAR));
      copy[chars] = L'\0';
      HeapFree(GetProcessHeap(), 0, storage);
      *result = copy;
      return true;
    }
    HeapFree(GetProcessHeap(), 0, storage);
    if (required <= size) {
      set_nt_error(status);
      return false;
    }
    size = required + sizeof(WCHAR);
  }
  SetLastError(ERROR_INSUFFICIENT_BUFFER);
  return false;
}

WCHAR* dos_path_from_nt_path(const WCHAR* nt_path, DWORD flags) {
  const DWORD volume_kind = flags & 0x7;
  if (volume_kind == 0x2) {  // VOLUME_NAME_NT
    SIZE_T length = lstrlenW(nt_path);
    WCHAR* copy = static_cast<WCHAR*>(HeapAlloc(
        GetProcessHeap(), 0, (length + 1) * sizeof(WCHAR)));
    if (copy != nullptr) CopyMemory(copy, nt_path, (length + 1) * sizeof(WCHAR));
    return copy;
  }

  if (wcsncmp(nt_path, L"\\??\\", 4) == 0) {
    const WCHAR* suffix = nt_path + 4;
    SIZE_T suffix_length = lstrlenW(suffix);
    WCHAR* result = static_cast<WCHAR*>(HeapAlloc(
        GetProcessHeap(), 0, (suffix_length + 5) * sizeof(WCHAR)));
    if (result == nullptr) return nullptr;
    lstrcpyW(result, L"\\\\?\\");
    lstrcatW(result, suffix);
    return result;
  }

  WCHAR drives[512] = {};
  DWORD drive_chars = GetLogicalDriveStringsW(511, drives);
  if (drive_chars == 0 || drive_chars >= 511) return nullptr;
  for (const WCHAR* drive = drives; *drive != L'\0'; drive += lstrlenW(drive) + 1) {
    WCHAR name[3] = {drive[0], L':', L'\0'};
    WCHAR device[512] = {};
    if (QueryDosDeviceW(name, device, 511) == 0) continue;
    SIZE_T prefix_length = lstrlenW(device);
    if (_wcsnicmp(nt_path, device, prefix_length) != 0) continue;

    const WCHAR* suffix = nt_path + prefix_length;
    if (volume_kind == 0x4) {  // VOLUME_NAME_NONE
      SIZE_T suffix_length = lstrlenW(suffix);
      WCHAR* result = static_cast<WCHAR*>(HeapAlloc(
          GetProcessHeap(), 0, (suffix_length + 1) * sizeof(WCHAR)));
      if (result != nullptr) {
        CopyMemory(result, suffix, (suffix_length + 1) * sizeof(WCHAR));
      }
      return result;
    }

    SIZE_T suffix_length = lstrlenW(suffix);
    WCHAR* result = static_cast<WCHAR*>(HeapAlloc(
        GetProcessHeap(), 0, (suffix_length + 8) * sizeof(WCHAR)));
    if (result == nullptr) return nullptr;
    result[0] = L'\\';
    result[1] = L'\\';
    result[2] = L'?';
    result[3] = L'\\';
    result[4] = drive[0];
    result[5] = L':';
    lstrcpyW(result + 6, suffix);
    return result;
  }
  return nullptr;
}

volatile LONG64 g_tick_state = 0;

ULONGLONG xp_tick_count64() {
  DWORD low = GetTickCount();
  for (;;) {
    LONG64 previous = g_tick_state;
    DWORD previous_low = static_cast<DWORD>(previous);
    ULONGLONG high = static_cast<ULONGLONG>(previous) & 0xffffffff00000000ULL;
    if (low < previous_low && previous_low - low > 0x80000000UL) {
      high += 0x100000000ULL;
    }
    LONG64 next = static_cast<LONG64>(high | low);
    LONG64 observed = InterlockedCompareExchange64(&g_tick_state, next, previous);
    if (observed == previous) return static_cast<ULONGLONG>(next);
  }
}

typedef VOID(CALLBACK* XpTpWorkCallback)(PVOID, PVOID, PVOID);

struct XpThreadpoolWork {
  XpTpWorkCallback callback;
  PVOID context;
  volatile LONG references;
  volatile LONG closing;
};

DWORD WINAPI xp_threadpool_work_runner(LPVOID parameter) {
  XpThreadpoolWork* work = static_cast<XpThreadpoolWork*>(parameter);
  work->callback(nullptr, work->context, work);
  if (InterlockedDecrement(&work->references) == 0) {
    HeapFree(GetProcessHeap(), 0, work);
  }
  return 0;
}

}  // namespace

extern "C" {

__declspec(dllexport) PVOID WINAPI CreateThreadpoolWork(
    XpTpWorkCallback callback, PVOID context, PVOID environment) {
  typedef PVOID(WINAPI* Fn)(XpTpWorkCallback, PVOID, PVOID);
  static Fn native = kernel_proc<Fn>("CreateThreadpoolWork");
  if (native != nullptr) return native(callback, context, environment);
  if (callback == nullptr) {
    SetLastError(ERROR_INVALID_PARAMETER);
    return nullptr;
  }
  XpThreadpoolWork* work = static_cast<XpThreadpoolWork*>(
      HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY,
                sizeof(XpThreadpoolWork)));
  if (work == nullptr) {
    SetLastError(ERROR_NOT_ENOUGH_MEMORY);
    return nullptr;
  }
  work->callback = callback;
  work->context = context;
  work->references = 1;
  return work;
}

__declspec(dllexport) VOID WINAPI SubmitThreadpoolWork(PVOID opaque_work) {
  typedef VOID(WINAPI* Fn)(PVOID);
  static Fn native = kernel_proc<Fn>("SubmitThreadpoolWork");
  if (native != nullptr) return native(opaque_work);
  XpThreadpoolWork* work = static_cast<XpThreadpoolWork*>(opaque_work);
  if (work == nullptr || work->closing != 0) return;
  InterlockedIncrement(&work->references);
  HANDLE thread = CreateThread(nullptr, 0, xp_threadpool_work_runner, work, 0,
                               nullptr);
  if (thread == nullptr) {
    if (InterlockedDecrement(&work->references) == 0) {
      HeapFree(GetProcessHeap(), 0, work);
    }
    return;
  }
  CloseHandle(thread);
}

__declspec(dllexport) VOID WINAPI CloseThreadpoolWork(PVOID opaque_work) {
  typedef VOID(WINAPI* Fn)(PVOID);
  static Fn native = kernel_proc<Fn>("CloseThreadpoolWork");
  if (native != nullptr) return native(opaque_work);
  XpThreadpoolWork* work = static_cast<XpThreadpoolWork*>(opaque_work);
  if (work == nullptr || InterlockedExchange(&work->closing, 1) != 0) return;
  if (InterlockedDecrement(&work->references) == 0) {
    HeapFree(GetProcessHeap(), 0, work);
  }
}

__declspec(dllexport) VOID WINAPI FreeLibraryWhenCallbackReturns(
    PVOID callback_instance, HMODULE module) {
  typedef VOID(WINAPI* Fn)(PVOID, HMODULE);
  static Fn native = kernel_proc<Fn>("FreeLibraryWhenCallbackReturns");
  if (native != nullptr) return native(callback_instance, module);
  // XP's fallback workers are short-lived dedicated threads. Deliberately keep
  // the optional backend loaded until process exit instead of unloading code
  // while its callback could still be returning.
  (void)callback_instance;
  (void)module;
}

__declspec(dllexport) VOID WINAPI InitializeSRWLock(PSRWLOCK lock) {
  typedef VOID(WINAPI* Fn)(PSRWLOCK);
  static Fn native = native_srw_family_available()
                         ? kernel_proc<Fn>("InitializeSRWLock")
                         : nullptr;
  if (native != nullptr) return native(lock);
  lock->Ptr = nullptr;
}

__declspec(dllexport) VOID WINAPI AcquireSRWLockExclusive(PSRWLOCK lock) {
  typedef VOID(WINAPI* Fn)(PSRWLOCK);
  static Fn native = native_srw_family_available()
                         ? kernel_proc<Fn>("AcquireSRWLockExclusive")
                         : nullptr;
  if (native != nullptr) return native(lock);
  EnterCriticalSection(&xp_srw(lock)->lock);
}

__declspec(dllexport) VOID WINAPI AcquireSRWLockShared(PSRWLOCK lock) {
  typedef VOID(WINAPI* Fn)(PSRWLOCK);
  static Fn native = native_srw_family_available()
                         ? kernel_proc<Fn>("AcquireSRWLockShared")
                         : nullptr;
  if (native != nullptr) return native(lock);
  EnterCriticalSection(&xp_srw(lock)->lock);
}

__declspec(dllexport) BOOLEAN WINAPI TryAcquireSRWLockExclusive(PSRWLOCK lock) {
  typedef BOOLEAN(WINAPI* Fn)(PSRWLOCK);
  static Fn native = native_srw_family_available()
                         ? kernel_proc<Fn>("TryAcquireSRWLockExclusive")
                         : nullptr;
  if (native != nullptr) return native(lock);
  return TryEnterCriticalSection(&xp_srw(lock)->lock) ? TRUE : FALSE;
}

__declspec(dllexport) BOOLEAN WINAPI TryAcquireSRWLockShared(PSRWLOCK lock) {
  typedef BOOLEAN(WINAPI* Fn)(PSRWLOCK);
  static Fn native = native_srw_family_available()
                         ? kernel_proc<Fn>("TryAcquireSRWLockShared")
                         : nullptr;
  if (native != nullptr) return native(lock);
  return TryEnterCriticalSection(&xp_srw(lock)->lock) ? TRUE : FALSE;
}

__declspec(dllexport) VOID WINAPI ReleaseSRWLockExclusive(PSRWLOCK lock) {
  typedef VOID(WINAPI* Fn)(PSRWLOCK);
  static Fn native = native_srw_family_available()
                         ? kernel_proc<Fn>("ReleaseSRWLockExclusive")
                         : nullptr;
  if (native != nullptr) return native(lock);
  LeaveCriticalSection(&xp_srw(lock)->lock);
}

__declspec(dllexport) VOID WINAPI ReleaseSRWLockShared(PSRWLOCK lock) {
  typedef VOID(WINAPI* Fn)(PSRWLOCK);
  static Fn native = native_srw_family_available()
                         ? kernel_proc<Fn>("ReleaseSRWLockShared")
                         : nullptr;
  if (native != nullptr) return native(lock);
  LeaveCriticalSection(&xp_srw(lock)->lock);
}

__declspec(dllexport) VOID WINAPI InitializeConditionVariable(
    PCONDITION_VARIABLE condition) {
  typedef VOID(WINAPI* Fn)(PCONDITION_VARIABLE);
  static Fn native = native_condition_family_available()
                         ? kernel_proc<Fn>("InitializeConditionVariable")
                         : nullptr;
  if (native != nullptr) return native(condition);
  condition->Ptr = nullptr;
}

__declspec(dllexport) BOOL WINAPI SleepConditionVariableCS(
    PCONDITION_VARIABLE condition, PCRITICAL_SECTION lock, DWORD timeout) {
  typedef BOOL(WINAPI* Fn)(PCONDITION_VARIABLE, PCRITICAL_SECTION, DWORD);
  static Fn native = native_condition_family_available()
                         ? kernel_proc<Fn>("SleepConditionVariableCS")
                         : nullptr;
  if (native != nullptr) return native(condition, lock, timeout);
  return xp_sleep_condition(condition, lock, timeout,
                            ExternalLockKind::CriticalSection);
}

__declspec(dllexport) BOOL WINAPI SleepConditionVariableSRW(
    PCONDITION_VARIABLE condition, PSRWLOCK lock, DWORD timeout, ULONG flags) {
  typedef BOOL(WINAPI* Fn)(PCONDITION_VARIABLE, PSRWLOCK, DWORD, ULONG);
  static Fn native = native_condition_family_available()
                         ? kernel_proc<Fn>("SleepConditionVariableSRW")
                         : nullptr;
  if (native != nullptr) return native(condition, lock, timeout, flags);
  ExternalLockKind kind = (flags & 1) != 0
                              ? ExternalLockKind::SrwShared
                              : ExternalLockKind::SrwExclusive;
  return xp_sleep_condition(condition, lock, timeout, kind);
}

__declspec(dllexport) VOID WINAPI WakeConditionVariable(
    PCONDITION_VARIABLE value) {
  typedef VOID(WINAPI* Fn)(PCONDITION_VARIABLE);
  static Fn native = native_condition_family_available()
                         ? kernel_proc<Fn>("WakeConditionVariable")
                         : nullptr;
  if (native != nullptr) return native(value);
  XpConditionVariable* condition = xp_condition(value);
  EnterCriticalSection(&condition->lock);
  for (XpConditionWaiter* waiter = condition->head; waiter != nullptr;
       waiter = waiter->next) {
    if (!waiter->signaled) {
      waiter->signaled = true;
      SetEvent(waiter->event);
      break;
    }
  }
  LeaveCriticalSection(&condition->lock);
}

__declspec(dllexport) VOID WINAPI WakeAllConditionVariable(
    PCONDITION_VARIABLE value) {
  typedef VOID(WINAPI* Fn)(PCONDITION_VARIABLE);
  static Fn native = native_condition_family_available()
                         ? kernel_proc<Fn>("WakeAllConditionVariable")
                         : nullptr;
  if (native != nullptr) return native(value);
  XpConditionVariable* condition = xp_condition(value);
  EnterCriticalSection(&condition->lock);
  for (XpConditionWaiter* waiter = condition->head; waiter != nullptr;
       waiter = waiter->next) {
    waiter->signaled = true;
    SetEvent(waiter->event);
  }
  LeaveCriticalSection(&condition->lock);
}

__declspec(dllexport) BOOL WINAPI InitOnceExecuteOnce(
    PINIT_ONCE once, PINIT_ONCE_FN callback, PVOID parameter, LPVOID* context) {
  typedef BOOL(WINAPI* Fn)(PINIT_ONCE, PINIT_ONCE_FN, PVOID, LPVOID*);
  static Fn native = kernel_proc<Fn>("InitOnceExecuteOnce");
  if (native != nullptr) return native(once, callback, parameter, context);
  XpInitOnce* state = xp_once(once);
  EnterCriticalSection(&state->lock);
  BOOL result = TRUE;
  if (!state->complete) {
    void* callback_context = nullptr;
    result = callback(once, parameter, &callback_context);
    if (result) {
      state->context = callback_context;
      state->complete = true;
    }
  }
  if (result && context != nullptr) *context = state->context;
  LeaveCriticalSection(&state->lock);
  return result;
}

__declspec(dllexport) BOOL WINAPI InitOnceBeginInitialize(
    PINIT_ONCE once, DWORD flags, PBOOL pending, LPVOID* context) {
  typedef BOOL(WINAPI* Fn)(PINIT_ONCE, DWORD, PBOOL, LPVOID*);
  static Fn native = kernel_proc<Fn>("InitOnceBeginInitialize");
  if (native != nullptr) return native(once, flags, pending, context);
  if (once == nullptr || pending == nullptr || (flags & ~0x3UL) != 0) {
    SetLastError(ERROR_INVALID_PARAMETER);
    return FALSE;
  }

  XpInitOnce* state = xp_once(once);
  EnterCriticalSection(&state->lock);
  if ((flags & 0x1UL) != 0) {  // INIT_ONCE_CHECK_ONLY
    if (!state->complete) {
      LeaveCriticalSection(&state->lock);
      SetLastError(ERROR_GEN_FAILURE);
      return FALSE;
    }
    *pending = FALSE;
    if (context != nullptr) *context = state->context;
    LeaveCriticalSection(&state->lock);
    return TRUE;
  }

  if (state->complete) {
    *pending = FALSE;
    if (context != nullptr) *context = state->context;
    LeaveCriticalSection(&state->lock);
  } else {
    // The successful initializer retains the recursive critical section until
    // InitOnceComplete. Other threads block here, matching native synchronous
    // INIT_ONCE behavior.
    *pending = TRUE;
  }
  return TRUE;
}

__declspec(dllexport) BOOL WINAPI InitOnceComplete(
    PINIT_ONCE once, DWORD flags, LPVOID context) {
  typedef BOOL(WINAPI* Fn)(PINIT_ONCE, DWORD, LPVOID);
  static Fn native = kernel_proc<Fn>("InitOnceComplete");
  if (native != nullptr) return native(once, flags, context);
  if (once == nullptr || (flags & ~0x4UL) != 0) {
    SetLastError(ERROR_INVALID_PARAMETER);
    return FALSE;
  }
  XpInitOnce* state = xp_once(once);
  if ((flags & 0x4UL) == 0) {  // not INIT_ONCE_INIT_FAILED
    state->context = context;
    state->complete = true;
  }
  LeaveCriticalSection(&state->lock);
  return TRUE;
}

__declspec(dllexport) ULONGLONG WINAPI GetTickCount64(void) {
  typedef ULONGLONG(WINAPI* Fn)(void);
  static Fn native = kernel_proc<Fn>("GetTickCount64");
  return native != nullptr ? native() : xp_tick_count64();
}

__declspec(dllexport) BOOL WINAPI GetQueuedCompletionStatusEx(
    HANDLE port, LPOVERLAPPED_ENTRY entries, ULONG count, PULONG removed,
    DWORD timeout, BOOL alertable) {
  typedef BOOL(WINAPI* Fn)(HANDLE, LPOVERLAPPED_ENTRY, ULONG, PULONG, DWORD,
                           BOOL);
  static Fn native = kernel_proc<Fn>("GetQueuedCompletionStatusEx");
  if (native != nullptr) {
    return native(port, entries, count, removed, timeout, alertable);
  }
  if (entries == nullptr || removed == nullptr || count == 0) {
    SetLastError(ERROR_INVALID_PARAMETER);
    return FALSE;
  }
  DWORD bytes = 0;
  ULONG_PTR key = 0;
  LPOVERLAPPED overlapped = nullptr;
  BOOL ok = GetQueuedCompletionStatus(port, &bytes, &key, &overlapped, timeout);
  if (!ok && overlapped == nullptr) {
    *removed = 0;
    return FALSE;
  }
  entries[0].lpCompletionKey = key;
  entries[0].lpOverlapped = overlapped;
  entries[0].Internal = overlapped != nullptr ? overlapped->Internal : 0;
  entries[0].dwNumberOfBytesTransferred = bytes;
  *removed = 1;
  return TRUE;
}

__declspec(dllexport) BOOL WINAPI SetFileCompletionNotificationModes(
    HANDLE file, UCHAR flags) {
  typedef BOOL(WINAPI* Fn)(HANDLE, UCHAR);
  static Fn native = kernel_proc<Fn>("SetFileCompletionNotificationModes");
  if (native != nullptr) return native(file, flags);

  // Some NT 5.x systems omit this API even though their completion-port and
  // event behavior can satisfy FILE_SKIP_SET_EVENT_ON_HANDLE. (XP x64 SP2
  // exports the API and therefore takes the native branch above.) Only when
  // the export is genuinely absent, treat that one safe flag as a no-op. The
  // other modes change completion delivery semantics and are not emulated.
  constexpr UCHAR kSkipSetEventOnHandle = 0x2;
  if ((flags & ~kSkipSetEventOnHandle) == 0) return TRUE;
  SetLastError(ERROR_CALL_NOT_IMPLEMENTED);
  return FALSE;
}

__declspec(dllexport) DWORD WINAPI GetFinalPathNameByHandleW(
    HANDLE file, LPWSTR buffer, DWORD buffer_chars, DWORD flags) {
  typedef DWORD(WINAPI* Fn)(HANDLE, LPWSTR, DWORD, DWORD);
  static Fn native = kernel_proc<Fn>("GetFinalPathNameByHandleW");
  if (native != nullptr) return native(file, buffer, buffer_chars, flags);
  WCHAR* nt_path = nullptr;
  if (!query_handle_name(file, &nt_path)) return 0;
  WCHAR* final_path = dos_path_from_nt_path(nt_path, flags);
  HeapFree(GetProcessHeap(), 0, nt_path);
  if (final_path == nullptr) {
    SetLastError(ERROR_PATH_NOT_FOUND);
    return 0;
  }
  DWORD length = static_cast<DWORD>(lstrlenW(final_path));
  if (buffer == nullptr || buffer_chars <= length) {
    HeapFree(GetProcessHeap(), 0, final_path);
    return length + 1;
  }
  CopyMemory(buffer, final_path, (length + 1) * sizeof(WCHAR));
  HeapFree(GetProcessHeap(), 0, final_path);
  return length;
}

__declspec(dllexport) BOOL WINAPI GetFileInformationByHandleEx(
    HANDLE file, FileInfoByHandleClassXp information_class, LPVOID information,
    DWORD information_size) {
  typedef BOOL(WINAPI* Fn)(HANDLE, FileInfoByHandleClassXp, LPVOID, DWORD);
  static Fn native = kernel_proc<Fn>("GetFileInformationByHandleEx");
  if (native != nullptr) {
    return native(file, information_class, information, information_size);
  }
  if (information == nullptr) {
    SetLastError(ERROR_INVALID_PARAMETER);
    return FALSE;
  }

  BY_HANDLE_FILE_INFORMATION legacy = {};
  if (information_class == FileBasicInfoXp) {
    if (information_size < sizeof(XpFileBasicInfo)) {
      SetLastError(ERROR_BAD_LENGTH);
      return FALSE;
    }
    if (!GetFileInformationByHandle(file, &legacy)) return FALSE;
    XpFileBasicInfo* result = static_cast<XpFileBasicInfo*>(information);
    result->CreationTime = file_time_as_large_integer(legacy.ftCreationTime);
    result->LastAccessTime = file_time_as_large_integer(legacy.ftLastAccessTime);
    result->LastWriteTime = file_time_as_large_integer(legacy.ftLastWriteTime);
    result->ChangeTime = result->LastWriteTime;
    result->FileAttributes = legacy.dwFileAttributes;
    return TRUE;
  }
  if (information_class == FileStandardInfoXp) {
    if (information_size < sizeof(XpFileStandardInfo)) {
      SetLastError(ERROR_BAD_LENGTH);
      return FALSE;
    }
    if (!GetFileInformationByHandle(file, &legacy)) return FALSE;
    XpFileStandardInfo* result =
        static_cast<XpFileStandardInfo*>(information);
    result->EndOfFile.HighPart = static_cast<LONG>(legacy.nFileSizeHigh);
    result->EndOfFile.LowPart = legacy.nFileSizeLow;
    result->AllocationSize = result->EndOfFile;
    result->NumberOfLinks = legacy.nNumberOfLinks;
    result->DeletePending = FALSE;
    result->Directory =
        (legacy.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
    return TRUE;
  }
  if (information_class == FileNameInfoXp) {
    if (information_size < sizeof(DWORD)) {
      SetLastError(ERROR_BAD_LENGTH);
      return FALSE;
    }
    WCHAR* name = nullptr;
    if (!query_handle_name(file, &name)) return FALSE;
    DWORD bytes = static_cast<DWORD>(lstrlenW(name) * sizeof(WCHAR));
    if (information_size < sizeof(DWORD) + bytes) {
      HeapFree(GetProcessHeap(), 0, name);
      SetLastError(ERROR_MORE_DATA);
      return FALSE;
    }
    XpFileNameInfo* result = static_cast<XpFileNameInfo*>(information);
    result->FileNameLength = bytes;
    CopyMemory(result->FileName, name, bytes);
    HeapFree(GetProcessHeap(), 0, name);
    return TRUE;
  }
  SetLastError(ERROR_CALL_NOT_IMPLEMENTED);
  return FALSE;
}

__declspec(dllexport) int WINAPI GetLocaleInfoEx(
    LPCWSTR locale_name, LCTYPE type, LPWSTR data, int data_chars) {
  typedef int(WINAPI* Fn)(LPCWSTR, LCTYPE, LPWSTR, int);
  static Fn native = kernel_proc<Fn>("GetLocaleInfoEx");
  return native != nullptr
             ? native(locale_name, type, data, data_chars)
             : GetLocaleInfoW(xp_lcid_for_locale_name(locale_name), type, data,
                              data_chars);
}

__declspec(dllexport) int WINAPI LCMapStringEx(
    LPCWSTR locale_name, DWORD flags, LPCWSTR source, int source_chars,
    LPWSTR destination, int destination_chars, LPNLSVERSIONINFO version,
    LPVOID reserved, LPARAM sort_handle) {
  typedef int(WINAPI* Fn)(LPCWSTR, DWORD, LPCWSTR, int, LPWSTR, int,
                          LPNLSVERSIONINFO, LPVOID, LPARAM);
  static Fn native = kernel_proc<Fn>("LCMapStringEx");
  if (native != nullptr) {
    return native(locale_name, flags, source, source_chars, destination,
                  destination_chars, version, reserved, sort_handle);
  }
  if (version != nullptr || reserved != nullptr || sort_handle != 0) {
    SetLastError(ERROR_INVALID_PARAMETER);
    return 0;
  }
  return LCMapStringW(xp_lcid_for_locale_name(locale_name), flags, source,
                      source_chars, destination, destination_chars);
}

__declspec(dllexport) int WINAPI CompareStringEx(
    LPCWSTR locale_name, DWORD flags, LPCWCH first, int first_chars,
    LPCWCH second, int second_chars, LPNLSVERSIONINFO version,
    LPVOID reserved, LPARAM sort_handle) {
  typedef int(WINAPI* Fn)(LPCWSTR, DWORD, LPCWCH, int, LPCWCH, int,
                          LPNLSVERSIONINFO, LPVOID, LPARAM);
  static Fn native = kernel_proc<Fn>("CompareStringEx");
  if (native != nullptr) {
    return native(locale_name, flags, first, first_chars, second, second_chars,
                  version, reserved, sort_handle);
  }
  if (version != nullptr || reserved != nullptr || sort_handle != 0) {
    SetLastError(ERROR_INVALID_PARAMETER);
    return 0;
  }
  return CompareStringW(xp_lcid_for_locale_name(locale_name), flags, first,
                        first_chars, second, second_chars);
}

__declspec(dllexport) BOOL WINAPI SetFileInformationByHandle(
    HANDLE file, FileInfoByHandleClassXp information_class, LPVOID information,
    DWORD information_size) {
  typedef BOOL(WINAPI* Fn)(HANDLE, FileInfoByHandleClassXp, LPVOID, DWORD);
  static Fn native = kernel_proc<Fn>("SetFileInformationByHandle");
  if (native != nullptr) {
    return native(file, information_class, information, information_size);
  }
  if (information_class != FileEndOfFileInfoXp ||
      information_size < sizeof(XpFileEndOfFileInfo)) {
    SetLastError(ERROR_CALL_NOT_IMPLEMENTED);
    return FALSE;
  }
  LARGE_INTEGER original = {};
  LARGE_INTEGER zero = {};
  if (!SetFilePointerEx(file, zero, &original, FILE_CURRENT)) return FALSE;
  LARGE_INTEGER end =
      static_cast<XpFileEndOfFileInfo*>(information)->EndOfFile;
  if (!SetFilePointerEx(file, end, nullptr, FILE_BEGIN)) return FALSE;
  BOOL result = SetEndOfFile(file);
  DWORD error = result ? ERROR_SUCCESS : GetLastError();
  SetFilePointerEx(file, original, nullptr, FILE_BEGIN);
  if (!result) SetLastError(error);
  return result;
}

__declspec(dllexport) BOOL WINAPI CreateSymbolicLinkW(
    LPCWSTR link, LPCWSTR target, DWORD flags) {
  typedef BOOL(WINAPI* Fn)(LPCWSTR, LPCWSTR, DWORD);
  static Fn native = kernel_proc<Fn>("CreateSymbolicLinkW");
  if (native != nullptr) {
    // This branch is deliberately kept separate because XP has no native
    // symbolic-link primitive.  Java receives a normal unsupported result.
    return native(link, target, flags);
  }
  SetLastError(ERROR_CALL_NOT_IMPLEMENTED);
  return FALSE;
}

__declspec(dllexport) DWORD WINAPI GetDynamicTimeZoneInformation(
    PDYNAMIC_TIME_ZONE_INFORMATION dynamic_info) {
  typedef DWORD(WINAPI* Fn)(PDYNAMIC_TIME_ZONE_INFORMATION);
  static Fn native = kernel_proc<Fn>("GetDynamicTimeZoneInformation");
  if (native != nullptr) return native(dynamic_info);
  if (dynamic_info == nullptr) return TIME_ZONE_ID_INVALID;
  TIME_ZONE_INFORMATION info = {};
  DWORD result = GetTimeZoneInformation(&info);
  if (result == TIME_ZONE_ID_INVALID) return result;
  ZeroMemory(dynamic_info, sizeof(*dynamic_info));
  dynamic_info->Bias = info.Bias;
  CopyMemory(dynamic_info->StandardName, info.StandardName,
             sizeof(info.StandardName));
  dynamic_info->StandardDate = info.StandardDate;
  dynamic_info->StandardBias = info.StandardBias;
  CopyMemory(dynamic_info->DaylightName, info.DaylightName,
             sizeof(info.DaylightName));
  dynamic_info->DaylightDate = info.DaylightDate;
  dynamic_info->DaylightBias = info.DaylightBias;
  dynamic_info->DynamicDaylightTimeDisabled = FALSE;
  return result;
}

__declspec(dllexport) BOOL WINAPI QueryFullProcessImageNameW(
    HANDLE process, DWORD flags, LPWSTR path, PDWORD path_chars) {
  typedef BOOL(WINAPI* Fn)(HANDLE, DWORD, LPWSTR, PDWORD);
  static Fn native = kernel_proc<Fn>("QueryFullProcessImageNameW");
  if (native != nullptr) return native(process, flags, path, path_chars);
  if (path == nullptr || path_chars == nullptr || *path_chars == 0) {
    SetLastError(ERROR_INVALID_PARAMETER);
    return FALSE;
  }
  DWORD capacity = *path_chars;
  DWORD length = GetModuleFileNameExW(process, nullptr, path, capacity);
  if (length == 0) return FALSE;
  if (length >= capacity - 1) {
    SetLastError(ERROR_INSUFFICIENT_BUFFER);
    return FALSE;
  }
  *path_chars = length;
  return TRUE;
}

__declspec(dllexport) VOID WINAPI FlushProcessWriteBuffers(void) {
  typedef VOID(WINAPI* Fn)(void);
  static Fn native = kernel_proc<Fn>("FlushProcessWriteBuffers");
  if (native != nullptr) return native();
  static volatile LONG barrier;
  InterlockedExchange(&barrier, 0);
}

__declspec(dllexport) DWORD WINAPI GetActiveProcessorCount(WORD group) {
  typedef DWORD(WINAPI* Fn)(WORD);
  static Fn native = kernel_proc<Fn>("GetActiveProcessorCount");
  if (native != nullptr) return native(group);
  SYSTEM_INFO info = {};
  GetSystemInfo(&info);
  return info.dwNumberOfProcessors;
}

__declspec(dllexport) BOOL WINAPI GetProcessGroupAffinity(
    HANDLE process, PUSHORT group_count, PUSHORT group_array) {
  typedef BOOL(WINAPI* Fn)(HANDLE, PUSHORT, PUSHORT);
  static Fn native = kernel_proc<Fn>("GetProcessGroupAffinity");
  if (native != nullptr) return native(process, group_count, group_array);
  if (group_count == nullptr) {
    SetLastError(ERROR_INVALID_PARAMETER);
    return FALSE;
  }
  if (group_array == nullptr || *group_count < 1) {
    *group_count = 1;
    SetLastError(ERROR_INSUFFICIENT_BUFFER);
    return FALSE;
  }
  group_array[0] = 0;
  *group_count = 1;
  return TRUE;
}

__declspec(dllexport) LPVOID WINAPI VirtualAllocExNuma(
    HANDLE process, LPVOID address, SIZE_T size, DWORD allocation_type,
    DWORD protect, DWORD preferred_node) {
  typedef LPVOID(WINAPI* Fn)(HANDLE, LPVOID, SIZE_T, DWORD, DWORD, DWORD);
  static Fn native = kernel_proc<Fn>("VirtualAllocExNuma");
  return native != nullptr
             ? native(process, address, size, allocation_type, protect,
                      preferred_node)
             : VirtualAllocEx(process, address, size, allocation_type, protect);
}

__declspec(dllexport) BOOL WINAPI K32EnumProcessModules(
    HANDLE process, HMODULE* modules, DWORD bytes, LPDWORD needed) {
  typedef BOOL(WINAPI* Fn)(HANDLE, HMODULE*, DWORD, LPDWORD);
  static Fn native = kernel_proc<Fn>("K32EnumProcessModules");
  return native != nullptr ? native(process, modules, bytes, needed)
                           : EnumProcessModules(process, modules, bytes, needed);
}

__declspec(dllexport) BOOL WINAPI K32EnumProcessModulesEx(
    HANDLE process, HMODULE* modules, DWORD bytes, LPDWORD needed,
    DWORD filter_flag) {
  typedef BOOL(WINAPI* Fn)(HANDLE, HMODULE*, DWORD, LPDWORD, DWORD);
  static Fn native = kernel_proc<Fn>("K32EnumProcessModulesEx");
  if (native != nullptr) {
    return native(process, modules, bytes, needed, filter_flag);
  }
  // XP/Server 2003 x64 has no cross-architecture module enumeration filter.
  // The calling process and Minecraft runtime are both x64, so the legacy
  // PSAPI function has the same effective result for LIST_MODULES_DEFAULT and
  // LIST_MODULES_64BIT. Ignore the advisory filter on these systems.
  return EnumProcessModules(process, modules, bytes, needed);
}

__declspec(dllexport) DWORD WINAPI K32GetModuleFileNameExA(
    HANDLE process, HMODULE module, LPSTR name, DWORD size) {
  typedef DWORD(WINAPI* Fn)(HANDLE, HMODULE, LPSTR, DWORD);
  static Fn native = kernel_proc<Fn>("K32GetModuleFileNameExA");
  return native != nullptr ? native(process, module, name, size)
                           : GetModuleFileNameExA(process, module, name, size);
}

__declspec(dllexport) BOOL WINAPI K32GetModuleInformation(
    HANDLE process, HMODULE module, LPMODULEINFO info, DWORD size) {
  typedef BOOL(WINAPI* Fn)(HANDLE, HMODULE, LPMODULEINFO, DWORD);
  static Fn native = kernel_proc<Fn>("K32GetModuleInformation");
  return native != nullptr ? native(process, module, info, size)
                           : GetModuleInformation(process, module, info, size);
}

__declspec(dllexport) BOOL WINAPI K32GetProcessMemoryInfo(
    HANDLE process, PPROCESS_MEMORY_COUNTERS counters, DWORD size) {
  typedef BOOL(WINAPI* Fn)(HANDLE, PPROCESS_MEMORY_COUNTERS, DWORD);
  static Fn native = kernel_proc<Fn>("K32GetProcessMemoryInfo");
  return native != nullptr ? native(process, counters, size)
                           : GetProcessMemoryInfo(process, counters, size);
}

// Use an internal name because the modern Windows SDK declares the public
// entry point with import linkage. The definition file maps the public export.
VOID WINAPI JdkXpRaiseFailFastException(
    PEXCEPTION_RECORD record, PCONTEXT context, DWORD flags) {
  typedef VOID(WINAPI* Fn)(PEXCEPTION_RECORD, PCONTEXT, DWORD);
  static Fn native = kernel_proc<Fn>("RaiseFailFastException");
  if (native != nullptr) return native(record, context, flags);
  if (record != nullptr) {
    EXCEPTION_POINTERS pointers = {record, context};
    UnhandledExceptionFilter(&pointers);
  }
  TerminateProcess(GetCurrentProcess(),
                   record != nullptr ? record->ExceptionCode : 3);
}

__declspec(dllexport) BOOL WINAPI InitializeCriticalSectionEx(
    LPCRITICAL_SECTION section, DWORD spin_count, DWORD flags) {
  typedef BOOL(WINAPI* Fn)(LPCRITICAL_SECTION, DWORD, DWORD);
  static Fn native = kernel_proc<Fn>("InitializeCriticalSectionEx");
  return native != nullptr
             ? native(section, spin_count, flags)
             : InitializeCriticalSectionAndSpinCount(section, spin_count);
}

__declspec(dllexport) HANDLE WINAPI CreateEventExW(
    LPSECURITY_ATTRIBUTES attributes, LPCWSTR name, DWORD flags,
    DWORD desired_access) {
  typedef HANDLE(WINAPI* Fn)(LPSECURITY_ATTRIBUTES, LPCWSTR, DWORD, DWORD);
  static Fn native = kernel_proc<Fn>("CreateEventExW");
  if (native != nullptr) return native(attributes, name, flags, desired_access);
  return CreateEventW(attributes, (flags & 1) != 0, (flags & 2) != 0, name);
}

__declspec(dllexport) HANDLE WINAPI CreateEventExA(
    LPSECURITY_ATTRIBUTES attributes, LPCSTR name, DWORD flags,
    DWORD desired_access) {
  typedef HANDLE(WINAPI* Fn)(LPSECURITY_ATTRIBUTES, LPCSTR, DWORD, DWORD);
  static Fn native = kernel_proc<Fn>("CreateEventExA");
  if (native != nullptr) return native(attributes, name, flags, desired_access);
  return CreateEventA(attributes, (flags & 1) != 0, (flags & 2) != 0, name);
}

__declspec(dllexport) HANDLE WINAPI CreateMutexExW(
    LPSECURITY_ATTRIBUTES attributes, LPCWSTR name, DWORD flags,
    DWORD desired_access) {
  typedef HANDLE(WINAPI* Fn)(LPSECURITY_ATTRIBUTES, LPCWSTR, DWORD, DWORD);
  static Fn native = kernel_proc<Fn>("CreateMutexExW");
  if (native != nullptr) return native(attributes, name, flags, desired_access);
  return CreateMutexW(attributes, (flags & 1) != 0, name);
}

__declspec(dllexport) HANDLE WINAPI CreateMutexExA(
    LPSECURITY_ATTRIBUTES attributes, LPCSTR name, DWORD flags,
    DWORD desired_access) {
  typedef HANDLE(WINAPI* Fn)(LPSECURITY_ATTRIBUTES, LPCSTR, DWORD, DWORD);
  static Fn native = kernel_proc<Fn>("CreateMutexExA");
  if (native != nullptr) return native(attributes, name, flags, desired_access);
  return CreateMutexA(attributes, (flags & 1) != 0, name);
}

__declspec(dllexport) HANDLE WINAPI CreateSemaphoreExW(
    LPSECURITY_ATTRIBUTES attributes, LONG initial_count, LONG maximum_count,
    LPCWSTR name, DWORD, DWORD desired_access) {
  typedef HANDLE(WINAPI* Fn)(LPSECURITY_ATTRIBUTES, LONG, LONG, LPCWSTR, DWORD,
                             DWORD);
  static Fn native = kernel_proc<Fn>("CreateSemaphoreExW");
  if (native != nullptr) {
    return native(attributes, initial_count, maximum_count, name, 0,
                  desired_access);
  }
  return CreateSemaphoreW(attributes, initial_count, maximum_count, name);
}

__declspec(dllexport) HANDLE WINAPI CreateWaitableTimerExW(
    LPSECURITY_ATTRIBUTES attributes, LPCWSTR name, DWORD flags,
    DWORD desired_access) {
  typedef HANDLE(WINAPI* Fn)(LPSECURITY_ATTRIBUTES, LPCWSTR, DWORD, DWORD);
  static Fn native = kernel_proc<Fn>("CreateWaitableTimerExW");
  if (native != nullptr) return native(attributes, name, flags, desired_access);
  return CreateWaitableTimerW(attributes, (flags & 1) != 0, name);
}

__declspec(dllexport) BOOL WINAPI SetWaitableTimerEx(
    HANDLE timer, const LARGE_INTEGER* due_time, LONG period,
    PTIMERAPCROUTINE completion, LPVOID completion_argument,
    PVOID wake_context, ULONG tolerable_delay) {
  typedef BOOL(WINAPI* Fn)(HANDLE, const LARGE_INTEGER*, LONG,
                           PTIMERAPCROUTINE, LPVOID, PVOID, ULONG);
  static Fn native = kernel_proc<Fn>("SetWaitableTimerEx");
  if (native != nullptr) {
    return native(timer, due_time, period, completion, completion_argument,
                  wake_context, tolerable_delay);
  }
  return SetWaitableTimer(timer, due_time, period, completion,
                          completion_argument, FALSE);
}

HANDLE WINAPI JdkXpIcmp6CreateFile(void) {
  typedef HANDLE(WINAPI* Fn)(void);
  Fn native = iphlpapi_proc<Fn>("Icmp6CreateFile");
  if (native != nullptr) return native();
  SetLastError(ERROR_CALL_NOT_IMPLEMENTED);
  return INVALID_HANDLE_VALUE;
}

DWORD WINAPI JdkXpNotifyAddrChange(PHANDLE handle, LPOVERLAPPED overlapped) {
  typedef DWORD(WINAPI* Fn)(PHANDLE, LPOVERLAPPED);
  Fn native = iphlpapi_proc<Fn>("NotifyAddrChange");
  return native != nullptr ? native(handle, overlapped)
                           : ERROR_CALL_NOT_IMPLEMENTED;
}

DWORD WINAPI JdkXpConvertLengthToIpv4Mask(ULONG mask_length, PULONG mask) {
  typedef DWORD(WINAPI* Fn)(ULONG, PULONG);
  Fn native = iphlpapi_proc<Fn>("ConvertLengthToIpv4Mask");
  if (native != nullptr) return native(mask_length, mask);
  if (mask == nullptr || mask_length > 32) return ERROR_INVALID_PARAMETER;
  const ULONG host_mask = mask_length == 0
                              ? 0
                              : 0xffffffffUL << (32 - mask_length);
  *mask = ((host_mask & 0x000000ffUL) << 24) |
          ((host_mask & 0x0000ff00UL) << 8) |
          ((host_mask & 0x00ff0000UL) >> 8) |
          ((host_mask & 0xff000000UL) >> 24);
  return NO_ERROR;
}

DWORD WINAPI JdkXpConvertInterfaceLuidToNameW(
    const NET_LUID* luid, PWSTR name, SIZE_T length) {
  typedef DWORD(WINAPI* Fn)(const NET_LUID*, PWSTR, SIZE_T);
  Fn native = iphlpapi_proc<Fn>("ConvertInterfaceLuidToNameW");
  if (native != nullptr) return native(luid, name, length);
  const ULONG index = luid_index(luid);
  if (index == 0 || name == nullptr || length < 4) {
    return ERROR_INVALID_PARAMETER;
  }
  interface_name(index, name, length);
  return NO_ERROR;
}

DWORD WINAPI JdkXpConvertInterfaceNameToLuidW(
    PCWSTR name, NET_LUID* luid) {
  typedef DWORD(WINAPI* Fn)(PCWSTR, NET_LUID*);
  Fn native = iphlpapi_proc<Fn>("ConvertInterfaceNameToLuidW");
  if (native != nullptr) return native(name, luid);
  ULONG index = 0;
  if (luid == nullptr || !parse_interface_name(name, &index)) {
    return ERROR_INVALID_NAME;
  }
  PIP_ADAPTER_ADDRESSES adapters = nullptr;
  DWORD result = load_xp_adapters(AF_UNSPEC, &adapters);
  if (result != NO_ERROR) return result;
  result = ERROR_INVALID_NAME;
  for (PIP_ADAPTER_ADDRESSES current = adapters; current != nullptr;
       current = current->Next) {
    if (adapter_index(current) == index || current->IfIndex == index ||
        current->Ipv6IfIndex == index) {
      *luid = adapter_luid(current);
      result = NO_ERROR;
      break;
    }
  }
  HeapFree(GetProcessHeap(), 0, adapters);
  return result;
}

VOID WINAPI JdkXpFreeMibTable(PVOID memory) {
  typedef VOID(WINAPI* Fn)(PVOID);
  Fn native = iphlpapi_proc<Fn>("FreeMibTable");
  if (native != nullptr) {
    native(memory);
  } else if (memory != nullptr) {
    HeapFree(GetProcessHeap(), 0, memory);
  }
}

HANDLE WINAPI JdkXpIcmpCreateFile(void) {
  typedef HANDLE(WINAPI* Fn)(void);
  Fn native = iphlpapi_proc<Fn>("IcmpCreateFile");
  if (native != nullptr) return native();
  SetLastError(ERROR_CALL_NOT_IMPLEMENTED);
  return INVALID_HANDLE_VALUE;
}

DWORD WINAPI JdkXpGetAnycastIpAddressTable(
    ADDRESS_FAMILY family, PMIB_ANYCASTIPADDRESS_TABLE* table) {
  typedef DWORD(WINAPI* Fn)(ADDRESS_FAMILY, PMIB_ANYCASTIPADDRESS_TABLE*);
  Fn native = iphlpapi_proc<Fn>("GetAnycastIpAddressTable");
  return native != nullptr ? native(family, table)
                           : xp_get_anycast_table(family, table);
}

BOOL WINAPI JdkXpIcmpCloseHandle(HANDLE handle) {
  typedef BOOL(WINAPI* Fn)(HANDLE);
  Fn native = iphlpapi_proc<Fn>("IcmpCloseHandle");
  if (native != nullptr) return native(handle);
  SetLastError(ERROR_CALL_NOT_IMPLEMENTED);
  return FALSE;
}

DWORD WINAPI JdkXpIcmpSendEcho(
    HANDLE handle, IPAddr destination, LPVOID request, WORD request_size,
    PIP_OPTION_INFORMATION options, LPVOID reply, DWORD reply_size,
    DWORD timeout) {
  typedef DWORD(WINAPI* Fn)(HANDLE, IPAddr, LPVOID, WORD,
                            PIP_OPTION_INFORMATION, LPVOID, DWORD, DWORD);
  Fn native = iphlpapi_proc<Fn>("IcmpSendEcho");
  if (native != nullptr) {
    return native(handle, destination, request, request_size, options, reply,
                  reply_size, timeout);
  }
  SetLastError(ERROR_CALL_NOT_IMPLEMENTED);
  return 0;
}

DWORD WINAPI JdkXpIcmpSendEcho2Ex(
    HANDLE handle, HANDLE event, FARPROC apc, PVOID context,
    IPAddr source, IPAddr destination, LPVOID request, WORD request_size,
    PIP_OPTION_INFORMATION options, LPVOID reply, DWORD reply_size,
    DWORD timeout) {
  typedef DWORD(WINAPI* ExFn)(HANDLE, HANDLE, FARPROC, PVOID, IPAddr, IPAddr,
                              LPVOID, WORD, PIP_OPTION_INFORMATION, LPVOID,
                              DWORD, DWORD);
  ExFn native = iphlpapi_proc<ExFn>("IcmpSendEcho2Ex");
  if (native != nullptr) {
    return native(handle, event, apc, context, source, destination, request,
                  request_size, options, reply, reply_size, timeout);
  }
  typedef DWORD(WINAPI* LegacyFn)(HANDLE, HANDLE, FARPROC, PVOID, IPAddr,
                                  LPVOID, WORD, PIP_OPTION_INFORMATION, LPVOID,
                                  DWORD, DWORD);
  LegacyFn legacy = iphlpapi_proc<LegacyFn>("IcmpSendEcho2");
  if (legacy != nullptr) {
    return legacy(handle, event, apc, context, destination, request,
                  request_size, options, reply, reply_size, timeout);
  }
  SetLastError(ERROR_CALL_NOT_IMPLEMENTED);
  return 0;
}

ULONG WINAPI JdkXpGetAdaptersAddresses(
    ULONG family, ULONG flags, PVOID reserved,
    PIP_ADAPTER_ADDRESSES addresses, PULONG size) {
  GetAdaptersAddressesFn native =
      iphlpapi_proc<GetAdaptersAddressesFn>("GetAdaptersAddresses");
  return native != nullptr
             ? native(family, flags, reserved, addresses, size)
             : ERROR_CALL_NOT_IMPLEMENTED;
}

DWORD WINAPI JdkXpIcmp6SendEcho2(
    HANDLE handle, HANDLE event, FARPROC apc, PVOID context,
    SOCKADDR_IN6* source, SOCKADDR_IN6* destination, LPVOID request,
    WORD request_size, PIP_OPTION_INFORMATION options, LPVOID reply,
    DWORD reply_size, DWORD timeout) {
  typedef DWORD(WINAPI* Fn)(HANDLE, HANDLE, FARPROC, PVOID, SOCKADDR_IN6*,
                            SOCKADDR_IN6*, LPVOID, WORD,
                            PIP_OPTION_INFORMATION, LPVOID, DWORD, DWORD);
  Fn native = iphlpapi_proc<Fn>("Icmp6SendEcho2");
  if (native != nullptr) {
    return native(handle, event, apc, context, source, destination, request,
                  request_size, options, reply, reply_size, timeout);
  }
  SetLastError(ERROR_CALL_NOT_IMPLEMENTED);
  return 0;
}

DWORD WINAPI JdkXpGetIfEntry2(PMIB_IF_ROW2 row) {
  typedef DWORD(WINAPI* Fn)(PMIB_IF_ROW2);
  Fn native = iphlpapi_proc<Fn>("GetIfEntry2");
  return native != nullptr ? native(row) : xp_get_if_entry2(row);
}

DWORD WINAPI JdkXpGetIfTable2(PMIB_IF_TABLE2* table) {
  typedef DWORD(WINAPI* Fn)(PMIB_IF_TABLE2*);
  Fn native = iphlpapi_proc<Fn>("GetIfTable2");
  return native != nullptr ? native(table) : xp_get_if_table2(table);
}

DWORD WINAPI JdkXpGetUnicastIpAddressTable(
    ADDRESS_FAMILY family, PMIB_UNICASTIPADDRESS_TABLE* table) {
  typedef DWORD(WINAPI* Fn)(ADDRESS_FAMILY, PMIB_UNICASTIPADDRESS_TABLE*);
  Fn native = iphlpapi_proc<Fn>("GetUnicastIpAddressTable");
  return native != nullptr ? native(family, table)
                           : xp_get_unicast_table(family, table);
}

}  // extern "C"
