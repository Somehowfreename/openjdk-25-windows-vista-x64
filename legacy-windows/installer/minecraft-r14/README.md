# Minecraft r14 installer driver

This directory contains the release-specific installer driver for OpenJDK
25.0.4 on Windows XP Professional x64 Edition SP2. `r14` includes the automatic
native routing used by Minecraft 26.1 through 26.2 and the additional LWJGL
3.4.2 and isolated SDL3 compatibility components required by Minecraft 26.3
Snapshot 9. It also applies the bare-metal-tested XP DirectSound configuration
inside the Minecraft process to prevent OpenAL crackling.

The script requires:

- a clean checkout of this repository;
- the assembled r14 JDK runtime image;
- NSIS 3.12 or newer.

Example:

```powershell
.\build-installer.ps1 `
  -RuntimeDirectory C:\release\openjdk-25.0.4-xp-x64-minecraft-wrapper-r14 `
  -Makensis C:\tools\nsis\makensis.exe `
  -OutputDirectory C:\release\installer
```

It verifies that every r14 compatibility component is present, records the
source commit, generates a payload SHA-256 manifest, treats NSIS warnings as
errors, and emits an installer checksum file. The shared NSIS definition stays
in the adjacent `minecraft-beta-r9` directory because its installer behavior
did not change in r14.
