[CmdletBinding()]
param(
    [string] $OutputDirectory = (Join-Path $PSScriptRoot 'upgrade-audit-build'),
    [string] $WorkspaceRoot
)

$ErrorActionPreference = 'Stop'
$workspace = if ($WorkspaceRoot) { (Resolve-Path -LiteralPath $WorkspaceRoot).Path } else { Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$msvc = Join-Path $workspace 'work\toolchains\msvc-14.29-portable\Contents\VC\Tools\MSVC\14.29.30133'
$sdk = Join-Path $workspace 'work\toolchains\winsdk-10.0.19041-portable\Windows Kits\10'
$compiler = Join-Path $msvc 'bin\Hostx64\x64\cl.exe'
$linker = Join-Path $msvc 'bin\Hostx64\x64\link.exe'
$source = Join-Path $PSScriptRoot 'upgrade-audit.c'
$object = Join-Path $OutputDirectory 'upgrade-audit.obj'
$output = Join-Path $OutputDirectory 'legacy-openjdk-upgrade-audit.exe'

[IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null

$includes = @(
    "/I$(Join-Path $msvc 'include')",
    "/I$(Join-Path $sdk 'Include\10.0.19041.0\ucrt')",
    "/I$(Join-Path $sdk 'Include\10.0.19041.0\shared')",
    "/I$(Join-Path $sdk 'Include\10.0.19041.0\um')"
)
& $compiler /nologo /c /TC /O2 /MT /W3 /GS- @includes "/Fo$object" $source
if ($LASTEXITCODE -ne 0) { throw 'Compiling the upgrade auditor failed.' }

$libraries = @(
    "/LIBPATH:$(Join-Path $msvc 'lib\x64')",
    "/LIBPATH:$(Join-Path $msvc 'lib\onecore\x64')",
    "/LIBPATH:$(Join-Path $sdk 'Lib\10.0.19041.0\ucrt\x64')",
    "/LIBPATH:$(Join-Path $sdk 'Lib\10.0.19041.0\um\x64')"
)
& $linker /nologo /subsystem:console,5.02 /osversion:5.02 /entry:wmainCRTStartup `
    "/out:$output" $object @libraries kernel32.lib /OPT:REF /OPT:ICF /Brepro
if ($LASTEXITCODE -ne 0) { throw 'Linking the upgrade auditor failed.' }

Write-Output "UPGRADE_AUDITOR=$output"
Write-Output "SHA256=$((Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash)"
