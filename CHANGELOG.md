# Changelog

## 1.0.0 — 2026-08-20

First supported release for Windows XP Professional x64 Edition SP2.

- backports OpenJDK 25.0.4 to the NT 5.2 x86-64 target;
- keeps compatibility components application-local;
- provides native-GPU and software-rendered Minecraft launchers;
- supports official, authenticated Minecraft Java Edition 26.1, 26.1.1,
  26.1.2, and 26.2 Vanilla through official MultiMC 0.7.0-4274;
- supports Minecraft 26.3 Snapshot 9 Vanilla for playable single-player worlds
  through the added LWJGL 3.4.2 MemoryUtil and isolated SDL3 compatibility
  components;
- performs XP-compatible native routing automatically without modifying
  MultiMC libraries or Minecraft JARs;
- applies a process-local, bare-metal-tested XP DirectSound configuration that
  prevents OpenAL crackling without changing Windows or MultiMC settings;
- validates Java/Javac startup, world lifecycles, saving, normal shutdown,
  audio, Microsoft account sign-in, and main-release online multiplayer;
- includes source, build notes, per-file payload verification, release hashes,
  legal notices, and an uninstall entry;
- does not include Fabric, NeoForge, Forge, individual mods, Vista, 32-bit
  Windows, or unvalidated Minecraft versions.
