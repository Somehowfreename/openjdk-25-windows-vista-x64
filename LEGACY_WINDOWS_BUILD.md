# Building OpenJDK 25 and the Minecraft 26 package

This repository contains the modified OpenJDK source, application-local Windows
compatibility code, Minecraft wrappers, and installer sources. Build on a
modern x64 Windows host, not on XP or Vista. Read OpenJDK's
[Windows build instructions](doc/building.md) first.

## Tools and source

- Use this release tag's complete source tree; checking out unmodified upstream
  OpenJDK alone omits the port changes.
- Upstream project: <https://github.com/openjdk/jdk25u-dev>.
- A boot JDK suitable for building JDK 25, Cygwin, GNU Make, and the Windows
  dependencies listed in `doc/building.md`.
- MSVC 14.29.30133 and Windows SDK 10.0.19041.0 for the legacy native tools.
- LLVM `llvm-readobj` for PE import/export inspection.
- NSIS 3.12 for packaging.
- An original XP Professional x64 `kernel32.dll` from your own installation,
  used as an export reference. Windows DLLs are not distributed here.

Follow the Windows-specific configure options in the upstream instructions,
then build the x64 release image with `make images`. The normal OpenJDK image
is an intermediate result: the post-link compatibility stage below is required.

## Process-local Windows compatibility

These scripts accept explicit tool and image paths:

```powershell
.\legacy-windows\jdkxp\build-proxy.ps1 `
  -JdkImage C:\build\jdk25\images\jdk `
  -MsvcRoot C:\BuildTools\VC\Tools\MSVC\14.29.30133 `
  -WindowsSdkRoot 'C:\Program Files (x86)\Windows Kits\10' `
  -LlvmReadObj C:\LLVM\bin\llvm-readobj.exe `
  -XpKernel32 C:\reference\xp-x64\kernel32.dll `
  -OutputDirectory C:\build\jdk25-proxy

.\legacy-windows\jdkxp\package-image.ps1 `
  -InputJdkImage C:\build\jdk25\images\jdk `
  -ProxyBuildDirectory C:\build\jdk25-proxy `
  -LlvmReadObj C:\LLVM\bin\llvm-readobj.exe `
  -OutputDirectory C:\build\legacy-jdk25 `
  -MapIphlpapi
```

Use `-AdditionalTargetRoot` when generating the proxy for additional native
dependencies. It extends the required export surface; it does not install
anything into Windows. Packaging refuses to overwrite an existing image.

## Minecraft native-library and wrapper stage

The wrapper drivers are workspace-oriented, not a self-contained dependency
downloader. They require the prepared native dependencies, import libraries,
and JDK build output referenced at the top of each script. The exact published
payload is recorded in `legacy-windows/installer/minecraft26-release/PAYLOAD-SHA256SUMS.txt`.
Do not replace native libraries with arbitrary newer binaries: their exported
ABI and legacy OS imports matter.

Use `-WorkspaceRoot` to select a build workspace. Its `work` directory contains
the following inputs (the script headers give the full relative paths):

- `sources/openjdk25u-xp`: this source tree and its `w25xp-release-final1` build;
- `toolchains`: the compiler, SDK and LLVM tools listed above;
- `compat/jdkxp`: the scripts from `legacy-windows/jdkxp`;
- `compat/minecraftxp/preload`: compatible native DLLs and import libraries;
- `minecraft`: prepared native profiles and the relevant JNA artifacts;
- `artifacts/openjdk-25.0.4-xp-x64-certified-final`: the base legacy JDK image,
  including the native support inputs consumed by assembly.

The underlying third-party projects are [LWJGL](https://github.com/LWJGL/lwjgl3),
[GLFW](https://github.com/glfw/glfw), [OpenAL Soft](https://github.com/kcat/openal-soft),
[SDL](https://github.com/libsdl-org/SDL), [JNA](https://github.com/java-native-access/jna),
and [Mesa](https://gitlab.freedesktop.org/mesa/mesa). Retain their licenses and
notices when preparing native inputs. The release does not bundle Minecraft
game files, Microsoft build tools, or Windows system DLLs as source dependencies.

After preparing those inputs, from this repository:

```powershell
.\legacy-windows\minecraft\build-lwjgl-memoryutil-compat.ps1 `
  -WorkspaceRoot C:\build\legacy-workspace -OutputRevision r3
.\legacy-windows\minecraft\build-sdl3-isolated-compat.ps1 `
  -WorkspaceRoot C:\build\legacy-workspace -OutputRevision r1
.\legacy-windows\minecraft\build-minecraft-wrappers.ps1 `
  -WorkspaceRoot C:\build\legacy-workspace -JavaMajor 25
.\legacy-windows\minecraft\assemble-minecraft-wrapper-images.ps1 `
  -WorkspaceRoot C:\build\legacy-workspace -JavaMajor 25
```

This repository's wrapper and assembly defaults select its own OS and build
revision. XP uses the preserved r31 minimal-options source together with the
current Minecraft 26 path; Vista uses its own r41 compile definitions.
See [release metadata](LEGACY_WINDOWS_RELEASE.md). Existing build output is
preserved rather than overwritten.

The small profile-selection test can run without launching Minecraft:

```powershell
.\legacy-windows\minecraft\tests\test-minecraft-profile-detection.ps1 `
  -WorkspaceRoot C:\build\legacy-workspace
```

## Installer and certificate utility

`legacy-windows/installer/minecraft26-release` contains the NSIS script,
upgrade-auditor source, original packaging driver, and a path-parameterized
packaging entry point. Build the auditor, then package a completed runtime:

```powershell
.\legacy-windows\installer\minecraft26-release\build-upgrade-audit.ps1 `
  -WorkspaceRoot C:\build\legacy-workspace -OutputDirectory C:\build\auditor
.\legacy-windows\installer\minecraft26-release\build-installer.ps1 `
  -RuntimeDirectory C:\build\complete-runtime `
  -Makensis C:\tools\nsis-3.12\makensis.exe `
  -UpgradeAuditor C:\build\auditor\legacy-openjdk-upgrade-audit.exe `
  -OutputDirectory C:\build\installer
```

By default, packaging requires the exact published payload manifest. A developer
packaging a deliberately changed runtime must use `-AllowDifferentPayload`;
the resulting installer is a new build requiring its own validation.

The certificate importer is built separately:

```powershell
.\legacy-windows\tools\xp-cert-import\build.ps1 `
  -MsvcRoot C:\BuildTools\VC\Tools\MSVC\14.29.30133 `
  -WindowsSdkRoot 'C:\Program Files (x86)\Windows Kits\10' `
  -OutputDirectory C:\build\certificate-tool
```

The same NT 5.2-compatible importer implementation is used for Vista under the
Vista-specific filename. The release ZIP supplies the OS-specific BAT/README
and Microsoft root snapshot separately from the JDK. The README explains how
to obtain a fresh SST directly from Microsoft instead.

## Reproducibility limits

The release installers are the preserved tested binaries, not newly rebuilt
copies. Their original embedded source labels are build labels, not Git commit
IDs; the release tag and payload manifest record the corresponding source and
files. A rebuild may differ because of compiler versions, timestamps, path
metadata or native inputs. Do not claim an identical binary unless its hash
actually matches. A fresh clone does not by itself fetch and prepare every
third-party native dependency.
