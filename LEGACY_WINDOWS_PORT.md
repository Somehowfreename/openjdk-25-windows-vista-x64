# Legacy Windows x64 port

This branch provides an OpenJDK 25.0.4 release image and installer for Windows
XP Professional x64 Edition SP2. Release 1.0.0 targets official Minecraft Java
Edition 26.2 Vanilla.

## Support status

| Operating system | Architecture | Runtime payload | Status |
| --- | --- | --- | --- |
| Windows XP Professional x64 Edition SP2 | x86-64 | OpenJDK source port plus application-local compatibility DLLs | Vanilla 1.0.0 |
| Windows Vista SP2 | x86-64 | Development target | Not included in this release |
| Windows 7 SP1 | x86-64 | Use an unmodified current OpenJDK distribution | Not built by this project |

The installers intentionally reject other operating systems and 32-bit Windows.
They do not modify Windows system DLLs, `PATH`, or `JAVA_HOME`. Each JDK is
installed side by side under `Program Files\Legacy OpenJDK` and can be removed
through Programs and Features.

## Native API policy

The compatibility layer is process-local. It first resolves and calls the
native host implementation when one exists. A compatibility implementation is
selected only when the host lacks the required export or compatible behavior.

The compatibility layer neither installs a global shim nor patches the
operating system. See [legacy-windows/README.md](legacy-windows/README.md) for
the implementation and packaging model.

The Minecraft wrapper sets process-local `ALSOFT_CONF` to its bundled XP audio
configuration before the JVM starts. OpenAL therefore uses XP's native
DirectSound implementation with the tested output format and buffer while
other Java programs and system audio remain untouched.

## Installation and launcher selection

1. Download the installer whose filename names the exact target OS.
2. Verify its SHA-256 value against `SHA256SUMS.txt`.
3. Run the installer as an administrator.
4. In the Minecraft launcher's Java settings, select the installed
   `bin\minecraft-javaw.exe` explicitly.
5. If the native graphics path cannot create the required OpenGL context, use
   `bin\minecraft-javaw-software.exe` instead.

These initial installers are unsigned. Windows may display an unknown-publisher
warning. Hash verification is required until a documented code-signing process
is introduced.

## Certification scope

The release was tested on XP x64 SP2 using official, authenticated, non-demo
Minecraft 26.1, 26.1.1, 26.1.2, and 26.2 Vanilla. World creation/loading,
rendering, player input, save/reload, audio, multiplayer, and normal exit
passed for every main release. Minecraft 26.3 Snapshot 9 passed launch, audio,
playable single-player world generation, save/reload, and normal exit;
multiplayer was not tested.

The release build verifies Java/Javac and wrapper startup, preserves the
machine environment, records the source commit and payload marker, and verifies
all 661 payload hashes. Uninstall behavior is unchanged from the previously
qualified installer definition.

See [LEGACY_WINDOWS_TEST_MATRIX.md](LEGACY_WINDOWS_TEST_MATRIX.md) for the exact
matrix and [LEGACY_WINDOWS_RELEASE.md](LEGACY_WINDOWS_RELEASE.md) for release
hashes and provenance.

## Building and redistribution

See [LEGACY_WINDOWS_BUILD.md](LEGACY_WINDOWS_BUILD.md). The source remains under
the OpenJDK GPLv2 with Classpath Exception terms in `LICENSE`,
`ADDITIONAL_LICENSE_INFO`, and `ASSEMBLY_EXCEPTION`.

Microsoft no longer supports these operating systems. Use them only in a
security posture appropriate for obsolete systems. This project does not make
the operating system itself safe for unrestricted Internet exposure.
