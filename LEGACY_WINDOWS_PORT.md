# Port architecture

The repository contains the OpenJDK 25.0.4 source baseline, Windows compatibility
sources, native-library adapters, launcher wrappers and installer tooling.
OpenJDK's upstream licenses and attribution are retained.

Compatibility DLLs are application-local. Native exports are resolved
when available, and implementations for unavailable operations are
used where required. Windows system DLLs are not replaced.

The public launcher executables choose the Minecraft compatibility profile,
configure process-local library and audio behavior, and start the private Java
runtime. The MultiMC compatibility filename is copied from the named MultiMC
wrapper, not built as a separate program or implemented as a shortcut.

The Vista build uses its own wrapper defines. An application-level OS-version
property selects the compatible Minecraft/Netty path; native compatibility
code still resolves the real OS exports. The XP-specific snapshot garbage
collector workaround is not enabled by the Vista build.

The native adapters cover the LWJGL bindings, windowing, audio and related
libraries needed by the supported Minecraft 26 releases. Loader support does
not extend the OS API surface for every possible third-party mod.

See the source and [build notes](LEGACY_WINDOWS_BUILD.md) for implementation
details and [release metadata](LEGACY_WINDOWS_RELEASE.md) for exact artifact
hashes. Internal build revision numbers are not Java version numbers.
