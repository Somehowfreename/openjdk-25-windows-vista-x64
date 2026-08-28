# OpenJDK 25 for Windows Vista x64

OpenJDK 25.0.4 for Windows Vista SP2 x64, with automatic Minecraft 26
compatibility. This is the separate Vista package; use its Vista installer
and launcher executables, not the XP package. No One-Core-API or system-wide
extended kernel is required.

## Supported configuration

- Windows Vista SP2 x64 with the correct chipset, network, audio and graphics drivers.
- Minecraft 26.1 through 26.2: vanilla, Fabric and NeoForge.
- Single-player, local/LAN servers, and online servers for those main releases.
- MultiMC and the launcher-specific OLauncher entry point.
- Minecraft 26.3 Snapshot 10: working vanilla single-player.

**Fabric and NeoForge support is included for Minecraft 26.1–26.2.
Individual mods have not been tested.** A working loader does not guarantee
that every mod or native dependency supports Vista.

**Minecraft 26.3 mod loaders are not supported yet.** Snapshot 10 works in
single-player. Multiplayer is expected to work, but has not been verified:
no compatible public server was available for testing. Please report results
or problems through [GitHub Issues](https://github.com/Somehowfreename/openjdk-25-windows-vista-x64/issues).

See the [configuration matrix](LEGACY_WINDOWS_TEST_MATRIX.md) for the specific
loader versions. This release covers only the listed Minecraft 26 configurations.

## Before installing

1. Install Windows Vista SP2 **64-bit**, with the correct hardware drivers.
   A graphics driver providing the required OpenGL support is necessary.
2. Set the correct date, time and time zone before attempting HTTPS downloads
   or Microsoft account sign-in.
3. Download `Vista-x64-Certificates-Installer.zip` from
   [Releases](https://github.com/Somehowfreename/openjdk-25-windows-vista-x64/releases/latest).
   Extract the ZIP completely and open the enclosed
   `Vista-x64-Certificates-Installer` folder. Right-click
   `Install Certificates.bat` and choose **Run as administrator**. Accept
   Vista's UAC prompt. Keep the BAT, `import-sst-vista-x64.exe`, and
   `WURoots.sst` in the same folder. Wait for **SUCCESS**, then restart Vista.
4. Run the Vista OpenJDK installer from the same release as an administrator.

The installation does not require a Legacy Update session or an extended
kernel. Keeping applicable Microsoft updates installed is still recommended
for general security; Vista remains an unsupported operating system.

The default installation folder is:

`C:\Program Files\Legacy OpenJDK\jdk-25.0.4-vista-x64`

The installer does not replace Windows system DLLs or change global `PATH`
or `JAVA_HOME`. Close games and launchers before upgrading, and back up any
files you have added to or modified in the JDK directory before accepting
an installer replacement warning.

## Configure MultiMC

1. Download the official Windows archive from [multimc.org](https://multimc.org/#Download).
2. Extract it completely to a normal local folder, for example `C:\Games\MultiMC`.
   Do not run the launcher inside a ZIP or from a network/shared folder.
3. Run `MultiMC.exe` normally. Add your account using **Manage Accounts > Add Microsoft**.
   You can complete the device-code web page on a modern computer or phone.
4. In **Settings > Java**, select:

   `C:\Program Files\Legacy OpenJDK\jdk-25.0.4-vista-x64\bin\minecraft-javaw-multimc.exe`

   MultiMC's **first-launch** Java picker may hide this executable. Enter the
   full path manually in that initial dialog, or cancel it and use
   **Settings > Java > Browse** once the main window opens. The normal
   settings picker shows the executable.
5. Click **Add Instance** and choose the supported Minecraft 26 version.
6. Check that any per-instance Java override uses the same executable.
7. Set maximum memory to `4096 MiB` if the computer has enough RAM. No extra
   compatibility JVM flags need to be entered.
8. Launch normally.

The legacy filename `bin\minecraft-javaw.exe` is a physical, byte-identical
copy of the named MultiMC executable. New configurations should use
`minecraft-javaw-multimc.exe` to make the launcher choice clear.

### Fabric or NeoForge

For Minecraft 26.1–26.2, use **Edit Instance > Version** to install either
Fabric or NeoForge for the exact game version. Use one loader per instance.
The same Java executable handles vanilla and these loaders. Refer to the
[configuration matrix](LEGACY_WINDOWS_TEST_MATRIX.md) for tested versions.

No individual mods have been tested. A mod may require native libraries or
Windows APIs unavailable on Vista even when its loader works.

## OLauncher

Use [OLauncher](https://github.com/olauncher/olauncher) from its official
project and sign in using its normal Microsoft-account flow. In the profile's
Java settings, select:

`C:\Program Files\Legacy OpenJDK\jdk-25.0.4-vista-x64\bin\minecraft-javaw-olauncher.exe`

Do not substitute the MultiMC executable for OLauncher. Loader profiles must
be installed for the matching game version using the loader's supported
installation procedure; this JDK does not add a loader installer to OLauncher's UI.

If downloads stall, use an OLauncher build containing its resumable-download
and completed-file validation fix. Launcher download behavior is separate
from the JDK's game compatibility.

## Compatibility and graphics

The launcher-specific executable selects the compatible native libraries
automatically. Do not replace downloaded launcher JARs or DLLs manually.
Compatibility behavior is application-local. Native operating-system exports
are used where available, with fallbacks for missing functions. The Vista
wrapper also includes application-level behavior specific to Vista; it is
not simply the XP installer renamed.

Use the normal launcher executables on physical hardware. The software-rendering
executables under `bin\vmtests` are for environments lacking suitable hardware
OpenGL support and are substantially slower.

## Install certificates manually

You do not have to run the certificate installer or trust its supplied SST.

1. On a supported, Internet-connected Windows computer, open an administrator
   Command Prompt in an empty folder and run:

   ```cmd
   certutil -generateSSTFromWU WURoots.sst
   certutil -hashfile WURoots.sst SHA256
   ```

2. To use the automated importer with your own Microsoft-generated roots,
   replace the ZIP's `WURoots.sst` with that file. Keep it beside the BAT and
   importer and run **Install Certificates.bat > Run as administrator** on Vista.
3. To use **no executable from this project**, open the SST on the supported
   computer, review its roots, and export the required certificates as
   DER-encoded `.cer` files. Transfer those files to Vista.
4. On Vista, run `mmc` as administrator and approve UAC. Add **Certificates**
   for **Computer account > Local computer**, then open
   **Trusted Root Certification Authorities > Certificates**. Use
   **Action > All Tasks > Import** to import the reviewed certificates.
5. Restart Vista when finished.

Microsoft documents [certutil and SST generation](https://learn.microsoft.com/windows-server/administration/windows-commands/certutil)
and [the computer trusted-root store](https://learn.microsoft.com/windows-hardware/drivers/install/trusted-root-certification-authorities-certificate-store).
Root imports change trust for the whole computer. Do not use untrusted mirrors.
The certificate ZIP contains the same instructions and the importer source is
included in this repository.

## Troubleshooting, source and licensing

- [Troubleshooting and manual verification](MINECRAFT_RELEASE.md)
- [Supported configurations](LEGACY_WINDOWS_TEST_MATRIX.md)
- [Build instructions](LEGACY_WINDOWS_BUILD.md)
- [Release files and hashes](LEGACY_WINDOWS_RELEASE.md)
- [Port architecture](LEGACY_WINDOWS_PORT.md)
- [Changelog](CHANGELOG.md), [support](SUPPORT.md), and [security](SECURITY.md)

Minecraft game files, account credentials and access tokens are not bundled.
Own the game and sign in through your launcher. Never put account files or
access tokens in a bug report.

This is an independent community port of [OpenJDK](https://github.com/openjdk/jdk25u-dev),
not an official Oracle, Adoptium, Microsoft, Mojang, MultiMC or OLauncher
product. See [LICENSE](LICENSE), [ADDITIONAL_LICENSE_INFO](ADDITIONAL_LICENSE_INFO),
and [ASSEMBLY_EXCEPTION](ASSEMBLY_EXCEPTION). Third-party components retain
their own licenses.
