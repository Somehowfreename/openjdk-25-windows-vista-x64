[CmdletBinding()]
param(
    [ValidatePattern('^r[0-9]+$')]
    [string] $OutputRevision = 'r1',

    [string] $CertifiedSdlRoot
)

$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..\..\..')).Path
$reader = Join-Path $workspace 'work\toolchains\llvm-mingw-20260616-msvcrt-x86_64\bin\llvm-readobj.exe'
$patcher = Join-Path $workspace 'work\compat\jdkxp\patch-image.ps1'
if (-not $CertifiedSdlRoot) {
    $CertifiedSdlRoot = Join-Path $workspace `
        'work\artifacts\openjdk-25.0.4-xp-x64-certified-final\minecraft-sdl342'
}

$sourceSdl = Join-Path $CertifiedSdlRoot 'SDL3.dll'
$sourceShell = Join-Path $CertifiedSdlRoot 'JDKS.dll'
$sourceUser = Join-Path $CertifiedSdlRoot 'JDKU.dll'
$outputRoot = Join-Path $workspace "work\release-builds\sdl3-isolated-compat-$OutputRevision"
$payload = Join-Path $outputRoot 'payload'
$targetSdl = Join-Path $payload 'SDL3.dll'
$targetShell = Join-Path $payload 'SDLS.dll'
$targetUser = Join-Path $payload 'SDLU.dll'

foreach ($required in @($reader, $patcher, $sourceSdl, $sourceShell, $sourceUser)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required isolated SDL compatibility input is missing: $required"
    }
}
if (Test-Path -LiteralPath $outputRoot) {
    throw "Refusing to replace preserved isolated SDL compatibility build: $outputRoot"
}
[IO.Directory]::CreateDirectory($payload) | Out-Null

# SDL's shell and window-system forwarders have a broader export set than the
# JDK runtime's modules. Give them private names so loading SDL can never
# replace or collide with the JDK's own JDKS.dll and JDKU.dll modules.
Copy-Item -LiteralPath $sourceSdl -Destination $targetSdl
Copy-Item -LiteralPath $sourceShell -Destination $targetShell
Copy-Item -LiteralPath $sourceUser -Destination $targetUser
& $patcher -ImageRoot $payload -LlvmReadObj $reader `
    -TargetWindowsMajor 5 -TargetWindowsMinor 2 `
    -ImportMappings @{ 'JDKS.dll' = 'SDLS.dll'; 'JDKU.dll' = 'SDLU.dll' }

$sdlImports = & $reader --coff-imports $targetSdl
if ($LASTEXITCODE -ne 0) { throw 'Reading isolated SDL imports failed.' }
foreach ($requiredModule in @('SDLS.dll', 'SDLU.dll', 'JDKXP.dll')) {
    if (-not ($sdlImports | Select-String -SimpleMatch "Name: $requiredModule")) {
        throw "Isolated SDL does not import required module $requiredModule."
    }
}
foreach ($forbiddenModule in @('JDKS.dll', 'JDKU.dll', 'KERNEL32.dll', 'SHELL32.dll', 'USER32.dll')) {
    if ($sdlImports | Select-String -SimpleMatch "Name: $forbiddenModule") {
        throw "Isolated SDL still imports non-isolated module $forbiddenModule."
    }
}

$manifest = Join-Path $outputRoot 'SHA256SUMS.txt'
Get-FileHash -Algorithm SHA256 $targetSdl, $targetShell, $targetUser |
    ForEach-Object { '{0}  {1}' -f $_.Hash, (Split-Path -Leaf $_.Path) } |
    Set-Content -LiteralPath $manifest -Encoding ascii

Write-Output "SDL3_ISOLATED_COMPAT_PASS=$outputRoot"
Write-Output "PAYLOAD=$payload"
Write-Output "MANIFEST=$manifest"
