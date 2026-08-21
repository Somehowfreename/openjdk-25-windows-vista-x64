# Minecraft 26 Vanilla release guide

This guide covers the supported configuration in release 1.0.0:

- Windows XP Professional x64 Edition SP2;
- OpenJDK 25.0.4 from this repository;
- official MultiMC 0.7.0-4274;
- official, authenticated Minecraft Java Edition 26.1, 26.1.1, 26.1.2, and
  26.2 Vanilla;
- Minecraft 26.3 Snapshot 9 Vanilla for playable single-player worlds.

Only versions marked **Pass** in
[LEGACY_WINDOWS_TEST_MATRIX.md](LEGACY_WINDOWS_TEST_MATRIX.md) are release
qualified. Mod loaders, individual mods, Vista, 32-bit Windows, and other game
versions are outside this release.

## Choose the correct Java executable

- `bin\minecraft-javaw.exe`: recommended GUI launcher for real XP x64 hardware
  with a suitable graphics driver;
- `bin\minecraft-java.exe`: the same native-GPU path with a diagnostic console;
- `bin\minecraft-javaw-software.exe`: slower CPU-rendered GUI fallback;
- `bin\minecraft-java-software.exe`: CPU-rendered fallback with a diagnostic
  console.

The ordinary `java.exe` and `javaw.exe` remain general-purpose launchers and do
not activate Minecraft compatibility routing. The four Minecraft launchers
resolve every support file relative to the installed JDK. They do not replace
system DLLs or modify global `PATH` or `JAVA_HOME`.

## Beginner installation

1. Confirm the computer runs XP Professional x64 Edition SP2, has the correct
   date and time, and has current chipset, network, audio, and graphics drivers.
2. Install the current [Legacy Update](https://legacyupdate.net/) release, use
   it to install all applicable XP x64 updates, restart, and scan again. Repeat
   until no applicable updates remain.
3. Verify the JDK installer SHA-256 against
   [LEGACY_WINDOWS_RELEASE.md](LEGACY_WINDOWS_RELEASE.md), then run it as an
   administrator.
4. Download the official Windows archive from
   [multimc.org](https://multimc.org/#Download), extract it to a local folder,
   and run `MultiMC.exe`. During first-launch setup, its Java file picker may
   hide nonstandard executable names. If `minecraft-javaw.exe` is not listed,
   type or paste this complete path directly into the Java-path field:

   `C:\Program Files\Legacy OpenJDK\jdk-25.0.4-xp-x64\bin\minecraft-javaw.exe`

   This manual-entry workaround applies only to the first-launch picker. After
   the launcher opens, **Settings > Java > Browse** displays
   `minecraft-javaw.exe` and it can be selected normally.
5. Click the face/profile button in the upper-right, choose **Manage Accounts**,
   then **Add Microsoft**. Follow the device-code instructions. It is fine to
   open the displayed web address on another trusted computer or phone.
6. Click **Add Instance**, select a supported Minecraft 26 Vanilla version, and
   create the instance.
7. Right-click the instance, choose **Edit Instance**, open **Settings**, and
   enable the Java override. Select `minecraft-javaw.exe` using the normal Java
   picker, or confirm that the path is exactly:

   `C:\Program Files\Legacy OpenJDK\jdk-25.0.4-xp-x64\bin\minecraft-javaw.exe`

8. Set maximum memory to `4096 MiB` if the computer has sufficient RAM. Do not
   add JVM compatibility flags.
9. Double-click the instance. MultiMC downloads the official game files and the
   JDK routes the XP-compatible native components automatically.

If the game cannot create an OpenGL window or its graphics are corrupt, change
only the selected executable to `minecraft-javaw-software.exe` and retry. The
software path is much slower because it renders on the CPU.

## Certificate requirements

MultiMC must establish modern HTTPS connections to Microsoft, Xbox, Mojang,
and Minecraft services. The computer's clock and trusted-root store must be
current.

The recommended route is the latest Legacy Update release. Its installer
refreshes the root-certificate store and restores the update path on XP x64.
Use Legacy Update 1.13.2 or newer, verify its checksum on the
[official release-history page](https://legacyupdate.net/releases), install all
applicable updates, restart, and rescan until none remain before configuring
MultiMC. Legacy Update is a community-maintained delivery mechanism; the
Windows updates it installs are Microsoft-issued updates.

### Manual certificate route

Use this only if you intentionally do not want Legacy Update:

1. On a currently supported Windows computer, open Command Prompt as an
   administrator.
2. Generate a serialized store directly from Microsoft's Windows Update trust
   service:

   ```cmd
   certutil -generateSSTFromWU WURoots.sst
   ```

3. Copy `WURoots.sst` and the release asset `import-sst-xp-x64.exe` to a local
   folder on XP. Verify the importer's published SHA-256 first.
4. Log on to XP as a local administrator, open Command Prompt in that folder,
   and run:

   ```cmd
   import-sst-xp-x64.exe WURoots.sst ROOT
   ```

5. Restart XP, then add the Microsoft account in MultiMC.

The importer's source is in
[`legacy-windows/tools/xp-cert-import`](legacy-windows/tools/xp-cert-import).
No certificates are bundled by this project. Do not install a root bundle from
an unknown mirror; adding roots changes trust for the whole computer.

## Automatic native-library routing

No MultiMC or Minecraft files need to be replaced. The launchers automatically
make LWJGL use the application-local XP-compatible OpenAL, GLFW, FreeType,
OpenGL support, and other native modules installed with this JDK. This applies
to every Minecraft 26 instance that uses one of the four Minecraft launchers.

The launcher also points OpenAL Soft at the bundled `alsoft-xp.ini` before the
JVM starts. That file selects XP's native DirectSound backend, stereo 16-bit
48 kHz output, and the bare-metal-tested 1024-frame/four-period buffer. The
setting is process-local: it does not change Windows audio settings, other
programs, MultiMC, or the user's global OpenAL configuration. An advanced user
can set `ALSOFT_CONF` before launching to supply a different OpenAL Soft config.

Do not patch JARs, make library files read-only, replace files under MultiMC's
`libraries` directory, or add `java.library.path`/`org.lwjgl.librarypath`
arguments. Those changes can defeat MultiMC's integrity checks or bypass the
automatic routing.

## Manual repair and verification

Use these steps if an instance does not start automatically:

1. In the instance's **Edit Instance > Settings** page, select the executable
   using the normal Java picker or confirm the path is exactly:

   `C:\Program Files\Legacy OpenJDK\jdk-25.0.4-xp-x64\bin\minecraft-javaw.exe`

   Do not select ordinary `java.exe` or `javaw.exe`.
2. Remove custom JVM arguments, especially `java.library.path`,
   `org.lwjgl.librarypath`, or manually added native-library paths.
3. Confirm these files exist in the installed JDK's `bin` directory:
   `minecraft-javaw.exe`, `lwjgl.dll`, `lwjgl341.dll`, `SDL3.dll`, `SDLS.dll`,
   and `SDLU.dll`. Do not obtain individual DLLs from third-party download
   sites. If any are absent, verify the release installer checksum and run that
   installer again as an administrator to repair the complete payload.
   Also confirm this audio configuration exists:

   `C:\Program Files\Legacy OpenJDK\jdk-25.0.4-xp-x64\minecraft\26.2\compat\alsoft-xp.ini`
4. Create a new unmodified Vanilla instance of the same game version and point
   it to `minecraft-javaw.exe`. This separates a damaged instance from a Java
   installation problem without changing existing worlds.
5. For a visible diagnostic console, temporarily select
   `minecraft-java.exe`. Copy the MultiMC log and Minecraft crash report before
   closing the console.
6. If native GPU startup fails, change only the executable to
   `minecraft-javaw-software.exe`. If that works, install the correct XP x64
   graphics driver before returning to `minecraft-javaw.exe`.

The installer also places matching support files in `minecraft-software` for
the CPU-rendered fallback. Reinstall the complete package instead of copying
files between these directories. Never edit a Minecraft JAR or MultiMC's
download cache as a repair step.

## Troubleshooting

### Microsoft sign-in or downloads fail

- Correct the XP date, time, and time zone.
- Finish the certificate/update procedure above and restart.
- Confirm ordinary HTTPS access and DNS resolution work.
- Retry the device-code flow; the web page can be completed on another device.

### The game exits while loading native libraries

- Confirm the instance points to `minecraft-javaw.exe` or
  `minecraft-javaw-software.exe` from this project—not ordinary `javaw.exe`.
- Remove custom Java arguments and manual LWJGL/OpenAL replacements.
- Re-run the JDK installer to repair its application-local components.

### The game opens but performance is extremely poor

`minecraft-javaw-software.exe` intentionally renders on the CPU. Install the
correct XP x64 GPU driver and try `minecraft-javaw.exe`. Real-hardware speed is
determined primarily by that driver and GPU.

### Audio crackles or contains static

- Confirm the instance uses this project's `minecraft-javaw.exe`, then fully
  close and restart Minecraft.
- Confirm `minecraft\26.2\compat\alsoft-xp.ini` exists under the installed JDK.
- Remove any custom `ALSOFT_CONF` or `ALSOFT_DRIVERS` environment override.
- Run the release installer again as an administrator to repair the complete
  wrapper payload; do not copy an unrelated `OpenAL.dll` into MultiMC.
- If the problem remains, include the audio device and driver version in the
  issue report along with sanitized MultiMC and Minecraft logs.

### Reporting an issue

Include the Minecraft version, selected launcher executable, hardware, GPU
driver version, and sanitized MultiMC/Minecraft logs. Never upload
`accounts.json`, access tokens, authorization codes, passwords, or private
server addresses.

## Validated behavior

All main releases from 26.1 through 26.2 passed Microsoft account sign-in,
official download, title-screen startup, audio, authenticated multiplayer,
world creation, rendering and player input, saving, reload, and normal exit.
Minecraft 26.3 Snapshot 9 passed launch, audio, playable single-player world
generation, saving, reload, and normal exit; its multiplayer path has not been
tested. Installer and payload checks are recorded separately in the release
matrix.

The installer is unsigned. Always verify its published SHA-256 before running
it. Physical GPU behavior depends on the installed XP x64 graphics driver; the
software renderer is the portable fallback.
