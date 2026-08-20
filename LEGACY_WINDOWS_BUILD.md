# Building the XP x64 Minecraft 26 Vanilla release

## Source baseline

- Upstream repository: `https://github.com/openjdk/jdk25u-dev.git`
- Upstream release tag: `jdk-25.0.4.1+0` / `jdk-25.0.4+7`
- Port branch: `xp-x64-backport`

Build the normal x64 Windows JDK image using the upstream instructions in
`doc/building.md`. The port source is then processed into a release image by the
scripts under `legacy-windows/jdkxp`; that post-link step is part of the port.
The source and exact r12 wrapper/installer drivers are all contained in this
repository.

## Compatibility image prerequisites

- x64 MSVC compiler and linker
- Windows 10 SDK 10.0.19041.0, unless another version is passed explicitly
- LLVM `llvm-readobj`
- An original Windows XP Professional x64 `kernel32.dll`, used only to generate
  a valid export allow-list
- The freshly built JDK image

Example:

```powershell
.\legacy-windows\jdkxp\build-proxy.ps1 `
  -JdkImage C:\build\jdk25\images\jdk `
  -MsvcRoot C:\BuildTools\VC\Tools\MSVC\14.xx.xxxxx `
  -WindowsSdkRoot 'C:\Program Files (x86)\Windows Kits\10' `
  -LlvmReadObj C:\LLVM\bin\llvm-readobj.exe `
  -XpKernel32 C:\reference\xp-x64\kernel32.dll `
  -OutputDirectory C:\build\jdk25-proxy

.\legacy-windows\jdkxp\package-image.ps1 `
  -InputJdkImage C:\build\jdk25\images\jdk `
  -ProxyBuildDirectory C:\build\jdk25-proxy `
  -LlvmReadObj C:\LLVM\bin\llvm-readobj.exe `
  -OutputDirectory C:\release-images\jdk25-xp-x64 `
  -MapIphlpapi
```

The proxy build generates its export definition from the actual target binaries
and XP export surface. Packaging copies to a new destination, rejects an
existing output directory, rewrites only the narrow import families required by
the port, sets the NT 5.2 PE target, and emits `SHA256SUMS.txt`.

Optional Minecraft native directories can be supplied through
`-AdditionalTargetRoot` when building the proxy. This expands the process-local
forwarder surface; it does not modify Minecraft or Windows. The wrapper and
assembly sources used for release build r12 are under `legacy-windows/minecraft`.

Build the two release-specific native compatibility payloads before the wrapper:

```powershell
.\legacy-windows\minecraft\build-lwjgl-memoryutil-compat.ps1 `
  -OutputRevision r3

.\legacy-windows\minecraft\build-sdl3-isolated-compat.ps1 `
  -OutputRevision r1

.\legacy-windows\minecraft\build-minecraft-wrappers.ps1 `
  -JavaMajor 25 -OutputRevision r12 `
  -LwjglCompatRevision r3 -SdlCompatRevision r1

.\legacy-windows\minecraft\assemble-minecraft-wrapper-images.ps1 `
  -JavaMajor 25 -Revision r12 -SupportRevision r12 -TargetOs xp
```

The LWJGL build preserves the certified legacy export surface and adds only the
two MemoryUtil queries observed in LWJGL 3.4.2. The SDL build gives its broader
shell and user compatibility modules private names, preventing them from
colliding with the JDK's own modules.

## Building installers

Use NSIS 3.12 or newer and the release driver under
`legacy-windows/installer/minecraft-r12`. The release selects only the XP x64
OpenJDK 25 image. Definitions for development targets are not support claims.

```powershell
.\legacy-windows\installer\minecraft-r12\build-installer.ps1 `
  -RuntimeDirectory C:\release\openjdk-25.0.4-xp-x64-minecraft-wrapper-r12 `
  -Makensis C:\tools\nsis\makensis.exe `
  -OutputDirectory C:\release\installer
```

The driver embeds the exact source commit and payload SHA-256 manifest, treats
NSIS warnings as errors, and emits installer `SHA256SUMS.txt`. For a different
build farm, change only the explicit input/toolchain paths; do not change the
payload, source commit, or target-OS checks when reproducing release build r12.

The optional serialized-certificate-store importer can be built separately:

```powershell
.\legacy-windows\tools\xp-cert-import\build.ps1 `
  -MsvcRoot C:\toolchains\MSVC\14.29.30133 `
  -WindowsSdkRoot 'C:\Program Files (x86)\Windows Kits\10' `
  -OutputDirectory C:\release\certificate-tool
```

No certificates are part of the source or binary release. The utility accepts
only a user-supplied SST and writes to the requested local-machine certificate
store.
