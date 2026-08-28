# Minecraft 26 release installer source

The current release uses `minecraft26-release/legacy-openjdk.nsi` and its
upgrade auditor. The OS-specific release configuration and exact payload
manifest are in that directory. See the repository's `LEGACY_WINDOWS_BUILD.md`
for build commands and `LEGACY_WINDOWS_RELEASE.md` for artifact hashes.

The installer requires administrator access, verifies its target OS, and keeps
the runtime within its installation directory. It does not set global PATH or
JAVA_HOME or modify Windows DLLs. The upgrade auditor identifies modified or
additional files before replacement and requires explicit confirmation.

Other installer directories are retained historical build sources, not the
entry point for the current release.
