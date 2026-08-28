[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RuntimeDirectory,
    [Parameter(Mandatory=$true)][string]$Makensis,
    [Parameter(Mandatory=$true)][string]$UpgradeAuditor,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [switch]$AllowDifferentPayload
)
$ErrorActionPreference='Stop'
$config=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'release-config.json') -Raw|ConvertFrom-Json
$runtime=(Resolve-Path -LiteralPath $RuntimeDirectory).Path.TrimEnd('\')
$compiler=(Resolve-Path -LiteralPath $Makensis).Path
$auditor=(Resolve-Path -LiteralPath $UpgradeAuditor).Path
$repository=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
$output=[IO.Path]::GetFullPath($OutputDirectory)
if(Test-Path -LiteralPath $output){throw 'Choose a new output directory; existing output will not be overwritten.'}
if($output.StartsWith($runtime+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Output must not be inside the runtime.'}
$files=@(Get-ChildItem -LiteralPath $runtime -File -Recurse|Sort-Object FullName)
$actual=@{}
foreach($file in $files){
    if($file.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Runtime must not contain reparse-point files.'}
    $relative=$file.FullName.Substring($runtime.Length+1).Replace('\','/')
    $actual[$relative]=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
}
foreach($required in @('bin/minecraft-javaw.exe','bin/minecraft-javaw-multimc.exe','bin/minecraft-javaw-olauncher.exe','lib/legacy-windows/internal/launcher/executables/java.exe')){
    if(-not $actual.ContainsKey($required)){throw "Required runtime file missing: $required"}
}
if($actual['bin/minecraft-javaw.exe'] -ne $actual['bin/minecraft-javaw-multimc.exe']){throw 'MultiMC compatibility filenames must be byte-identical.'}
$expected=@{}
foreach($line in Get-Content -LiteralPath (Join-Path $PSScriptRoot 'PAYLOAD-SHA256SUMS.txt')){
    if($line -match '^([0-9a-fA-F]{64})\s+(.+)$'){$expected[$Matches[2]]=$Matches[1]} elseif($line.Trim()){throw 'Invalid published manifest.'}
}
$differences=@($actual.Keys|Where-Object{-not $expected.ContainsKey($_) -or $actual[$_] -ne $expected[$_]})
$missing=@($expected.Keys|Where-Object{-not $actual.ContainsKey($_)})
if(($differences.Count -or $missing.Count) -and -not $AllowDifferentPayload){throw 'Runtime differs from the published manifest. Review changes or explicitly use -AllowDifferentPayload for a new build.'}
[IO.Directory]::CreateDirectory($output)|Out-Null
$manifest=Join-Path $output "jdk25-$($config.targetOs)-x64-PAYLOAD-SHA256SUMS.txt"
$files|ForEach-Object{
    $relative=$_.FullName.Substring($runtime.Length+1).Replace('\','/')
    '{0}  {1}' -f $actual[$relative],$relative
}|Set-Content -LiteralPath $manifest -Encoding ascii
$installer=Join-Path $output $config.installer
$os=$config.targetOs
$label=$config.sourceLabel
if($AllowDifferentPayload){$label+='-local-rebuild'}
$arguments=@(
    '/V3','/WX',
    "/DPRODUCT_ID=jdk25-$os-x64",
    "/DPRODUCT_NAME=$($config.productName)",
    "/DDISPLAY_VERSION=25.0.4-legacy-windows-$os-x64-version2-$($config.revision)",
    "/DFILE_VERSION=25.0.4.$($config.revision.Substring(1))",
    "/DTARGET_OS=$os",
    "/DOS_LABEL=$($config.osLabel)",
    "/DINSTALL_FOLDER=jdk-25.0.4-$os-x64",
    "/DRUNTIME_DIR=$runtime",
    "/DOUTPUT_FILE=$installer",
    "/DLICENSE_FILE=$(Join-Path $repository 'LICENSE')",
    "/DADDITIONAL_LICENSE_FILE=$(Join-Path $repository 'ADDITIONAL_LICENSE_INFO')",
    "/DASSEMBLY_EXCEPTION_FILE=$(Join-Path $repository 'ASSEMBLY_EXCEPTION')",
    "/DPAYLOAD_MANIFEST=$manifest",
    "/DSOURCE_COMMIT=$label",
    '/DPAYLOAD_KIND=Minecraft 26 with MultiMC and OLauncher wrappers',
    "/DUPGRADE_AUDITOR=$auditor",
    "/DESTIMATED_SIZE_KB=$([int][Math]::Ceiling(($files|Measure-Object Length -Sum).Sum/1KB))",
    (Join-Path $PSScriptRoot 'legacy-openjdk.nsi')
)
& $compiler @arguments
if($LASTEXITCODE -ne 0 -or -not(Test-Path -LiteralPath $installer)){throw 'NSIS packaging failed.'}
@($installer,$manifest)|Get-FileHash -Algorithm SHA256|ForEach-Object{
    '{0}  {1}' -f $_.Hash,(Split-Path $_.Path -Leaf)
}|Set-Content -LiteralPath (Join-Path $output 'SHA256SUMS.txt') -Encoding ascii
Write-Output "INSTALLER=$installer"
Write-Output 'This is a local rebuild. Its installer hash may differ from the published artifact.'
