# Minecraft 26 setup and troubleshooting

Follow the operating-system-specific paths and certificate instructions in
[README.md](README.md). Use this repository's installer, not the installer
from the other operating system's repository.

## Launcher selection

- MultiMC: `bin\minecraft-javaw-multimc.exe`.
- Existing MultiMC configurations may keep `bin\minecraft-javaw.exe`; the two
  files are byte-identical copies.
- OLauncher: `bin\minecraft-javaw-olauncher.exe`.
- Do not select an internal Java executable or a software-rendering executable
  from `bin\vmtests` for ordinary physical-hardware use.

If the first-launch MultiMC picker hides the required name, type the complete
path or cancel and select it through the launcher's **Settings > Java** page.
Check per-instance Java overrides too: they take precedence over global settings.

## Fabric and NeoForge

Support covers the Minecraft 26.1–26.2 configurations in
[the matrix](LEGACY_WINDOWS_TEST_MATRIX.md). Install one loader per instance,
using a loader build for that exact Minecraft version. The same launcher-specific
executable is used for vanilla and the supported loader profiles.

Individual mods have not been tested. A loader starting and loading a world
does not prove that every mod's Java code, bundled DLLs, graphics requirements
or network protocol will work. Minecraft 26.3 mod loaders are not supported yet.

## Downloads and Microsoft sign-in

Check the system clock, network connectivity and trusted roots first. Install
the OS-specific certificate ZIP, or follow the manual Microsoft certificate
instructions in the README. Root certificates do not repair every TLS or
network problem; the launcher must also support the server's TLS protocol.

Keep launchers on a normal local disk. If OLauncher stalls during downloads,
use a version containing its resumable-download and completed-file validation
fix. Do not disable certificate verification to work around a download error.

## Manual repair and verification

1. Close Minecraft and both launchers before changing the JDK installation.
2. Verify the downloaded installer against the release's `SHA256SUMS.txt`.
   On a modern Windows computer, `certutil -hashfile filename.exe SHA256`
   prints the hash. The payload manifest lists the expected installed files.
3. Check that your selected Java path points into the correct OS-specific JDK
   installation and names the proper launcher wrapper.
4. Keep the installation directory complete. Copying just a wrapper EXE is
   insufficient; it also needs the private Java runtime and native libraries.
5. Remove only custom JVM arguments or library overrides that you added
   yourself, after recording them so you can restore them. In particular,
   stale `java.library.path`, LWJGL, GLFW or OpenAL overrides can select the
   wrong files. Normal use requires no extra compatibility arguments.
6. If a packaged file is missing or modified, back up your own changes and
   reinstall the same release. Review the installer's replacement warnings.

The wrappers configure library selection before the game loads its native
dependencies. Do not manually overwrite the launcher's libraries or make its
JARs read-only. No per-instance DLL-copy script is required for supported
configurations.

## Graphics and audio

Install the correct vendor graphics and audio drivers. An absent or unsuitable
OpenGL driver is not fixed by changing launchers. Software rendering is slow
and is not the normal hardware configuration.

The compatibility package applies its audio settings to the game process.
Do not create a global audio configuration as a prerequisite. If sound is
missing or distorted, check the OS playback device and volume first, then
report the game version, audio device, driver, and launcher log.

## Multiplayer and snapshots

Minecraft 26.1–26.2 supports local/LAN and online servers. Use a server that
accepts your exact game version and any server-required client configuration.
VPN restrictions, bans and account entitlement errors are server/account
issues, not evidence of a Java compatibility failure by themselves.

Minecraft 26.3 Snapshot 10 works in vanilla single-player. Multiplayer is
expected but unverified: no compatible public server was available for the
tests. Fabric and NeoForge on Minecraft 26.3 are not supported yet.

## Reporting a problem

Include the OS and service pack, installer filename, launcher version, exact
Java wrapper path, Minecraft and loader version, graphics/audio hardware, and
steps to reproduce. Attach the relevant game or launcher log after removing
access tokens, account identifiers and unrelated personal paths. Never upload
`accounts.json`, launcher authentication data or an entire launcher folder.
