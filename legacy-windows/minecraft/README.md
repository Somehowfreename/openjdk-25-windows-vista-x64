# Minecraft 26 wrapper source

The launcher-specific dispatchers select compatible native dependencies before
starting the private Java runtime. Their paths are resolved relative to the
installation, not a fixed launcher folder.

- `minecraft-javaw-multimc.exe`: MultiMC entry point.
- `minecraft-javaw.exe`: a byte-identical copy for existing MultiMC settings.
- `minecraft-javaw-olauncher.exe`: OLauncher entry point.
- `minecraft-java.exe`: console diagnostics.
- `bin/vmtests`: explicitly named software-rendering variants.

`minecraft_software_dispatcher.c` selects the runtime and process-local audio
settings. `minecraft_wrapper_options.cpp` supplies the native-library routes.
`jtracy_noop.cpp` provides the optional Tracy JNI surface, and
`lwjgl_memoryutil_compat.c` supplies the additional MemoryUtil entry points.
SDL's compatibility modules have private names to avoid collisions with the
JDK's modules. Windows system files and launcher downloads are not replaced.

See [build instructions](../../LEGACY_WINDOWS_BUILD.md) and the
[release scope](../../LEGACY_WINDOWS_TEST_MATRIX.md). Internal profile code is
not a support claim for configurations outside that matrix.

This project's original code follows the surrounding OpenJDK GPLv2 with
Classpath Exception licensing. Third-party components retain their licenses.
