# Legacy Windows x64 port tooling

This directory contains the source and reproducible post-link tooling used by
the Windows XP Professional x64 and Windows Vista x64 release images. It is
part of the port: a build made from the modified OpenJDK source is not a release
artifact until the image has been processed by `jdkxp/package-image.ps1`.

The compatibility DLL is application-local. It does not install or replace any
Windows system DLL and affects only binaries in this JDK image. Implementations
resolve the native operating-system function first. A fallback is selected only
when the function or a representation-compatible API family is unavailable.
Windows 7 and newer should use the unmodified upstream/Temurin build instead.

`jdkxp/build-proxy.ps1` requires an x64 MSVC toolset, a Windows SDK, an original
Windows XP x64 `kernel32.dll` for its export allow-list, LLVM `llvm-readobj`, and
the freshly built JDK image. `jdkxp/package-image.ps1` copies that image to a
new destination, sets PE OS/subsystem compatibility to NT 5.2, redirects the
narrow import families through JDKXP, and writes `SHA256SUMS.txt`. Both scripts
refuse to overwrite an existing release image.

For OpenJDK 25, package with `-MapIphlpapi`. XP and Vista select the validated
provider and fallback paths only where their kernels lack the required modern
behavior; Windows 7 retains the native wepoll and operating-system facilities.
WinHTTP and NCrypt are resolved dynamically and use native host implementations
whenever present.

The compatibility sources are distributed under the same GPLv2 with Classpath
Exception terms as this OpenJDK repository. See the repository `LICENSE` file.

`build-proxy.ps1 -AdditionalTargetRoot` accepts process-local Minecraft native
and renderer directories when constructing the optional Minecraft support
package. This expands only the proxy's XP-native Kernel32 forwarder surface;
it does not modify the JDK classes, VM, or system DLLs.
