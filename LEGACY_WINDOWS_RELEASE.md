# OpenJDK 25.0.4 for XP x64 — Minecraft 26 Vanilla 1.0.0

## Release asset

| Target | File | SHA-256 |
| --- | --- | --- |
| Windows XP Professional x64 Edition SP2 | `OpenJDK25U-jdk_x64_windows-xp_25.0.4_minecraft-r12.exe` | `24B474733682A854D30316185425332E18BE9B80A88768DD86A1D50B1338BB3E` |

Optional manual certificate-store importer:

| File | SHA-256 |
| --- | --- |
| `import-sst-xp-x64.exe` | `C368BB7FF15812AF72DACFE206B4A8267CCE0A7B9190823F333610F99D0BC24E` |

Payload manifest:

| File | SHA-256 |
| --- | --- |
| `jdk25-xp-x64-PAYLOAD-SHA256SUMS.txt` | `EA7F6DDB0686A1A11C293DC363BCC9FD59F641E7C28CB76A086E3A03B377A070` |

`r12` is the release build that adds the LWJGL 3.4.2 MemoryUtil compatibility
surface and isolated SDL3 routing required by Minecraft 26.3 Snapshot 9 while
preserving the automatic native routing used by the main 26.1–26.2 releases.
It is an internal package revision, not a beta designation.

## Provenance

- Upstream repository: `https://github.com/openjdk/jdk25u-dev.git`
- Upstream baseline: `jdk-25.0.4.1+0` / `jdk-25.0.4+7`
- Binary payload source commit:
  `d8ed72c2da0e5912e54c738d36cc8efdc3d0b475`
- Release documentation/preparation commit: recorded by the final release tag
- Public release tag: `v1.0.0`

The final `v1.0.0` tag may add checksums and release metadata without changing
the qualified r12 installer payload.

## Important notes

- The installer and payload are x86-64 only.
- The installer is unsigned; verify SHA-256 before execution.
- No Windows system DLL is installed or replaced.
- Global `PATH` and `JAVA_HOME` are not changed.
- Select installed `bin\minecraft-javaw.exe` for real hardware. Use
  `bin\minecraft-javaw-software.exe` only as the slower CPU-rendered fallback.
- The installer contains no Minecraft game files, Mojang assets, account
  credentials, or launcher authentication data.
- This is an independent community build, not an official OpenJDK or Adoptium
  release or support channel.

## Certified application target

Official, authenticated, non-demo Minecraft Java Edition 26.1, 26.1.1, 26.1.2,
and 26.2 Vanilla through official MultiMC 0.7.0-4274 on Windows XP Professional
x64 Edition SP2 are fully tested. Minecraft 26.3 Snapshot 9 is tested for
launch, audio, playable single-player world generation, save/reload, and normal
exit; multiplayer has not been tested. See
[LEGACY_WINDOWS_TEST_MATRIX.md](LEGACY_WINDOWS_TEST_MATRIX.md) for completed
checks and explicitly excluded configurations.
