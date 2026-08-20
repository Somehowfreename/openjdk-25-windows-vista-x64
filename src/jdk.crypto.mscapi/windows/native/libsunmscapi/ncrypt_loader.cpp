/*
 * Copyright (c) 2026, OpenJDK XP Backport contributors. All rights reserved.
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
 *
 * This code is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 only, as
 * published by the Free Software Foundation.  This particular file is subject
 * to the "Classpath" exception as provided in the LICENSE file that
 * accompanied this code.
 */

#include <windows.h>
#include <wincrypt.h>
#include <ncrypt.h>

namespace {

FARPROC ncrypt_proc(const char* name) {
    HMODULE module = GetModuleHandleW(L"ncrypt.dll");
    if (module == nullptr) {
        module = LoadLibraryW(L"ncrypt.dll");
    }
    return module == nullptr ? nullptr : GetProcAddress(module, name);
}

} // namespace

bool JdkNCryptAvailable() {
    return ncrypt_proc("NCryptOpenStorageProvider") != nullptr;
}

#define JDK_NCRYPT_DISPATCH(Name, Parameters, Arguments)                 \
    SECURITY_STATUS WINAPI Jdk##Name Parameters {                       \
        typedef SECURITY_STATUS (WINAPI *Function) Parameters;          \
        Function function = reinterpret_cast<Function>(ncrypt_proc(#Name)); \
        return function == nullptr ? NTE_NOT_SUPPORTED : function Arguments; \
    }

JDK_NCRYPT_DISPATCH(NCryptDecrypt,
        (NCRYPT_KEY_HANDLE key, PBYTE input, DWORD input_size,
         VOID* padding, PBYTE output, DWORD output_size,
         DWORD* result_size, DWORD flags),
        (key, input, input_size, padding, output, output_size, result_size,
         flags))

JDK_NCRYPT_DISPATCH(NCryptDeleteKey,
        (NCRYPT_KEY_HANDLE key, DWORD flags),
        (key, flags))

JDK_NCRYPT_DISPATCH(NCryptEncrypt,
        (NCRYPT_KEY_HANDLE key, PBYTE input, DWORD input_size,
         VOID* padding, PBYTE output, DWORD output_size,
         DWORD* result_size, DWORD flags),
        (key, input, input_size, padding, output, output_size, result_size,
         flags))

JDK_NCRYPT_DISPATCH(NCryptExportKey,
        (NCRYPT_KEY_HANDLE key, NCRYPT_KEY_HANDLE export_key,
         LPCWSTR blob_type, NCryptBufferDesc* parameters, PBYTE output,
         DWORD output_size, DWORD* result_size, DWORD flags),
        (key, export_key, blob_type, parameters, output, output_size,
         result_size, flags))

JDK_NCRYPT_DISPATCH(NCryptFreeObject,
        (NCRYPT_HANDLE object),
        (object))

JDK_NCRYPT_DISPATCH(NCryptGetProperty,
        (NCRYPT_HANDLE object, LPCWSTR property, PBYTE output,
         DWORD output_size, DWORD* result_size, DWORD flags),
        (object, property, output, output_size, result_size, flags))

JDK_NCRYPT_DISPATCH(NCryptImportKey,
        (NCRYPT_PROV_HANDLE provider, NCRYPT_KEY_HANDLE import_key,
         LPCWSTR blob_type, NCryptBufferDesc* parameters,
         NCRYPT_KEY_HANDLE* key, PBYTE data, DWORD data_size, DWORD flags),
        (provider, import_key, blob_type, parameters, key, data, data_size,
         flags))

JDK_NCRYPT_DISPATCH(NCryptOpenStorageProvider,
        (NCRYPT_PROV_HANDLE* provider, LPCWSTR provider_name, DWORD flags),
        (provider, provider_name, flags))

JDK_NCRYPT_DISPATCH(NCryptSignHash,
        (NCRYPT_KEY_HANDLE key, VOID* padding, PBYTE hash, DWORD hash_size,
         PBYTE signature, DWORD signature_size, DWORD* result_size,
         DWORD flags),
        (key, padding, hash, hash_size, signature, signature_size, result_size,
         flags))

JDK_NCRYPT_DISPATCH(NCryptTranslateHandle,
        (NCRYPT_PROV_HANDLE* provider, NCRYPT_KEY_HANDLE* key,
         HCRYPTPROV legacy_provider, HCRYPTKEY legacy_key,
         DWORD legacy_key_spec, DWORD flags),
        (provider, key, legacy_provider, legacy_key, legacy_key_spec, flags))

JDK_NCRYPT_DISPATCH(NCryptVerifySignature,
        (NCRYPT_KEY_HANDLE key, VOID* padding, PBYTE hash, DWORD hash_size,
         PBYTE signature, DWORD signature_size, DWORD flags),
        (key, padding, hash, hash_size, signature, signature_size, flags))

#undef JDK_NCRYPT_DISPATCH
