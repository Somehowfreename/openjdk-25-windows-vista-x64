# Release 1.0.0 validation matrix

Release 1.0.0 supports official, authenticated, non-demo Minecraft Java
Edition 26.1, 26.1.1, 26.1.2, and 26.2 Vanilla with OpenJDK 25.0.4 and
official MultiMC 0.7.0-4274 on XP x64 SP2. Minecraft 26.3 Snapshot 9 Vanilla is
qualified separately for its tested single-player behavior.

| Operating system | Vanilla | Fabric | NeoForge |
| --- | --- | --- | --- |
| Windows XP Professional x64 Edition SP2 | Pass | Not included | Not included |
| Windows Vista SP2 x64 | Not included | Not included | Not included |

## Installer certification

| Installer | Package build | Java/Javac | Embedded metadata | Global environment | 658 payload hashes | Uninstall safety definition |
| --- | --- | --- | --- | --- | --- | --- | --- |
| XP x64 build r12 | Pass | Pass | Pass | No `PATH` or `JAVA_HOME` changes | Pass (658/658) | Pass (registered path and marker guarded) |

“Embedded metadata” includes the product identity, target operating system,
payload marker, source commit, and per-file payload manifest. The installer
definition writes product and uninstall registry entries but does not alter
global `PATH` or `JAVA_HOME`.

## Minecraft lifecycle certification

| Minecraft version | Microsoft sign-in | Download and launch | Audio | Multiplayer | Create/render/navigate world | Save/reload | Normal exit |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 26.1 Vanilla | Pass | Pass | Pass | Pass | Pass | Pass | Pass |
| 26.1.1 Vanilla | Pass | Pass | Pass | Pass | Pass | Pass | Pass |
| 26.1.2 Vanilla | Pass | Pass | Pass | Pass | Pass | Pass | Pass |
| 26.2 Vanilla | Pass | Pass | Pass | Pass | Pass | Pass | Pass |
| 26.3 Snapshot 9 Vanilla | Pass | Pass | Pass | Not tested | Pass | Pass | Pass |

For release qualification, the Vanilla lifecycle covers:

1. create world, render, navigate, save, and exit normally;
2. reload the saved world, render, navigate, save, and exit normally.

The application-local graphics paths, Java Sound DirectSound path, and OpenAL
sound engine completed successfully. Normal Microsoft device-code sign-in and
authenticated multiplayer passed for every listed main release. Snapshot 9
multiplayer has not been tested.

Physical GPU-driver behavior remains hardware-dependent. This matrix does not
certify mod loaders, individual mods, Vista, 32-bit Windows, or Minecraft
versions not listed above.
