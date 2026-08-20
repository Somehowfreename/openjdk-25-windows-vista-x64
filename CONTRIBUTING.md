# Contributing

Compatibility reports and carefully scoped fixes are welcome.

## Before opening an issue

Confirm that the problem occurs with the exact supported configuration in
[MINECRAFT_RELEASE.md](MINECRAFT_RELEASE.md). Include:

- Windows edition, service pack, architecture, and whether it is a VM;
- installer filename and SHA-256;
- launcher name and version;
- selected Java executable;
- graphics adapter and driver;
- exact reproduction steps;
- launcher log and Minecraft `logs/latest.log`;
- whether the software-renderer launcher changes the result.

Remove account tokens, usernames, server addresses, and other personal
information from logs.

## Pull requests

Keep port-specific changes narrow and application-local. Native Windows APIs
must remain preferred whenever the host provides compatible behavior; fallbacks
should activate only when the target operating system lacks the required
functionality. Do not add global system-DLL replacement or operating-system
patching.

Run relevant build, import-audit, payload-hash, and VM lifecycle checks and
describe the results in the pull request. Changes intended for OpenJDK generally
rather than this XP port should follow the
[OpenJDK Developers' Guide](https://openjdk.org/guide/) and be proposed
upstream.

All contributions must comply with the repository license and applicable
OpenJDK contribution policies.
