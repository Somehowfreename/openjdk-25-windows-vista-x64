WINDOWS VISTA X64 CERTIFICATES INSTALLER
========================================

This package updates the Local Computer trusted-root certificate store on
Windows Vista SP2 x64. Current trusted roots are required for modern HTTPS,
Microsoft sign-in, Mojang services, launcher metadata, and Minecraft downloads.

Quick method
------------

1. Extract the complete Vista-x64-Certificates-Installer folder locally. Do
   not run it from inside the ZIP or from a network share.
2. Correct the computer's date, time, and time zone.
3. Confirm these files are together:

   Install Certificates.bat
   import-sst-vista-x64.exe
   WURoots.sst

4. Right-click Install Certificates.bat and choose Run as administrator.
5. Wait for SUCCESS, then restart Windows Vista.

The BAT writes certificate-install.log beside itself if troubleshooting is
needed. It changes only the Local Computer trusted-root certificate store.
It does not install Windows updates, Java, a launcher, Minecraft, or an
extended-kernel package.

Obtain a fresh root store directly from Microsoft
-------------------------------------------------

You do not have to trust the bundled WURoots.sst. On a currently supported,
Internet-connected Windows computer, open Command Prompt as administrator,
change to a new empty folder, and run:

certutil -generateSSTFromWU WURoots.sst

Record its SHA-256 if wanted:

certutil -hashfile WURoots.sst SHA256

Copy that Microsoft-generated file over the supplied WURoots.sst, keep it next
to the importer and BAT, and run the BAT as administrator on Vista.

Direct import without the BAT
-----------------------------

Open an elevated Command Prompt in the extracted folder and run:

import-sst-vista-x64.exe WURoots.sst ROOT

Confirm that it reports success, then restart Vista.

Manual route without the project executable
--------------------------------------------

On a supported Windows computer, open the Microsoft-generated WURoots.sst,
inspect it, and export the roots you require as individual DER-encoded .cer
files. On Vista, run mmc, add the Certificates snap-in for the Computer account,
open Trusted Root Certification Authorities, and import the inspected .cer
files. Restart Vista afterward. Import only certificates obtained from a source
you trust.

Microsoft documentation:
https://learn.microsoft.com/windows-server/administration/windows-commands/certutil
https://learn.microsoft.com/windows-hardware/drivers/install/trusted-root-certification-authorities-certificate-store

