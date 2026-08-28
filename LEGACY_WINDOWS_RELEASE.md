# OpenJDK 25.0.4 for Windows Vista x64 — release files

Release tag: `v1.0.0`. Minecraft support is limited to the configurations in
[the matrix](LEGACY_WINDOWS_TEST_MATRIX.md).

| Download | Purpose |
| --- | --- |
| `OpenJDK25U-jdk_x64_windows-vista_25.0.4.exe` | OS-specific OpenJDK and launcher wrappers |
| `Vista-x64-Certificates-Installer.zip` | Certificate BAT, importer, Microsoft root snapshot and manual instructions |
| `jdk25-vista-x64-PAYLOAD-SHA256SUMS.txt` | Per-file runtime hashes |
| `SHA256SUMS.txt` | Hashes of the other three assets |

GitHub also generates source ZIP/tar archives. Those are source code, not the
installer. The certificate importer is inside its ZIP; no separate EXE download
is needed.

## SHA-256

- Installer: `5DB1C22A53382AB9B1472B31B190BE8A38C99186C7424D5D0729E83E5D0DA40C`
- Certificate ZIP: `7E27BBD9B18E2EBAC39CDE69856419D534CA4C3EBA0E3D7129569FAB92E3AF47`
- Payload manifest: `2ECBACDAA3427199688BB5CE9AE38FC2F6820AAE53E67239668ED9D52545C1B8`

## Source and package provenance

The installer is the preserved r41 package, unchanged for publication.
Its original embedded source field is `local-candidate-vista-r41`,
a build label rather than a Git commit hash. This release tag contains the
corresponding OpenJDK changes, native adapters, wrapper code and installer
sources; the payload manifest identifies the exact included files.

The Vista package uses the r41 Vista build definitions. Its application-level OS-version property selects a compatible game-library path, while native compatibility code resolves the real OS exports. It does not enable the XP-only snapshot collector workaround.

## Packaging and safety

- x86-64 only; the installer checks its OS and service pack.
- Installer is unsigned; verify hashes before running it.
- Windows DLLs, global PATH and JAVA_HOME are not changed.
- Close games and launchers before upgrading. Back up local JDK modifications
  before approving replacement.
- Game files, accounts and authentication tokens are not bundled.
- Build and packaging instructions are in [LEGACY_WINDOWS_BUILD.md](LEGACY_WINDOWS_BUILD.md).
