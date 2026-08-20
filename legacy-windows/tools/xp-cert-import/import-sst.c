/*
 * Copyright (c) 2026 Legacy Windows OpenJDK contributors.
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 only, as
 * published by the Free Software Foundation.
 */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <wincrypt.h>
#include <stdio.h>

static int import_store(const char *source_path,
                        const char *destination_name) {
  HCERTSTORE source;
  HCERTSTORE destination;
  PCCERT_CONTEXT certificate = NULL;
  DWORD imported = 0;

  source = CertOpenStore(CERT_STORE_PROV_FILENAME_A,
                         X509_ASN_ENCODING | PKCS_7_ASN_ENCODING, 0,
                         CERT_STORE_OPEN_EXISTING_FLAG |
                             CERT_STORE_READONLY_FLAG,
                         source_path);
  if (source == NULL) {
    fprintf(stderr, "Cannot open %s (error %lu).\n", source_path,
            (unsigned long)GetLastError());
    return 1;
  }

  destination = CertOpenStore(CERT_STORE_PROV_SYSTEM_A, 0, 0,
                              CERT_SYSTEM_STORE_LOCAL_MACHINE,
                              destination_name);
  if (destination == NULL) {
    fprintf(stderr, "Cannot open Local Machine\\%s (error %lu).\n",
            destination_name, (unsigned long)GetLastError());
    CertCloseStore(source, 0);
    return 1;
  }

  while ((certificate =
              CertEnumCertificatesInStore(source, certificate)) != NULL) {
    if (!CertAddCertificateContextToStore(
            destination, certificate,
            CERT_STORE_ADD_REPLACE_EXISTING_INHERIT_PROPERTIES, NULL)) {
      fprintf(stderr, "Certificate %lu failed (error %lu).\n",
              (unsigned long)(imported + 1),
              (unsigned long)GetLastError());
      CertCloseStore(destination, 0);
      CertCloseStore(source, 0);
      return 1;
    }
    ++imported;
  }

  CertCloseStore(destination, 0);
  CertCloseStore(source, 0);
  printf("Imported %lu certificate(s) into Local Machine\\%s.\n",
         (unsigned long)imported, destination_name);
  return 0;
}

int main(int argc, char **argv) {
  if (argc != 3) {
    fprintf(stderr, "Usage: import-sst.exe FILE.sst ROOT|CA\n");
    return 2;
  }

  if (lstrcmpiA(argv[2], "ROOT") != 0 &&
      lstrcmpiA(argv[2], "CA") != 0) {
    fprintf(stderr, "Destination must be ROOT or CA.\n");
    return 2;
  }

  return import_store(argv[1], argv[2]);
}
