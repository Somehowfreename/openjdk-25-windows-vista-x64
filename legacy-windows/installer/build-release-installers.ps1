[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $XpRuntime,
    [Parameter(Mandatory)] [string] $VistaRuntime,
    [Parameter(Mandatory)] [string] $Win7Runtime,
    [Parameter(Mandatory)] [string] $NsisRoot,
    [string] $OutputDirectory = (Join-Path $PSScriptRoot 'out')
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$config = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'release-config.psd1')
$makensis = Join-Path $NsisRoot 'makensis.exe'
$nsi = Join-Path $PSScriptRoot 'legacy-openjdk.nsi'
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$manifestRoot = Join-Path $OutputDirectory 'payload-manifests'

foreach ($required in @(
    $makensis,
    $nsi,
    (Join-Path $repo 'LICENSE'),
    (Join-Path $repo 'ADDITIONAL_LICENSE_INFO'),
    (Join-Path $repo 'ASSEMBLY_EXCEPTION')
)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required input is missing: $required"
    }
}

if (Test-Path -LiteralPath $OutputDirectory) {
    if (Get-ChildItem -LiteralPath $OutputDirectory -Force | Select-Object -First 1) {
        throw "Refusing to overwrite a non-empty output directory: $OutputDirectory"
    }
} else {
    [IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
}
[IO.Directory]::CreateDirectory($manifestRoot) | Out-Null

$repoSafe = $repo.Replace('\', '/')
$sourceCommit = [string] $config.SourceCommit
if ($sourceCommit -notmatch '^[0-9a-f]{40}$') { throw 'SourceCommit must be a full Git object ID' }
& git -c "safe.directory=$repoSafe" -C $repo cat-file -e "$sourceCommit^{commit}"
if ($LASTEXITCODE -ne 0) { throw "Configured source commit is not present: $sourceCommit" }
if (& git -c "safe.directory=$repoSafe" -C $repo status --porcelain) {
    throw 'Commit or stash source changes before producing a release package'
}

$runtimeByTarget = @{
    xp = (Resolve-Path -LiteralPath $XpRuntime).Path
    vista = (Resolve-Path -LiteralPath $VistaRuntime).Path
    win7 = (Resolve-Path -LiteralPath $Win7Runtime).Path
}

foreach ($package in $config.Packages) {
    $runtime = $runtimeByTarget[$package.Target]
    foreach ($required in @(
        (Join-Path $runtime 'bin\java.exe'),
        (Join-Path $runtime 'bin\javac.exe')
    )) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Package $($package.Id) is missing runtime input: $required"
        }
    }

    $manifest = Join-Path $manifestRoot "$($package.Id)-PAYLOAD-SHA256SUMS.txt"
    $runtimeFiles = @(Get-ChildItem -LiteralPath $runtime -Recurse -File | Sort-Object FullName)
    $runtimeFiles | Get-FileHash -Algorithm SHA256 | ForEach-Object {
        '{0}  {1}' -f $_.Hash, $_.Path.Substring($runtime.Length + 1).Replace('\', '/')
    } | Set-Content -LiteralPath $manifest -Encoding ascii
    $estimatedKb = [int][Math]::Ceiling(($runtimeFiles | Measure-Object Length -Sum).Sum / 1KB)
    $output = Join-Path $OutputDirectory $package.Output

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
        $nsi
    )
    & $makensis @arguments
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $output -PathType Leaf)) {
        throw "NSIS failed for $($package.Id)"
    }
}

Get-ChildItem -LiteralPath $OutputDirectory -File -Filter '*.exe' | Sort-Object Name |
    Get-FileHash -Algorithm SHA256 | ForEach-Object {
        '{0}  {1}' -f $_.Hash, (Split-Path -Leaf $_.Path)
    } | Set-Content -LiteralPath (Join-Path $OutputDirectory 'SHA256SUMS.txt') -Encoding ascii

Write-Output "RELEASE_INSTALLERS=$OutputDirectory"
