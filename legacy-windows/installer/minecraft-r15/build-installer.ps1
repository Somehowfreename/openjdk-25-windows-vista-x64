[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $RuntimeDirectory,

    [Parameter(Mandatory)]
    [string] $Makensis,

    [string] $OutputDirectory = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
$runtime = (Resolve-Path -LiteralPath $RuntimeDirectory).Path
$sharedBuilder = Join-Path $PSScriptRoot '..\minecraft-r14\build-installer.ps1'

foreach ($requiredRelative in @(
    'bin\minecraft-javaw-multimc.exe',
    'bin\minecraft-javaw-olauncher.exe',
    'bin\minecraft-javaw-software-olauncher.exe'
)) {
    $required = Join-Path $runtime $requiredRelative
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required multi-launcher input is missing: $required"
    }
}

$legacy = Get-FileHash -LiteralPath (Join-Path $runtime 'bin\minecraft-javaw.exe') -Algorithm SHA256
$named = Get-FileHash -LiteralPath (Join-Path $runtime 'bin\minecraft-javaw-multimc.exe') -Algorithm SHA256
if ($legacy.Hash -ne $named.Hash) {
    throw 'The legacy and named MultiMC entry points must be byte-identical.'
}

& $sharedBuilder -RuntimeDirectory $runtime -Makensis $Makensis `
    -OutputDirectory $OutputDirectory -Revision r15 `
    -FileVersion '25.0.4.16' `
    -PayloadDescription 'OpenJDK source backport with automatic Minecraft 1.21/26 profiles and MultiMC and OLauncher adapters'
if ($LASTEXITCODE -ne 0) { throw 'Minecraft r15 installer build failed.' }
