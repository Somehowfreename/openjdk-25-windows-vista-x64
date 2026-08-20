[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $JdkImage,
    [Parameter(Mandatory = $true)][string] $MsvcRoot,
    [Parameter(Mandatory = $true)][string] $WindowsSdkRoot,
    [Parameter(Mandatory = $true)][string] $LlvmReadObj,
    [Parameter(Mandatory = $true)][string] $XpKernel32,
    [string[]] $AdditionalTargetRoot = @(),
    [string] $WindowsSdkVersion = '10.0.19041.0',
    [string] $OutputDirectory = (Join-Path $PSScriptRoot 'build')
)

$ErrorActionPreference = 'Stop'
$image = (Resolve-Path -LiteralPath $JdkImage).Path
$msvc = (Resolve-Path -LiteralPath $MsvcRoot).Path
$sdk = (Resolve-Path -LiteralPath $WindowsSdkRoot).Path
$reader = (Resolve-Path -LiteralPath $LlvmReadObj).Path
$kernel32 = (Resolve-Path -LiteralPath $XpKernel32).Path
$output = [IO.Path]::GetFullPath($OutputDirectory)
[IO.Directory]::CreateDirectory($output) | Out-Null
$targetRoots = @($image)
foreach ($root in $AdditionalTargetRoot) {
    $targetRoots += (Resolve-Path -LiteralPath $root).Path
}

$cl = Join-Path $msvc 'bin\Hostx64\x64\cl.exe'
$link = Join-Path $msvc 'bin\Hostx64\x64\link.exe'
$dumpbin = Join-Path $msvc 'bin\Hostx64\x64\dumpbin.exe'
$kernelImport = Join-Path $sdk "Lib\$WindowsSdkVersion\um\x64\kernel32.lib"
foreach ($required in @($cl, $link, $dumpbin, $kernelImport)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required compiler input does not exist: $required"
    }
}

$definition = Join-Path $output 'jdkxp.def'
& (Join-Path $PSScriptRoot 'generate-def.ps1') `
    -LlvmReadObj $reader -XpKernel32 $kernel32 `
    -Source (Join-Path $PSScriptRoot 'jdkxp.cpp') -Output $definition `
    -Dumpbin $dumpbin -Kernel32ImportLib $kernelImport -TargetRoot $targetRoots
if ($LASTEXITCODE -ne 0) { throw 'Generating the JDKXP export definition failed.' }

$includeArguments = @(
    (Join-Path $msvc 'include'),
    (Join-Path $sdk "Include\$WindowsSdkVersion\ucrt"),
    (Join-Path $sdk "Include\$WindowsSdkVersion\shared"),
    (Join-Path $sdk "Include\$WindowsSdkVersion\um")
) | ForEach-Object { "/I$_" }
$libraryArguments = @(
    "/LIBPATH:$msvc\lib\x64",
    "/LIBPATH:$msvc\lib\onecore\x64",
    "/LIBPATH:$sdk\Lib\$WindowsSdkVersion\ucrt\x64",
    "/LIBPATH:$sdk\Lib\$WindowsSdkVersion\um\x64"
)

$proxyObject = Join-Path $output 'jdkxp.obj'
$proxyDll = Join-Path $output 'JDKXP.dll'
& $cl /nologo /c /O2 /MT /W4 /EHsc /GS- @includeArguments `
    "/Fo$proxyObject" (Join-Path $PSScriptRoot 'jdkxp.cpp')
if ($LASTEXITCODE -ne 0) { throw 'Compiling JDKXP failed.' }
& $link /DLL /NOLOGO /MACHINE:X64 /SUBSYSTEM:WINDOWS,5.02 /OSVERSION:5.02 `
    "/OUT:$proxyDll" "/DEF:$definition" $proxyObject @libraryArguments `
    kernel32.lib psapi.lib /OPT:REF /OPT:ICF
if ($LASTEXITCODE -ne 0) { throw 'Linking JDKXP failed.' }

$apiDll = Join-Path $output 'api-ms-win-core-synch-l1-1-0.dll'
& $link /DLL /NOENTRY /NOLOGO /MACHINE:X64 /SUBSYSTEM:WINDOWS,5.02 /OSVERSION:5.02 `
    "/OUT:$apiDll" "/DEF:$(Join-Path $PSScriptRoot 'api-ms-win-core-synch-l1-1-0-vista.def')" `
    /NODEFAULTLIB
if ($LASTEXITCODE -ne 0) { throw 'Linking the synchronization API-set shim failed.' }

$smokeObject = Join-Path $output 'compat-smoke.obj'
$smokeExe = Join-Path $output 'compat-smoke.exe'
& $cl /nologo /c /O2 /MT /W4 /EHsc /GS- @includeArguments `
    "/Fo$smokeObject" (Join-Path $PSScriptRoot 'compat-smoke.cpp')
if ($LASTEXITCODE -ne 0) { throw 'Compiling the compatibility smoke test failed.' }
& $link /NOLOGO /MACHINE:X64 /SUBSYSTEM:CONSOLE,5.02 /OSVERSION:5.02 `
    "/OUT:$smokeExe" $smokeObject "/LIBPATH:$output" @libraryArguments `
    JDKXP.lib kernel32.lib /OPT:REF /OPT:ICF
if ($LASTEXITCODE -ne 0) { throw 'Linking the compatibility smoke test failed.' }

Get-FileHash -Algorithm SHA256 -LiteralPath $proxyDll, $apiDll, $smokeExe |
    ForEach-Object { '{0}  {1}' -f $_.Hash, (Split-Path -Leaf $_.Path) } |
    Set-Content -LiteralPath (Join-Path $output 'SHA256SUMS.txt') -Encoding ascii
Write-Output "JDKXP_BUILD=$output"
