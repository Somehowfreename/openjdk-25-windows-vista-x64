[CmdletBinding()]
param(
    [string[]] $Only = @(),

    [ValidatePattern('^r[0-9]+$')]
    [string] $MinecraftRevision = 'r9',

    [switch] $IncludeWindows7
)

$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$makensis = Join-Path $workspace 'work\toolchains\nsis-3.12\makensis.exe'
$script = Join-Path $PSScriptRoot 'legacy-openjdk.nsi'
$outputRoot = Join-Path $workspace "work\private-release-staging\installers-minecraft-$MinecraftRevision"
$metadataRoot = Join-Path $workspace "work\private-release-staging\payload-manifests-minecraft-$MinecraftRevision"

foreach ($required in @($makensis, $script)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required installer input is missing: $required"
    }
}
[IO.Directory]::CreateDirectory($outputRoot) | Out-Null
[IO.Directory]::CreateDirectory($metadataRoot) | Out-Null

$packages = @(
    [pscustomobject]@{ Id='jdk17-xp-x64'; Name='OpenJDK 17.0.20 for Windows XP x64'; Display='17.0.20+1-legacy-windows-x64-minecraft-r5'; FileVersion='17.0.20.7'; Target='xp'; Os='Windows XP Professional x64 Edition SP2'; Folder='jdk-17.0.20-xp-x64'; Runtime='work\artifacts\openjdk-17.0.20-xp-x64-minecraft-wrapper-r5'; Repo='work\sources\openjdk17u-xp'; Payload='OpenJDK source backport with relocatable Minecraft 1.20.1 wrapper'; Output='OpenJDK17U-jdk_x64_windows-xp_17.0.20_minecraft-r5.exe' },
    [pscustomobject]@{ Id='jdk17-vista-x64'; Name='OpenJDK 17.0.20 for Windows Vista x64'; Display='17.0.20-legacy-windows-vista-x64-minecraft-r5'; FileVersion='17.0.20.8'; Target='vista'; Os='Windows Vista SP2 x64'; Folder='jdk-17.0.20-vista-x64'; Runtime='work\artifacts\openjdk-17.0.20-vista-x64-minecraft-wrapper-r5'; Repo='work\sources\openjdk17u-xp'; Payload='OpenJDK source backport with relocatable Minecraft 1.20.1 wrapper'; Output='OpenJDK17U-jdk_x64_windows-vista_17.0.20_minecraft-r5.exe' },
    [pscustomobject]@{ Id='jdk17-win7-x64'; Name='Eclipse Temurin OpenJDK 17.0.20 for Windows 7 x64'; Display='17.0.20+8'; FileVersion='17.0.20.8'; Target='win7'; Os='Windows 7 SP1 x64'; Folder='jdk-17.0.20-win7-x64'; Runtime='work\toolchains\temurin-17\jdk-17.0.20+8'; Repo='work\sources\openjdk17u-xp'; Payload='Unmodified Eclipse Temurin 17.0.20+8'; Output='OpenJDK17U-jdk_x64_windows-7_17.0.20_8-temurin.exe' },
    [pscustomobject]@{ Id='jdk21-xp-x64'; Name='OpenJDK 21.0.12 for Windows XP x64'; Display='21.0.12+1-legacy-windows-x64-minecraft-r5'; FileVersion='21.0.12.7'; Target='xp'; Os='Windows XP Professional x64 Edition SP2'; Folder='jdk-21.0.12-xp-x64'; Runtime='work\artifacts\openjdk-21.0.12-xp-x64-minecraft-wrapper-r5'; Repo='work\sources\openjdk21u-xp'; Payload='OpenJDK source backport with relocatable Minecraft 1.21.1 wrapper'; Output='OpenJDK21U-jdk_x64_windows-xp_21.0.12_minecraft-r5.exe' },
    [pscustomobject]@{ Id='jdk21-vista-x64'; Name='OpenJDK 21.0.12 for Windows Vista x64'; Display='21.0.12-legacy-windows-vista-x64-minecraft-r5'; FileVersion='21.0.12.8'; Target='vista'; Os='Windows Vista SP2 x64'; Folder='jdk-21.0.12-vista-x64'; Runtime='work\artifacts\openjdk-21.0.12-vista-x64-minecraft-wrapper-r5'; Repo='work\sources\openjdk21u-xp'; Payload='OpenJDK source backport with relocatable Minecraft 1.21.1 wrapper'; Output='OpenJDK21U-jdk_x64_windows-vista_21.0.12_minecraft-r5.exe' },
    [pscustomobject]@{ Id='jdk21-win7-x64'; Name='Eclipse Temurin OpenJDK 21.0.12 for Windows 7 x64'; Display='21.0.12+8-LTS'; FileVersion='21.0.12.8'; Target='win7'; Os='Windows 7 SP1 x64'; Folder='jdk-21.0.12-win7-x64'; Runtime='work\toolchains\temurin-21\jdk-21.0.12+8'; Repo='work\sources\openjdk21u-xp'; Payload='Unmodified Eclipse Temurin 21.0.12+8'; Output='OpenJDK21U-jdk_x64_windows-7_21.0.12_8-temurin.exe' },
    [pscustomobject]@{ Id='jdk25-xp-x64'; Name='OpenJDK 25.0.4 for Windows XP x64'; Display='25.0.4-legacy-windows-xp-x64-minecraft-r5'; FileVersion='25.0.4.7'; Target='xp'; Os='Windows XP Professional x64 Edition SP2'; Folder='jdk-25.0.4-xp-x64'; Runtime='work\artifacts\openjdk-25.0.4-xp-x64-minecraft-wrapper-r5'; Repo='work\sources\openjdk25u-xp'; Payload='OpenJDK source backport with relocatable Minecraft 26.2 wrapper'; Output='OpenJDK25U-jdk_x64_windows-xp_25.0.4_minecraft-r5.exe' },
    [pscustomobject]@{ Id='jdk25-vista-x64'; Name='OpenJDK 25.0.4 for Windows Vista x64'; Display='25.0.4-legacy-windows-vista-x64-minecraft-r5'; FileVersion='25.0.4.8'; Target='vista'; Os='Windows Vista SP2 x64'; Folder='jdk-25.0.4-vista-x64'; Runtime='work\artifacts\openjdk-25.0.4-vista-x64-minecraft-wrapper-r5'; Repo='work\sources\openjdk25u-xp'; Payload='OpenJDK source backport with relocatable Minecraft 26.2 wrapper'; Output='OpenJDK25U-jdk_x64_windows-vista_25.0.4_minecraft-r5.exe' },
    [pscustomobject]@{ Id='jdk25-win7-x64'; Name='Eclipse Temurin OpenJDK 25.0.4 for Windows 7 x64'; Display='25.0.4+7-LTS'; FileVersion='25.0.4.7'; Target='win7'; Os='Windows 7 SP1 x64'; Folder='jdk-25.0.4-win7-x64'; Runtime='work\toolchains\temurin-25-stock\jdk-25.0.4+7'; Repo='work\sources\openjdk25u-xp'; Payload='Unmodified Eclipse Temurin 25.0.4+7'; Output='OpenJDK25U-jdk_x64_windows-7_25.0.4_7-temurin.exe' }
)

# Keep older preserved revisions immutable while allowing one reproducible
# build script to package the current Minecraft integration revision. Windows
# 7 uses stock Temurin and is deliberately excluded unless explicitly asked
# for; this project's deliverables are XP x64 and Vista x64 only.
$fileVersions = @{
    'jdk17-xp-x64'='17.0.20.9'; 'jdk17-vista-x64'='17.0.20.10'
    'jdk21-xp-x64'='21.0.12.9'; 'jdk21-vista-x64'='21.0.12.10'
    'jdk25-xp-x64'='25.0.4.9'; 'jdk25-vista-x64'='25.0.4.10'
}
if ($MinecraftRevision -eq 'r10') {
    # r10 is the Vista-native DWMAPI packaging correction.  Keep the fully
    # certified XP r9 packages immutable while advancing only Vista package
    # file versions for clean installer upgrade semantics.
    $fileVersions['jdk17-vista-x64'] = '17.0.20.11'
    $fileVersions['jdk21-vista-x64'] = '21.0.12.11'
    $fileVersions['jdk25-vista-x64'] = '25.0.4.11'
}
foreach ($package in @($packages | Where-Object Target -ne 'win7')) {
    $package.Display = $package.Display.Replace('minecraft-r5', "minecraft-$MinecraftRevision")
    $package.Runtime = $package.Runtime.Replace('minecraft-wrapper-r5', "minecraft-wrapper-$MinecraftRevision")
    $package.Output = $package.Output.Replace('minecraft-r5', "minecraft-$MinecraftRevision")
    $package.FileVersion = $fileVersions[$package.Id]
}
if (-not $IncludeWindows7) {
    $packages = @($packages | Where-Object Target -ne 'win7')
}

if ($Only.Count) {
    $unknown = @($Only | Where-Object { $_ -notin $packages.Id })
    if ($unknown.Count) { throw "Unknown package id(s): $($unknown -join ', ')" }
    $packages = @($packages | Where-Object Id -in $Only)
}

foreach ($package in $packages) {
    $runtime = Join-Path $workspace $package.Runtime
    $repo = Join-Path $workspace $package.Repo
    foreach ($required in @(
        (Join-Path $runtime 'bin\java.exe'),
        (Join-Path $runtime 'bin\javac.exe'),
        (Join-Path $repo 'LICENSE'),
        (Join-Path $repo 'ADDITIONAL_LICENSE_INFO'),
        (Join-Path $repo 'ASSEMBLY_EXCEPTION')
    )) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Package $($package.Id) is missing required input: $required"
        }
    }

    $repoSafe = $repo.Replace('\', '/')
    $sourceCommit = (& git -c "safe.directory=$repoSafe" -C $repo rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $sourceCommit -notmatch '^[0-9a-f]{40}$') {
        throw "Could not determine source commit for $($package.Id)"
    }
    if (& git -c "safe.directory=$repoSafe" -C $repo status --porcelain) {
        throw "Source repository is dirty: $repo"
    }

    $manifest = Join-Path $metadataRoot "$($package.Id)-PAYLOAD-SHA256SUMS.txt"
    $runtimeFiles = @(Get-ChildItem -LiteralPath $runtime -Recurse -File | Sort-Object FullName)
    $runtimeFiles | Get-FileHash -Algorithm SHA256 | ForEach-Object {
        '{0}  {1}' -f $_.Hash, $_.Path.Substring($runtime.Length + 1).Replace('\', '/')
    } | Set-Content -LiteralPath $manifest -Encoding ascii
    $estimatedKb = [int][Math]::Ceiling(($runtimeFiles | Measure-Object Length -Sum).Sum / 1KB)
    $output = Join-Path $outputRoot $package.Output

    Write-Output "BUILD_BEGIN=$($package.Id)"
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
        "/DLICENSE_FILE=$(Join-Path $repo 'LICENSE')",
        "/DADDITIONAL_LICENSE_FILE=$(Join-Path $repo 'ADDITIONAL_LICENSE_INFO')",
        "/DASSEMBLY_EXCEPTION_FILE=$(Join-Path $repo 'ASSEMBLY_EXCEPTION')",
        "/DPAYLOAD_MANIFEST=$manifest",
        "/DSOURCE_COMMIT=$sourceCommit",
        "/DPAYLOAD_KIND=$($package.Payload)",
        "/DESTIMATED_SIZE_KB=$estimatedKb",
        $script
    )
    & $makensis @arguments
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $output -PathType Leaf)) {
        throw "NSIS build failed for $($package.Id)"
    }
    $hash = Get-FileHash -LiteralPath $output -Algorithm SHA256
    Write-Output "BUILD_PASS=$($package.Id) SIZE=$((Get-Item -LiteralPath $output).Length) SHA256=$($hash.Hash)"
}

$installerManifest = Join-Path $outputRoot 'SHA256SUMS.txt'
Get-ChildItem -LiteralPath $outputRoot -File -Filter '*.exe' | Sort-Object Name |
    Get-FileHash -Algorithm SHA256 | ForEach-Object {
        '{0}  {1}' -f $_.Hash, (Split-Path -Leaf $_.Path)
    } | Set-Content -LiteralPath $installerManifest -Encoding ascii
Write-Output "INSTALLER_MANIFEST=$installerManifest"
