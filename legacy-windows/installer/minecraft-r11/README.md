# Minecraft r11 installer driver

This directory contains the release-specific installer driver for OpenJDK
25.0.4 on Windows XP Professional x64 Edition SP2. `r11` adds automatic
selection of the application-local XP-compatible native modules used by
Minecraft 26 and official MultiMC.

The script requires:

- a clean checkout of this repository;
- the assembled r11 JDK runtime image;
- NSIS 3.12 or newer.

Example:

```powershell
.\build-installer.ps1 `
  -RuntimeDirectory C:\release\openjdk-25.0.4-xp-x64-minecraft-wrapper-r11 `
  -Makensis C:\tools\nsis\makensis.exe `
  -OutputDirectory C:\release\installer
```

It records the source commit, generates a payload SHA-256 manifest, treats NSIS
warnings as errors, and emits an installer checksum file. The shared NSIS
definition is preserved in the adjacent `minecraft-beta-r9` directory because
its installer behavior did not change in r11.
