# OpenJDK 25 for Windows XP Professional x64

This project brings OpenJDK 25.0.4 to Windows XP Professional x64 Edition SP2
and provides application-local launchers for official Minecraft Java Edition
26 Vanilla.

## Supported configuration

Release 1.0.0 supports:

- Windows XP Professional x64 Edition SP2 (64-bit only);
- this project's OpenJDK 25.0.4 x64 installer;
- official MultiMC 0.7.0-4274;
- official, authenticated, non-demo Minecraft Java Edition 26.1, 26.1.1,
  26.1.2, and 26.2 Vanilla;
- Minecraft 26.3 Snapshot 9 Vanilla for playable single-player worlds.

All main releases from 26.1 through 26.2 completed Microsoft account sign-in,
download, audio, authenticated multiplayer, single-player world creation and
reload, rendering and input, saving, and normal exit. Minecraft 26.3 Snapshot 9
completed launch, audio, playable single-player world generation, save/reload,
and normal exit; multiplayer for that snapshot has not been tested. The exact
matrix is in
[LEGACY_WINDOWS_TEST_MATRIX.md](LEGACY_WINDOWS_TEST_MATRIX.md).

The Minecraft launcher automatically selects XP's native DirectSound backend
with the bare-metal-tested OpenAL output format and buffering. This prevents
the crackling produced by OpenAL Soft's default XP configuration on affected
hardware. Users do not need to create an `alsoft.ini` file or change MultiMC.

Fabric, NeoForge, Forge, individual mods, Windows Vista, 32-bit Windows, and
Minecraft versions not listed in the test matrix are not supported by this
release.

## Before installing

1. Install Windows XP Professional x64 Edition SP2 and the correct chipset,
   network, audio, and 64-bit graphics drivers for the computer.
2. Set the correct date, time, and time zone. TLS sign-in can fail when the
   clock is wrong.
3. Download `XP-x64-Certificates-Installer.zip` from this project's
   [GitHub Releases page](https://github.com/Somehowfreename/openjdk-25-windows-xp-x64/releases/latest).
   Extract it completely, open the enclosed `XP-x64-Certificates-Installer`
   folder, and double-click `Install Certificates.bat` while logged on as an
   administrator. Keep the BAT, `import-sst-xp-x64.exe`, and `WURoots.sst`
   together. Wait for **SUCCESS**, then restart XP.
4. Back up important files before using an unsupported operating system online.

Legacy Update is **not required** to run this OpenJDK or the supported
Minecraft versions. Bare-metal validation began with a fresh installation from
unmodified official Windows XP Professional x64 Edition SP2 media, with no
post-SP2 updates installed through Legacy Update or any other update service.
After the correct hardware drivers and current trusted-root certificates were
installed, the tested configurations worked.

Installing all applicable Microsoft-issued updates through the current
[Legacy Update](https://legacyupdate.net/) release is still recommended for
general operating-system security, but users do not need to wait for that
process before testing this project. Users who do not trust the supplied
certificate package can generate `WURoots.sst` directly from Microsoft's
Windows Update trust service and import it manually; see the
[manual Microsoft-root procedure](MINECRAFT_RELEASE.md#manual-certificate-route).

## Install OpenJDK 25

Download the installer from the
[GitHub Releases page](https://github.com/Somehowfreename/openjdk-25-windows-xp-x64/releases/latest)
and verify its SHA-256 against [LEGACY_WINDOWS_RELEASE.md](LEGACY_WINDOWS_RELEASE.md).
Run the installer as an administrator. It installs to:

`C:\Program Files\Legacy OpenJDK\jdk-25.0.4-xp-x64`

The installer does not replace Windows DLLs and does not alter global `PATH` or
`JAVA_HOME`.

## Install and configure MultiMC

1. Download the official Windows archive from
   [multimc.org](https://multimc.org/#Download).
2. Extract the entire archive to a normal local folder such as
   `C:\Games\MultiMC`. Do not run it from inside the ZIP or from any shared or
   network folder.
3. Run `MultiMC.exe`. During MultiMC's first-launch setup, its Java file picker
   may hide executables whose names are not the standard `java.exe` or
   `javaw.exe`. If `minecraft-javaw.exe` is not shown there, type or paste this
   complete path directly into the Java-path field:

   `C:\Program Files\Legacy OpenJDK\jdk-25.0.4-xp-x64\bin\minecraft-javaw.exe`

   Manual path entry is required only for that first-launch picker. After the
   main launcher opens, **Settings > Java > Browse** displays
   `minecraft-javaw.exe` and it can be selected normally.
4. Click the face/profile button in the upper-right, choose **Manage Accounts**,
   then **Add Microsoft**. Follow MultiMC's device-code instructions. The web
   page may be opened on a modern PC or phone.
5. Click **Add Instance**, select the desired supported Minecraft 26 Vanilla
   release, and create the instance.
6. Right-click the instance, choose **Edit Instance**, open **Settings**, and
   enable the Java-installation override. Select `minecraft-javaw.exe` using
   the normal Java picker, or confirm that the Java path is exactly:

   `C:\Program Files\Legacy OpenJDK\jdk-25.0.4-xp-x64\bin\minecraft-javaw.exe`

7. Set maximum memory to `4096 MiB` if the computer has enough physical RAM.
8. Leave the Java-arguments box unchanged. No compatibility flags are required.
9. Double-click the instance and play.

The native-GPU launcher above is the recommended path for real hardware. If the
installed XP graphics driver cannot provide the required OpenGL behavior, use
this slower CPU-rendered fallback instead by selecting it in the normal Java
picker or entering its complete path in the same box:

`C:\Program Files\Legacy OpenJDK\jdk-25.0.4-xp-x64\bin\minecraft-javaw-software.exe`

Do not replace files inside MultiMC's `libraries` directory or Minecraft JARs.
The included launchers route the compatible LWJGL, OpenAL, GLFW, FreeType, and
SDL components automatically for supported Minecraft 26 instances. They also
apply the verified XP DirectSound configuration only inside the Minecraft Java
process. Recovery and manual verification steps are in
[MINECRAFT_RELEASE.md](MINECRAFT_RELEASE.md#manual-repair-and-verification).

## Privacy and game ownership

Minecraft, launcher branding, Mojang assets, account credentials, and tokens
are not bundled. Users must own Minecraft and sign in through MultiMC's normal
Microsoft device-code flow. The JDK installer never reads or stores MultiMC
account data. Never publish `accounts.json`; its tokens can grant account
access.

## What the port changes

The port uses application-local compatibility DLLs and NT 5.2-compatible PE
targets. It does not replace Windows system DLLs or patch the operating system.
Native operating-system APIs are used when available; compatibility
implementations are selected only when XP lacks the required export or
behavior.

Technical documentation:

- [Minecraft release and troubleshooting guide](MINECRAFT_RELEASE.md)
- [Validation matrix](LEGACY_WINDOWS_TEST_MATRIX.md)
- [Port architecture](LEGACY_WINDOWS_PORT.md)
- [Build and reproduction notes](LEGACY_WINDOWS_BUILD.md)
- [Release provenance and hashes](LEGACY_WINDOWS_RELEASE.md)
- [Support policy](SUPPORT.md)
- [Security policy](SECURITY.md)

## Building from source

The complete corresponding OpenJDK and XP compatibility source is included in
this repository. Start with
[LEGACY_WINDOWS_BUILD.md](LEGACY_WINDOWS_BUILD.md), which records the upstream
baseline, compiler and SDK requirements, XP export reference, compatibility
image construction, Minecraft native-wrapper builds, final runtime assembly,
NSIS installer reproduction, and certificate-helper build. The normal OpenJDK
build system is documented in [doc/building.md](doc/building.md).

Release reproduction intentionally uses explicit input and toolchain paths and
refuses to overwrite preserved build outputs. A reproduced binary is expected
to be built from a clean checkout so its installer can embed the exact source
commit and a complete per-file payload manifest.

## Licensing and attribution

This repository is derived from the official
[OpenJDK 25 Updates development repository](https://github.com/openjdk/jdk25u-dev)
at the documented OpenJDK 25.0.4 baseline. Source is provided under OpenJDK's
GPLv2 with Classpath Exception terms; see [LICENSE](LICENSE),
[ADDITIONAL_LICENSE_INFO](ADDITIONAL_LICENSE_INFO), and
[ASSEMBLY_EXCEPTION](ASSEMBLY_EXCEPTION).

This is an independent community port. It is not an Oracle, OpenJDK, Eclipse
Foundation, Adoptium, MultiMC, Microsoft, Mojang, or Minecraft support
offering. Microsoft no longer supports Windows XP. Use obsolete operating
systems only with an appropriate security posture.
