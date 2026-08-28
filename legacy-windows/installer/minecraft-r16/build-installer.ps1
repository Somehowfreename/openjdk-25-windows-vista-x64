[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $RuntimeDirectory,

    [Parameter(Mandatory)]
    [string] $Makensis,

    [string] $OutputDirectory = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
$repository = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
$nsisScript = Join-Path $PSScriptRoot '..\minecraft-beta-r9\legacy-openjdk.nsi'
$runtime = (Resolve-Path -LiteralPath $RuntimeDirectory).Path
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
$manifest = Join-Path $outputRoot 'jdk25-xp-x64-PAYLOAD-SHA256SUMS.txt'
$output = Join-Path $outputRoot `
    'OpenJDK25U-jdk_x64_windows-xp_25.0.4_minecraft-r16.exe'

$privateRoot = 'lib\legacy-windows\internal\launcher\executables'
$requiredRelative = @(
    'bin\minecraft-java.exe',
    'bin\minecraft-javaw.exe',
    'bin\minecraft-javaw-multimc.exe',
    'bin\minecraft-javaw-olauncher.exe',
    'bin\vmtests\minecraft-java-software-rendering-multimc.exe',
    'bin\vmtests\minecraft-javaw-software-rendering-multimc.exe',
    'bin\vmtests\minecraft-javaw-software-rendering-olauncher.exe',
    "$privateRoot\java.exe",
    "$privateRoot\javaw.exe",
    "$privateRoot\minecraft-java-runtime.exe",
    "$privateRoot\minecraft-javaw-runtime.exe",
    "$privateRoot\software\minecraft-java-software.exe",
    "$privateRoot\software\minecraft-javaw-software.exe",
    "$privateRoot\1.21\minecraft-java-runtime.exe",
    "$privateRoot\1.21\minecraft-javaw-runtime.exe",
    "$privateRoot\1.21\software\minecraft-java-software.exe",
    "$privateRoot\1.21\software\minecraft-javaw-software.exe",
    'minecraft\1.21\natives-xp-x64\freetype.dll',
    'minecraft\26.2\natives-xp-x64\freetype.dll',
    'minecraft\26.2\compat\alsoft-xp.ini',
    'minecraft\26.2\compat\jtracy-1.0.37-natives-windows-xp.jar'
)

foreach ($required in @(
    $Makensis,
    $nsisScript,
    (Join-Path $repository 'LICENSE'),
    (Join-Path $repository 'ADDITIONAL_LICENSE_INFO'),
    (Join-Path $repository 'ASSEMBLY_EXCEPTION')
) + ($requiredRelative | ForEach-Object { Join-Path $runtime $_ })) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required installer input is missing: $required"
    }
}

$legacyHash = (Get-FileHash -LiteralPath `
    (Join-Path $runtime 'bin\minecraft-javaw.exe') -Algorithm SHA256).Hash
$multiMcHash = (Get-FileHash -LiteralPath `
    (Join-Path $runtime 'bin\minecraft-javaw-multimc.exe') -Algorithm SHA256).Hash
if ($legacyHash -ne $multiMcHash) {
    throw 'The legacy and named MultiMC entry points must be byte-identical.'
}

$forbidden = @(
    'bin\minecraft-javaw-software.exe',
    'bin\minecraft-javaw-software-olauncher.exe'
)
foreach ($relative in $forbidden) {
    if (Test-Path -LiteralPath (Join-Path $runtime $relative)) {
        throw "Unsupported or obsolete public entry point is present: $relative"
    }
}

$repositorySafe = $repository.Replace('\', '/')
$sourceCommit = (& git -c "safe.directory=$repositorySafe" -C $repository `
    rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $sourceCommit -notmatch '^[0-9a-f]{40}$') {
    throw 'Could not determine the source commit.'
}
if (& git -c "safe.directory=$repositorySafe" -C $repository status --porcelain) {
    throw "Source repository is dirty: $repository"
}

[IO.Directory]::CreateDirectory($outputRoot) | Out-Null
$runtimeFiles = @(Get-ChildItem -LiteralPath $runtime -Recurse -File |
    Sort-Object FullName)
$runtimeFiles | Get-FileHash -Algorithm SHA256 | ForEach-Object {
    '{0}  {1}' -f $_.Hash,
        $_.Path.Substring($runtime.Length + 1).Replace('\', '/')
} | Set-Content -LiteralPath $manifest -Encoding ascii

$estimatedKb = [int][Math]::Ceiling(
    ($runtimeFiles | Measure-Object Length -Sum).Sum / 1KB)
$arguments = @(
    '/V3',
    '/WX',
    '/DPRODUCT_ID=jdk25-xp-x64',
    '/DMODERN_MINECRAFT_LAYOUT',
    '/DPRODUCT_NAME=OpenJDK 25.0.4 for Windows XP x64',
    '/DDISPLAY_VERSION=25.0.4-legacy-windows-xp-x64-minecraft-r16',
    '/DFILE_VERSION=25.0.4.17',
    '/DTARGET_OS=xp',
    '/DOS_LABEL=Windows XP Professional x64 Edition SP2',
    '/DINSTALL_FOLDER=jdk-25.0.4-xp-x64',
    "/DRUNTIME_DIR=$runtime",
    "/DOUTPUT_FILE=$output",
    "/DLICENSE_FILE=$(Join-Path $repository 'LICENSE')",
    "/DADDITIONAL_LICENSE_FILE=$(Join-Path $repository 'ADDITIONAL_LICENSE_INFO')",
    "/DASSEMBLY_EXCEPTION_FILE=$(Join-Path $repository 'ASSEMBLY_EXCEPTION')",
    "/DPAYLOAD_MANIFEST=$manifest",
    "/DSOURCE_COMMIT=$sourceCommit",
    '/DPAYLOAD_KIND=OpenJDK source backport with automatic Minecraft 1.21/26 profiles and MultiMC and OLauncher adapters',
    "/DESTIMATED_SIZE_KB=$estimatedKb",
    $nsisScript
)
& $Makensis @arguments
if ($LASTEXITCODE -ne 0 -or
    -not (Test-Path -LiteralPath $output -PathType Leaf)) {
    throw 'NSIS installer build failed.'
}

$installerHash = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
"$installerHash  $(Split-Path -Leaf $output)" |
    Set-Content -LiteralPath (Join-Path $outputRoot 'SHA256SUMS.txt') `
        -Encoding ascii
Write-Output "INSTALLER=$output"
Write-Output "SHA256=$installerHash"
Write-Output "SOURCE_COMMIT=$sourceCommit"
