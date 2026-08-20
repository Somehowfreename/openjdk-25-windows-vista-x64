# Minecraft 26 wrapper source

This directory contains the source and exact build-r12 drivers for the
application-local Minecraft launchers bundled with the XP x64 installer.

## Entry points

- `minecraft-javaw.exe`: normal GUI launcher using the XP machine's native
  graphics driver;
- `minecraft-java.exe`: console equivalent for diagnostics;
- `minecraft-javaw-software.exe`: GUI launcher using the bundled software
  OpenGL renderer;
- `minecraft-java-software.exe`: console equivalent.

`minecraft_wrapper_options.cpp` supplies only the compatibility options needed
by the supported Minecraft 26 builds and resolves all support paths relative to
the installed JDK.
`minecraft_software_dispatcher.c` keeps the software renderer isolated from the
normal launcher so its `opengl32.dll` cannot shadow XP's system OpenGL module.
`jtracy_noop.cpp` provides the narrow optional Tracy JNI surface used by the
game without introducing post-XP runtime dependencies.
`lwjgl_memoryutil_compat.c` adds the two LWJGL 3.4.2 MemoryUtil queries while
the generated forwarding DLL preserves every certified legacy LWJGL export.
`build-sdl3-isolated-compat.ps1` gives SDL3's broader compatibility modules
private names so they cannot collide with modules already loaded by the JDK.

The PowerShell drivers are the exact drivers used to construct and assemble
the r12 payload. They intentionally refuse to overwrite preserved build output.
They expect the development-workspace inputs documented in
`../../LEGACY_WINDOWS_BUILD.md`; paths can be adapted for another build farm.

Minecraft, LWJGL, OpenAL Soft, GLFW, Mesa, and their assets are not relicensed
as part of this source tree. The installer contains only the compatibility
runtime components and their applicable notices; it does not contain Minecraft
game files or account credentials.

The original code in this directory is distributed under the same GPLv2 with
Classpath Exception terms as the surrounding OpenJDK repository. See
`../../LICENSE`, `../../ADDITIONAL_LICENSE_INFO`, and `../../ASSEMBLY_EXCEPTION`.
