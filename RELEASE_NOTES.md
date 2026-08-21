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

## Release assets

- `OpenJDK25U-jdk_x64_windows-xp_25.0.4_minecraft-r14.exe`: complete JDK and
  automatic Minecraft 26 compatibility installer.
- `import-sst-xp-x64.exe`: optional helper for importing a user-generated
  Microsoft root-certificate SST when Legacy Update is not used.
- `SHA256SUMS.txt`: release-asset checksums.

The installer is unsigned. Verify SHA-256 before running it. No Minecraft game
files, account credentials, launcher tokens, or certificate bundle are
included. This is an independent community port and not an official OpenJDK,
Adoptium, Microsoft, Mojang, Minecraft, or MultiMC release.
