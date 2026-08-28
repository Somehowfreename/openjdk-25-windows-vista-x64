# Security

Windows XP and Windows Vista no longer receive ordinary Microsoft security
support. A current Java runtime and root certificates do not make the entire
operating system secure. Use network isolation and an appropriate security
policy for legacy machines.

Use only trusted installers and official launcher downloads. Check release
hashes. Installing a root certificate changes system-wide trust; the README
describes obtaining roots directly from Microsoft without using this project's
automated importer.

Never publish launcher account files, Microsoft refresh/access tokens,
passwords, private keys or full authenticated launch commands in an issue.
For a suspected security vulnerability, use GitHub's private vulnerability
reporting feature when available, rather than posting secrets publicly.
