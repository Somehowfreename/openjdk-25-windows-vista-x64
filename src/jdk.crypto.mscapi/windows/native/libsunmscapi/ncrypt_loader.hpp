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

#ifndef JDK_CRYPTO_MSCAPI_NCRYPT_LOADER_HPP
#define JDK_CRYPTO_MSCAPI_NCRYPT_LOADER_HPP

#include <ncrypt.h>

bool JdkNCryptAvailable();

SECURITY_STATUS WINAPI JdkNCryptDecrypt(
        NCRYPT_KEY_HANDLE, PBYTE, DWORD, VOID*, PBYTE, DWORD, DWORD*, DWORD);
SECURITY_STATUS WINAPI JdkNCryptDeleteKey(NCRYPT_KEY_HANDLE, DWORD);
SECURITY_STATUS WINAPI JdkNCryptEncrypt(
        NCRYPT_KEY_HANDLE, PBYTE, DWORD, VOID*, PBYTE, DWORD, DWORD*, DWORD);
SECURITY_STATUS WINAPI JdkNCryptExportKey(
        NCRYPT_KEY_HANDLE, NCRYPT_KEY_HANDLE, LPCWSTR, NCryptBufferDesc*,
        PBYTE, DWORD, DWORD*, DWORD);
SECURITY_STATUS WINAPI JdkNCryptFreeObject(NCRYPT_HANDLE);
SECURITY_STATUS WINAPI JdkNCryptGetProperty(
        NCRYPT_HANDLE, LPCWSTR, PBYTE, DWORD, DWORD*, DWORD);
SECURITY_STATUS WINAPI JdkNCryptImportKey(
        NCRYPT_PROV_HANDLE, NCRYPT_KEY_HANDLE, LPCWSTR, NCryptBufferDesc*,
        NCRYPT_KEY_HANDLE*, PBYTE, DWORD, DWORD);
SECURITY_STATUS WINAPI JdkNCryptOpenStorageProvider(
        NCRYPT_PROV_HANDLE*, LPCWSTR, DWORD);
SECURITY_STATUS WINAPI JdkNCryptSignHash(
        NCRYPT_KEY_HANDLE, VOID*, PBYTE, DWORD, PBYTE, DWORD, DWORD*, DWORD);
SECURITY_STATUS WINAPI JdkNCryptTranslateHandle(
        NCRYPT_PROV_HANDLE*, NCRYPT_KEY_HANDLE*, HCRYPTPROV, HCRYPTKEY,
        DWORD, DWORD);
SECURITY_STATUS WINAPI JdkNCryptVerifySignature(
        NCRYPT_KEY_HANDLE, VOID*, PBYTE, DWORD, PBYTE, DWORD, DWORD);

// Keep all call sites unchanged while ensuring the linker never creates a
// static dependency on ncrypt.dll. Windows 7 uses the native entry points;
// XP receives NTE_NOT_SUPPORTED and stays on the legacy CryptoAPI path.
#define NCryptDecrypt JdkNCryptDecrypt
#define NCryptDeleteKey JdkNCryptDeleteKey
#define NCryptEncrypt JdkNCryptEncrypt
#define NCryptExportKey JdkNCryptExportKey
#define NCryptFreeObject JdkNCryptFreeObject
#define NCryptGetProperty JdkNCryptGetProperty
#define NCryptImportKey JdkNCryptImportKey
#define NCryptOpenStorageProvider JdkNCryptOpenStorageProvider
#define NCryptSignHash JdkNCryptSignHash
#define NCryptTranslateHandle JdkNCryptTranslateHandle
#define NCryptVerifySignature JdkNCryptVerifySignature

#endif // JDK_CRYPTO_MSCAPI_NCRYPT_LOADER_HPP
