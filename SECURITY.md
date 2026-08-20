# Security policy

## Windows XP warning

Windows XP is no longer supported by Microsoft. This project makes a specific
OpenJDK/Minecraft configuration run; it does not make Windows XP safe for
general Internet exposure. Use network isolation, backups, and an appropriate
security posture for an obsolete operating system.

## Reporting a port vulnerability

For vulnerabilities introduced by the XP compatibility layer, launcher,
packaging scripts, or installer, use GitHub's private vulnerability-reporting
feature when it is enabled for this repository. Do not publish exploit details
in a normal issue before maintainers have had time to assess them.

Ordinary compatibility defects that have no security impact may be filed as
GitHub issues using the bug-report template.

## Upstream OpenJDK vulnerabilities

For vulnerabilities in OpenJDK itself, follow the
[OpenJDK Vulnerability Policy](https://openjdk.org/groups/vulnerability/report).

The installer is currently unsigned. Always verify the SHA-256 published on the
GitHub Release before running it.
