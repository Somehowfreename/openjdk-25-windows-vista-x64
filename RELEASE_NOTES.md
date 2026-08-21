# OpenJDK 25.0.4 for Windows XP x64 — release 1.0.0

This release provides a 64-bit OpenJDK 25.0.4 runtime and application-local
Minecraft launchers for Windows XP Professional x64 Edition SP2.

## Tested Minecraft configurations

- Minecraft 26.1, 26.1.1, 26.1.2, and 26.2 Vanilla: Microsoft sign-in,
  official download, audio, authenticated multiplayer, playable single-player
  worlds, save/reload, and normal exit all passed.
- Minecraft 26.3 Snapshot 9 Vanilla: launch, audio, playable single-player
  world generation, save/reload, and normal exit passed. Multiplayer has not
  been tested.

Use official MultiMC 0.7.0-4274 and select:

`C:\Program Files\Legacy OpenJDK\jdk-25.0.4-xp-x64\bin\minecraft-javaw.exe`

No JVM compatibility flags, Minecraft JAR edits, read-only library files, or
manual native replacements are required. See the repository README and
`MINECRAFT_RELEASE.md` before installing.

The Minecraft Java wrapper automatically uses XP's native DirectSound backend
with the validated OpenAL output format and buffering. No per-user OpenAL file
or MultiMC audio workaround is required.

Bare-metal validation also passed from a fresh installation made with
unmodified official XP Professional x64 Edition SP2 media and no post-SP2
updates. Correct hardware drivers and current trusted-root certificates are
still required. Legacy Update is optional for this project, although installing
applicable Microsoft-issued updates remains recommended for OS security.
The final clean-room run restored a pre-driver XP image and used only newly
installed hardware drivers plus files downloaded from this release; Minecraft
launched with clean audio and no prior launcher or compatibility state.

## Release assets

- `OpenJDK25U-jdk_x64_windows-xp_25.0.4_minecraft-r14.exe`: complete JDK and
  automatic Minecraft 26 compatibility installer.
- `XP-x64-Certificates-Installer.zip`: optional one-step trusted-root package
  for fresh XP x64 SP2 systems. Its README also documents generating a fresh
  root store directly from Microsoft and importing it manually.
- `jdk25-xp-x64-PAYLOAD-SHA256SUMS.txt`: per-file hashes for all 661 installed
  JDK payload files.
- `SHA256SUMS.txt`: release-asset checksums.

The executables are unsigned. Verify SHA-256 before running them. No Minecraft
game files, account credentials, or launcher tokens are included. The optional
certificate ZIP contains a Microsoft Windows Update root-store snapshot and
clearly documents how to replace it with a newly generated Microsoft copy.
This is an independent community port and not an official OpenJDK, Adoptium,
Microsoft, Mojang, Minecraft, or MultiMC release.
