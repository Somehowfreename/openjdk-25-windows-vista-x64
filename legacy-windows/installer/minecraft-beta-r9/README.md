# Minecraft 26.2 Vanilla release build r9 installer source

These are the exact NSIS template and build driver used for the XP x64 build-r9
installer. The driver also retains definitions for later, currently unsupported
development targets; the only public 1.0.0 asset certified by this repository is:

`OpenJDK25U-jdk_x64_windows-xp_25.0.4_minecraft-r9.exe`

The XP definition embeds source commit
`4fd01c697c643d0563e07c10a3d5014b2a9a7cad`, the per-file payload manifest,
OpenJDK legal files, and a self-contained uninstaller. It rejects non-x64 and
non-XP-SP2 hosts, installs side by side, and does not modify global `PATH`,
`JAVA_HOME`, or Windows system files.

The release asset SHA-256 is recorded in `../../../LEGACY_WINDOWS_RELEASE.md`.
NSIS 3.12 was used for the preserved build. The development driver expects the
workspace layout and payload paths visible in its source; adjust those input
paths when reproducing the installer in another build environment.
