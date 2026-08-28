[CmdletBinding()]
param(
    [ValidatePattern('^r[0-9]+$')]
    [string] $XpRevision = 'r26',
    [ValidatePattern('^r[0-9]+$')]
    [string] $VistaRevision = 'r28',
    [string] $OutputDirectory = $PSScriptRoot,
    [ValidateSet('xp','vista')]
    [string[]] $TargetOs = @('xp','vista'),
    [string] $XpRuntimeDirectory
)

$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$makensis = Join-Path $workspace 'work\toolchains\nsis-3.12\makensis.exe'
$nsi = Join-Path $workspace 'work\installers\legacy-openjdk.nsi'
$licenseRoot = Join-Path $workspace 'work\release-repositories\openjdk-25-windows-xp-x64'
$outputRoot = Join-Path $OutputDirectory 'installers'
$manifestRoot = Join-Path $OutputDirectory 'payload-manifests'
$auditorBuildScript = Join-Path $workspace 'work\installers\build-upgrade-audit.ps1'
$auditorBuild = Join-Path $OutputDirectory 'upgrade-audit-build'
$auditor = Join-Path $auditorBuild 'legacy-openjdk-upgrade-audit.exe'

[IO.Directory]::CreateDirectory($outputRoot) | Out-Null
[IO.Directory]::CreateDirectory($manifestRoot) | Out-Null

$packages = @(
    [pscustomobject]@{
        Id = 'jdk25-xp-x64'
        Name = 'OpenJDK 25.0.4 for Windows XP x64'
        Display = '25.0.4-legacy-windows-xp-x64-version2-r26'
        FileVersion = '25.0.4.26'
        Target = 'xp'
        Os = 'Windows XP Professional x64 Edition SP2'
        Folder = 'jdk-25.0.4-xp-x64'
        Runtime = 'work\artifacts\openjdk-25.0.4-xp-x64-minecraft-wrapper-r26'
        Source = 'local-candidate-xp-r26'
        Payload = 'Local Version 2 test candidate with Minecraft 1.21.x and 26.x MultiMC and OLauncher wrappers'
        Output = 'OpenJDK25U-jdk_x64_windows-xp_25.0.4_version2-r26.exe'
    },
    [pscustomobject]@{
        Id = 'jdk25-vista-x64'
        Name = 'OpenJDK 25.0.4 for Windows Vista x64'
        Display = '25.0.4-legacy-windows-vista-x64-version2-r28'
        FileVersion = '25.0.4.28'
        Target = 'vista'
        Os = 'Windows Vista SP2 x64'
        Folder = 'jdk-25.0.4-vista-x64'
        Runtime = 'work\artifacts\openjdk-25.0.4-vista-x64-minecraft-wrapper-r28'
        Source = 'local-candidate-vista-r28'
        Payload = 'Local Version 2 test candidate with Minecraft 1.21.x and 26.x MultiMC and OLauncher wrappers'
        Output = 'OpenJDK25U-jdk_x64_windows-vista_25.0.4_version2-r28.exe'
    }
)

foreach ($package in $packages) {
    $revision = if ($package.Target -eq 'xp') { $XpRevision } else { $VistaRevision }
    foreach ($field in 'Display', 'Runtime', 'Source', 'Output') {
        $package.$field = $package.$field -replace 'r\d+$|r\d+(?=\.exe$)', $revision
    }
    $package.FileVersion = '25.0.4.' + $revision.Substring(1)
    $package.Payload = 'Local test candidate: Minecraft 1.20.x, 1.21.x and 26.x with MultiMC and OLauncher wrappers'
}
$packages=@($packages | Where-Object Target -in $TargetOs)

foreach ($required in @(
    $makensis,
    $nsi,
    (Join-Path $licenseRoot 'LICENSE'),
    (Join-Path $licenseRoot 'ADDITIONAL_LICENSE_INFO'),
    (Join-Path $licenseRoot 'ASSEMBLY_EXCEPTION')
)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required packaging input is missing: $required"
    }
}

& $auditorBuildScript -OutputDirectory $auditorBuild
if (-not (Test-Path -LiteralPath $auditor -PathType Leaf)) {
    throw "Upgrade auditor build did not produce: $auditor"
}

foreach ($package in $packages) {
    $runtime = if($package.Target -eq 'xp' -and $XpRuntimeDirectory) {
        (Resolve-Path -LiteralPath $XpRuntimeDirectory).Path
    } else { Join-Path $workspace $package.Runtime }
    foreach ($required in @(
        (Join-Path $runtime 'bin\minecraft-java.exe'),
        (Join-Path $runtime 'bin\minecraft-javaw-multimc.exe'),
        (Join-Path $runtime 'bin\minecraft-javaw-olauncher.exe'),
        (Join-Path $runtime 'lib\legacy-windows\internal\launcher\executables\java.exe'),
        (Join-Path $runtime 'lib\legacy-windows\internal\launcher\executables\javac.exe')
    )) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Package $($package.Id) is missing required input: $required"
        }
    }

    $manifest = Join-Path $manifestRoot "$($package.Id)-PAYLOAD-SHA256SUMS.txt"
    $runtimeFiles = @(Get-ChildItem -LiteralPath $runtime -Recurse -File | Sort-Object FullName)
    $runtimeFiles | Get-FileHash -Algorithm SHA256 | ForEach-Object {
        '{0}  {1}' -f $_.Hash, $_.Path.Substring($runtime.Length + 1).Replace('\', '/')
    } | Set-Content -LiteralPath $manifest -Encoding ascii

    $estimatedKb = [int][Math]::Ceiling(($runtimeFiles | Measure-Object Length -Sum).Sum / 1KB)
    $output = Join-Path $outputRoot $package.Output
    $arguments = @(
        '/V3',
        '/WX',
        "/DPRODUCT_ID=$($package.Id)",
        "/DPRODUCT_NAME=$($package.Name)",
        "/DDISPLAY_VERSION=$($package.Display)",
        "/DFILE_VERSION=$($package.FileVersion)",
        "/DTARGET_OS=$($package.Target)",
        "/DOS_LABEL=$($package.Os)",
        "/DINSTALL_FOLDER=$($package.Folder)",
        "/DRUNTIME_DIR=$runtime",
        "/DOUTPUT_FILE=$output",
        "/DLICENSE_FILE=$(Join-Path $licenseRoot 'LICENSE')",
        "/DADDITIONAL_LICENSE_FILE=$(Join-Path $licenseRoot 'ADDITIONAL_LICENSE_INFO')",
        "/DASSEMBLY_EXCEPTION_FILE=$(Join-Path $licenseRoot 'ASSEMBLY_EXCEPTION')",
        "/DPAYLOAD_MANIFEST=$manifest",
        "/DSOURCE_COMMIT=$($package.Source)",
        "/DPAYLOAD_KIND=$($package.Payload)",
        "/DUPGRADE_AUDITOR=$auditor",
        "/DESTIMATED_SIZE_KB=$estimatedKb",
        $nsi
    )

    Write-Output "BUILD_BEGIN=$($package.Id)"
    & $makensis @arguments
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $output -PathType Leaf)) {
        throw "NSIS build failed for $($package.Id)"
    }
    $hash = Get-FileHash -LiteralPath $output -Algorithm SHA256
    Write-Output "BUILD_PASS=$($package.Id) SIZE=$((Get-Item -LiteralPath $output).Length) SHA256=$($hash.Hash)"
}

Get-ChildItem -LiteralPath $outputRoot -File -Filter '*.exe' | Sort-Object Name |
    Get-FileHash -Algorithm SHA256 | ForEach-Object {
        '{0}  {1}' -f $_.Hash, (Split-Path -Leaf $_.Path)
    } | Set-Content -LiteralPath (Join-Path $outputRoot 'SHA256SUMS.txt') -Encoding ascii
