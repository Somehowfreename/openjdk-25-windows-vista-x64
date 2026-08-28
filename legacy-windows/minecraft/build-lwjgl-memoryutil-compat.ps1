[CmdletBinding()]
param(
    [ValidatePattern('^r[0-9]+$')]
    [string] $OutputRevision = 'r1',

    [string] $LegacyLwjgl,

    [string] $LegacyDefinition,
    [string] $WorkspaceRoot
)

$ErrorActionPreference = 'Stop'
$workspace = if ($WorkspaceRoot) { (Resolve-Path -LiteralPath $WorkspaceRoot).Path } else { (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..\..\..')).Path }
$msvc = Join-Path $workspace 'work\toolchains\msvc-14.29-portable\Contents\VC\Tools\MSVC\14.29.30133'
$sdk = Join-Path $workspace 'work\toolchains\winsdk-10.0.19041-portable\Windows Kits\10'
$sdkVersion = '10.0.19041.0'
$cl = Join-Path $msvc 'bin\Hostx64\x64\cl.exe'
$link = Join-Path $msvc 'bin\Hostx64\x64\link.exe'
$lib = Join-Path $msvc 'bin\Hostx64\x64\lib.exe'
$reader = Join-Path $workspace 'work\toolchains\llvm-mingw-20260616-msvcrt-x86_64\bin\llvm-readobj.exe'
$source = Join-Path $PSScriptRoot 'lwjgl_memoryutil_compat.c'

if (-not $LegacyLwjgl) {
    $LegacyLwjgl = Join-Path $workspace 'work\compat\minecraftxp\preload\lwjgl.dll'
}
if (-not $LegacyDefinition) {
    $LegacyDefinition = Join-Path $workspace 'work\compat\minecraftxp\preload\lwjgl.def'
}

$outputRoot = Join-Path $workspace "work\release-builds\lwjgl-memoryutil-compat-$OutputRevision"
$objects = Join-Path $outputRoot 'objects'
$payload = Join-Path $outputRoot 'payload'
$proxyDefinition = Join-Path $objects 'lwjgl-memoryutil-compat.def'
$legacyImportDefinition = Join-Path $objects 'lwjgl341-import.def'
$legacyImportLibrary = Join-Path $objects 'lwjgl341.lib'
$object = Join-Path $objects 'lwjgl-memoryutil-compat.obj'
$proxy = Join-Path $payload 'lwjgl.dll'
$legacyTarget = Join-Path $payload 'lwjgl341.dll'

foreach ($required in @($cl, $link, $lib, $reader, $source, $LegacyLwjgl, $LegacyDefinition)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required compatibility build input is missing: $required"
    }
}
if (Test-Path -LiteralPath $outputRoot) {
    throw "Refusing to replace preserved LWJGL compatibility build: $outputRoot"
}
foreach ($directory in @($objects, $payload)) {
    [IO.Directory]::CreateDirectory($directory) | Out-Null
}

$legacyExports = @(
    Get-Content -LiteralPath $LegacyDefinition |
        Where-Object {
            $_ -and
            $_ -notmatch '^\s*;' -and
            $_ -notmatch '^\s*(LIBRARY|EXPORTS)\b'
        } |
        ForEach-Object { $_.Trim() }
)
if ($legacyExports.Count -lt 1) {
    throw "No exports were found in $LegacyDefinition"
}
$localExports = @(
    'Java_org_lwjgl_system_MemoryUtil_ngetPageSize=lwjgl_memoryutil_get_page_size',
    'Java_org_lwjgl_system_MemoryUtil_ngetCacheLineSize=lwjgl_memoryutil_get_cache_line_size'
)
foreach ($localExport in $localExports) {
    $exportName = $localExport.Substring(0, $localExport.IndexOf('='))
    if ($legacyExports -match "^$([Regex]::Escape($exportName))(?:\s|$)") {
        throw "The certified legacy native unexpectedly already exports $exportName."
    }
}

$proxyExports = [Collections.Generic.List[string]]::new()
$proxyExports.Add('LIBRARY "lwjgl.dll"')
$proxyExports.Add('EXPORTS')
foreach ($localExport in $localExports) {
    $proxyExports.Add("    $localExport")
}
foreach ($legacyExport in $legacyExports) {
    $isData = $legacyExport -match '\s+DATA\s*$'
    $name = ($legacyExport -replace '\s+DATA\s*$', '').Trim()
    $line = "    $name=lwjgl341.$name"
    if ($isData) { $line += ' DATA' }
    $proxyExports.Add($line)
}
$proxyExports | Set-Content -LiteralPath $proxyDefinition -Encoding ascii

# LINK recognizes an external-module export forwarder after that module has
# been introduced by an import library.  Generate an import library whose
# internal DLL name matches the certified native's installed compatibility
# name; this does not alter the original native binary.
@('LIBRARY "lwjgl341.dll"', 'EXPORTS') + $legacyExports |
    Set-Content -LiteralPath $legacyImportDefinition -Encoding ascii
& $lib /nologo /machine:x64 "/def:$legacyImportDefinition" "/out:$legacyImportLibrary"
if ($LASTEXITCODE -ne 0) { throw 'Generating the renamed legacy LWJGL import library failed.' }

$includes = @(
    (Join-Path $msvc 'include'),
    (Join-Path $sdk "Include\$sdkVersion\ucrt"),
    (Join-Path $sdk "Include\$sdkVersion\shared"),
    (Join-Path $sdk "Include\$sdkVersion\um")
) | ForEach-Object { "/I$_" }
$libraries = @(
    "/LIBPATH:$(Join-Path $msvc 'lib\x64')",
    "/LIBPATH:$(Join-Path $sdk "Lib\$sdkVersion\ucrt\x64")",
    "/LIBPATH:$(Join-Path $sdk "Lib\$sdkVersion\um\x64")"
)

& $cl /nologo /c /TC /O2 /W4 /GS- /D_CRT_SECURE_NO_WARNINGS `
    @includes "/Fo$object" $source
if ($LASTEXITCODE -ne 0) { throw 'Compiling the LWJGL MemoryUtil compatibility shim failed.' }

& $link /nologo /dll /noentry /machine:x64 /subsystem:windows,5.02 /osversion:5.02 `
    "/def:$proxyDefinition" "/out:$proxy" $object @libraries `
    $legacyImportLibrary kernel32.lib /OPT:REF /OPT:ICF
if ($LASTEXITCODE -ne 0) { throw 'Linking the LWJGL MemoryUtil forwarding proxy failed.' }

Copy-Item -LiteralPath $LegacyLwjgl -Destination $legacyTarget

$exportDump = & $reader --coff-exports $proxy
if ($LASTEXITCODE -ne 0) { throw 'Reading the proxy export table failed.' }
$proxyExportCount = @($exportDump | Select-String -SimpleMatch 'Name: ').Count
$expectedExportCount = $legacyExports.Count + $localExports.Count
if ($proxyExportCount -ne $expectedExportCount) {
    throw "Proxy export count mismatch: expected $expectedExportCount, found $proxyExportCount."
}
if (-not ($exportDump | Select-String -SimpleMatch 'Java_org_lwjgl_system_MemoryUtil_ngetPageSize')) {
    throw 'The proxy does not export MemoryUtil.ngetPageSize.'
}
if (-not ($exportDump | Select-String -SimpleMatch 'Java_org_lwjgl_system_MemoryUtil_ngetCacheLineSize')) {
    throw 'The proxy does not export MemoryUtil.ngetCacheLineSize.'
}

$manifest = Join-Path $outputRoot 'SHA256SUMS.txt'
Get-FileHash -Algorithm SHA256 $proxy, $legacyTarget |
    ForEach-Object { '{0}  {1}' -f $_.Hash, (Split-Path -Leaf $_.Path) } |
    Set-Content -LiteralPath $manifest -Encoding ascii

Write-Output "LWJGL_MEMORYUTIL_COMPAT_PASS=$outputRoot"
Write-Output "LEGACY_EXPORTS=$($legacyExports.Count)"
Write-Output "PROXY_EXPORTS=$proxyExportCount"
Write-Output "PAYLOAD=$payload"
Write-Output "MANIFEST=$manifest"
