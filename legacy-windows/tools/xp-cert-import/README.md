# XP serialized-certificate-store importer

`import-sst` is a small CryptoAPI utility for importing certificates from a
serialized certificate store (`.sst`) into the local computer's `ROOT` or
`CA` store on Windows XP x64.

It does not download certificates and no certificate authorities are bundled
with this repository. Only use an SST produced directly by a source you trust.
For Microsoft's current third-party root set, generate the SST on a supported
Windows computer with:

```cmd
certutil -generateSSTFromWU WURoots.sst
```

Build the utility with an x64 Windows compiler that targets NT 5.2 and links
against `crypt32.lib`. The included `build.ps1` accepts MSVC 14.29 and Windows
SDK roots and emits an NT 5.2 console executable. Copy the resulting executable
and `WURoots.sst` to XP, open Command Prompt as an administrator, and run:

```cmd
import-sst-xp-x64.exe WURoots.sst ROOT
```

Adding trust anchors changes system-wide certificate trust. Review the source
and the SST contents first. The recommended beginner route is to use the
current Legacy Update release, which refreshes the XP root store as part of its
setup.
