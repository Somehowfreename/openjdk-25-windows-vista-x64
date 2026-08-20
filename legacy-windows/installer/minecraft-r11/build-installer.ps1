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
    'OpenJDK25U-jdk_x64_windows-xp_25.0.4_minecraft-r11.exe'

foreach ($required in @(
    $Makensis,
    $nsisScript,
    (Join-Path $runtime 'bin\java.exe'),
    (Join-Path $runtime 'bin\javac.exe'),
    (Join-Path $runtime 'bin\minecraft-javaw.exe'),
    (Join-Path $runtime 'bin\minecraft-javaw-software.exe'),
    (Join-Path $repository 'LICENSE'),
    (Join-Path $repository 'ADDITIONAL_LICENSE_INFO'),
    (Join-Path $repository 'ASSEMBLY_EXCEPTION')
)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required installer input is missing: $required"
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
    '/DPRODUCT_NAME=OpenJDK 25.0.4 for Windows XP x64',
    '/DDISPLAY_VERSION=25.0.4-legacy-windows-xp-x64-minecraft-r11',
    '/DFILE_VERSION=25.0.4.12',
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
    '/DPAYLOAD_KIND=OpenJDK source backport with relocatable Minecraft 26 wrapper',
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
