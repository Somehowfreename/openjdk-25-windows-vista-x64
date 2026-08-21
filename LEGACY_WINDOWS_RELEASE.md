# OpenJDK 25.0.4 for XP x64 — Minecraft 26 Vanilla 1.0.0

## Release asset

| Target | File | SHA-256 |
| --- | --- | --- |
| Windows XP Professional x64 Edition SP2 | `OpenJDK25U-jdk_x64_windows-xp_25.0.4_minecraft-r14.exe` | `EEEB734A072BC9278129786D60D11D6CC913C3D7145D3ED7361B8B5ED4267337` |

Optional trusted-root package for a fresh XP x64 SP2 installation:

| File | SHA-256 |
| --- | --- |
| `XP-x64-Certificates-Installer.zip` | `5F1E62D683A4FE38B53949751678C7AA16549891D19138F805166241EF962AA2` |

Optional manual certificate-store importer:

| File | SHA-256 |
| --- | --- |
| `import-sst-xp-x64.exe` | `C368BB7FF15812AF72DACFE206B4A8267CCE0A7B9190823F333610F99D0BC24E` |

Payload manifest:

| File | SHA-256 |
| --- | --- |
| `jdk25-xp-x64-PAYLOAD-SHA256SUMS.txt` | `37AC768DBA1AEF39BABE7E8933764995BCE752C7363ADA9E64D1BAD88B5A0C9C` |

`r14` preserves the automatic native routing used by Minecraft 26.1 through
26.2 and the LWJGL 3.4.2/isolated SDL3 compatibility required by Minecraft 26.3
Snapshot 9. It adds a two-stage launcher that sets the bundled XP DirectSound
configuration before the real JVM/OpenAL process loads, eliminating the
bare-metal OpenAL crackling observed with its default XP output configuration.
It is an internal package revision, not a beta designation.

## Provenance

- Upstream repository: `https://github.com/openjdk/jdk25u-dev.git`
- Upstream baseline: `jdk-25.0.4.1+0` / `jdk-25.0.4+7`
- Binary payload source commit:
  `cbf0aa68aafb4cdc0d96a18d35f7785ba3341f42`
- Release documentation/preparation commit: recorded by the final release tag
- Public release tag: `v1.0.0`

The final `v1.0.0` tag may add checksums and release metadata without changing
the qualified r14 installer payload.

## Important notes

- The installer and payload are x86-64 only.
- The installer is unsigned; verify SHA-256 before execution.
- No Windows system DLL is installed or replaced.
- Global `PATH` and `JAVA_HOME` are not changed.
- The bare-metal test used unmodified official XP x64 SP2 media with no
  post-SP2 updates. Correct drivers and current trusted roots were installed;
  Legacy Update was not required for the qualified application behavior.
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
