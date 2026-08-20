[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $InputJdkImage,
    [Parameter(Mandatory = $true)][string] $ProxyBuildDirectory,
    [Parameter(Mandatory = $true)][string] $LlvmReadObj,
    [Parameter(Mandatory = $true)][string] $OutputDirectory,
    [switch] $MapIphlpapi
)

$ErrorActionPreference = 'Stop'
$input = (Resolve-Path -LiteralPath $InputJdkImage).Path
$proxyBuild = (Resolve-Path -LiteralPath $ProxyBuildDirectory).Path
$reader = (Resolve-Path -LiteralPath $LlvmReadObj).Path
$output = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $output) {
    throw "Refusing to overwrite an existing release image: $output"
}
foreach ($name in @('JDKXP.dll', 'api-ms-win-core-synch-l1-1-0.dll')) {
    if (-not (Test-Path -LiteralPath (Join-Path $proxyBuild $name) -PathType Leaf)) {
        throw "Proxy build is incomplete: $name"
    }
}
[IO.Directory]::CreateDirectory($output) | Out-Null

$excludedRedistributables = @(
    'api-ms-win-crt-*.dll', 'concrt140.dll', 'msvcp140.dll',
    'msvcp140_1.dll', 'msvcp140_2.dll', 'ucrtbase.dll',
    'vcruntime140.dll', 'vcruntime140_1.dll'
)
& robocopy.exe $input $output /E /R:0 /W:0 /NFL /NDL /NJH /NJS /NC /NS /NP `
    /XF @excludedRedistributables
if ($LASTEXITCODE -ge 8) { throw "Copying the JDK image failed: $LASTEXITCODE" }

$mappings = @{ 'KERNEL32.dll' = 'JDKXP.dll' }
if ($MapIphlpapi) { $mappings['IPHLPAPI.DLL'] = 'JDKXP.dll' }
& (Join-Path $PSScriptRoot 'patch-image.ps1') -ImageRoot $output `
    -LlvmReadObj $reader -TargetWindowsMajor 5 -TargetWindowsMinor 2 `
    -ImportMappings $mappings
Copy-Item -LiteralPath (Join-Path $proxyBuild 'JDKXP.dll') `
    -Destination (Join-Path $output 'bin\JDKXP.dll')
Copy-Item -LiteralPath (Join-Path $proxyBuild 'api-ms-win-core-synch-l1-1-0.dll') `
    -Destination (Join-Path $output 'bin\api-ms-win-core-synch-l1-1-0.dll')

$manifest = Join-Path $output 'SHA256SUMS.txt'
Get-ChildItem -LiteralPath $output -Recurse -File | Sort-Object FullName |
    Get-FileHash -Algorithm SHA256 | ForEach-Object {
        '{0}  {1}' -f $_.Hash, $_.Path.Substring($output.Length + 1).Replace('\', '/')
    } | Set-Content -LiteralPath $manifest -Encoding ascii
Write-Output "RELEASE_IMAGE=$output"
Write-Output "SHA256_MANIFEST=$manifest"
