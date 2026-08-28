# Minecraft 26 configuration matrix

Use the OpenJDK installer for the operating system named in this repository.
Both the MultiMC and OLauncher entry points use the corresponding native-library
configuration automatically.

| Minecraft | Vanilla | Fabric Loader | NeoForge |
| --- | --- | --- | --- |
| 26.1 | Supported | 0.19.3 | 26.1.0.19-beta |
| 26.1.2 | Supported | 0.19.3 | 26.1.2.97 |
| 26.2 | Supported | 0.19.3 | 26.2.0.67 |
| 26.3 Snapshot 10 | Single-player | Not supported yet | Not supported yet |

These are the specific loader builds used for validation, not a promise that
every past or future loader build works. Minecraft 26.1.1 also has working
vanilla support; its loader combinations were not separately validated.

Single-player checks cover reaching the title screen, creating and generating
a Survival world, loading and rendering terrain, visible hearts and hunger,
brief player movement, saving and returning to the menu, and normal exit.

Minecraft 26.1–26.2 supports local/LAN and online servers. Individual mods
have not been tested; loader compatibility does not establish compatibility
with arbitrary modpacks, native dependencies, or server-required client mods.

Minecraft 26.3 Snapshot 10 works in vanilla single-player. Multiplayer is
expected to work but remains unverified because no compatible public server
was available for testing. No Minecraft 26.3 mod-loader support is claimed.

New Minecraft snapshots, loader versions, hardware drivers and third-party
mods can change compatibility. Include exact version numbers in bug reports.
