param(
    [Parameter(Mandatory = $true)][string]$LlvmReadObj,
    [Parameter(Mandatory = $true)][string]$XpKernel32,
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Output,
    [string]$Dumpbin,
    [string]$Kernel32ImportLib,
    [string[]]$TargetRoot,
    [hashtable]$ExportAliases = @{
        'RaiseFailFastException' = 'JdkXpRaiseFailFastException'
        'ConvertInterfaceLuidToNameW' = 'JdkXpConvertInterfaceLuidToNameW'
        'ConvertInterfaceNameToLuidW' = 'JdkXpConvertInterfaceNameToLuidW'
        'ConvertLengthToIpv4Mask' = 'JdkXpConvertLengthToIpv4Mask'
        'FreeMibTable' = 'JdkXpFreeMibTable'
        'GetAdaptersAddresses' = 'JdkXpGetAdaptersAddresses'
        'GetAnycastIpAddressTable' = 'JdkXpGetAnycastIpAddressTable'
        'GetIfEntry2' = 'JdkXpGetIfEntry2'
        'GetIfTable2' = 'JdkXpGetIfTable2'
        'GetUnicastIpAddressTable' = 'JdkXpGetUnicastIpAddressTable'
        'Icmp6CreateFile' = 'JdkXpIcmp6CreateFile'
        'Icmp6SendEcho2' = 'JdkXpIcmp6SendEcho2'
        'IcmpCloseHandle' = 'JdkXpIcmpCloseHandle'
        'IcmpCreateFile' = 'JdkXpIcmpCreateFile'
        'IcmpSendEcho' = 'JdkXpIcmpSendEcho'
        'IcmpSendEcho2Ex' = 'JdkXpIcmpSendEcho2Ex'
        'NotifyAddrChange' = 'JdkXpNotifyAddrChange'
    },
    [string[]]$ExcludeFileName = @(
        'api-ms-win-crt-*.dll', 'concrt140.dll', 'msvcp140.dll',
        'msvcp140_1.dll', 'msvcp140_2.dll', 'ucrtbase.dll',
        'vcruntime140.dll', 'vcruntime140_1.dll'
    )
)

$ErrorActionPreference = 'Stop'

$sourceText = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Source))
$implementedPattern = [regex]'(?s)__declspec\(dllexport\)\s+.*?\bWINAPI\s+([A-Za-z_]\w*)\s*\('
$implemented = @(
    $implementedPattern.Matches($sourceText) |
        ForEach-Object { $_.Groups[1].Value } |
        Sort-Object -Unique
)
$allFunctionsPattern = [regex]'\bWINAPI\s+([A-Za-z_]\w*)\s*\('
$allFunctions = @(
    $allFunctionsPattern.Matches($sourceText) |
        ForEach-Object { $_.Groups[1].Value } |
        Sort-Object -Unique
)
$aliasTargets = @{}
foreach ($target in $ExportAliases.Values) {
    if ($target -notin $allFunctions) {
        throw "Export alias target is not implemented by the source: $target"
    }
    $aliasTargets[$target] = $true
}
$publicImplemented = @(
    $implemented | Where-Object { -not $aliasTargets.ContainsKey($_) }
    $ExportAliases.Keys
) | Sort-Object -Unique

$exportText = & (Resolve-Path -LiteralPath $LlvmReadObj) --coff-exports (Resolve-Path -LiteralPath $XpKernel32)
if ($LASTEXITCODE -ne 0) {
    throw "llvm-readobj failed with exit code $LASTEXITCODE"
}
$xpExports = @(
    $exportText |
        ForEach-Object {
            if ($_ -match '^  Name: (.+)$') { $Matches[1].Trim() }
        } |
        Where-Object { $_ -and $_ -match '^[A-Za-z_][A-Za-z0-9_@?$]*$' } |
        Sort-Object -Unique
)

$forwardExports = $xpExports
if ([bool]$Dumpbin -xor [bool]$Kernel32ImportLib) {
    throw 'Dumpbin and Kernel32ImportLib must be supplied together.'
}
if ($Dumpbin) {
    $linkerMembers = & (Resolve-Path -LiteralPath $Dumpbin) /nologo /linkermember:1 `
        (Resolve-Path -LiteralPath $Kernel32ImportLib)
    if ($LASTEXITCODE -ne 0) {
        throw "dumpbin failed with exit code $LASTEXITCODE"
    }
    $sdkExports = @{
    }
    foreach ($line in $linkerMembers) {
        if ($line -match '^\s+[0-9A-F]+\s+([A-Za-z_][A-Za-z0-9_@?$]*)\s*$') {
            $name = $Matches[1]
            if (-not $name.StartsWith('__imp_', [StringComparison]::Ordinal)) {
                $sdkExports[$name] = $true
            }
        }
    }
    $forwardExports = @(
        $xpExports | Where-Object { $sdkExports.ContainsKey($_) }
    )
}
if ($TargetRoot) {
    $needed = @{}
    Get-ChildItem -LiteralPath (Resolve-Path -LiteralPath $TargetRoot) -Recurse -File |
        Where-Object {
            if ($_.Extension -notin '.exe', '.dll', '.drv') { return $false }
            foreach ($pattern in $ExcludeFileName) {
                if ($_.Name -like $pattern) { return $false }
            }
            return $true
        } |
        ForEach-Object {
            $currentModule = ''
            $imports = & (Resolve-Path -LiteralPath $LlvmReadObj) --coff-imports $_.FullName 2>$null
            if ($LASTEXITCODE -ne 0) { return }
            foreach ($line in $imports) {
                if ($line -match '^  Name: (.+)$') {
                    $currentModule = $Matches[1].Trim()
                } elseif ($currentModule -iin @('KERNEL32.dll', 'JDKXP.dll') -and
                          $line -match '^  Symbol:\s+(.+?)(?:\s+\(\d+\))?$') {
                    $symbol = $Matches[1].Trim()
                    if ($symbol -notmatch '^\(\d+\)$') { $needed[$symbol] = $true }
                }
            }
        }
    $xpSet = @{}
    foreach ($name in $xpExports) { $xpSet[$name] = $true }
    $unsupported = @(
        $needed.Keys |
            Where-Object { -not $xpSet.ContainsKey($_) -and $_ -notin $publicImplemented } |
            Sort-Object
    )
    if ($unsupported.Count -ne 0) {
        throw "No XP implementation for imported Kernel32 symbols: $($unsupported -join ', ')"
    }
    $forwardExports = @(
        $needed.Keys | Where-Object { $xpSet.ContainsKey($_) } | Sort-Object
    )
}

$implementedSet = @{}
foreach ($name in $publicImplemented) { $implementedSet[$name] = $true }

$lines = [Collections.Generic.List[string]]::new()
$lines.Add('LIBRARY JDKXP')
$lines.Add('EXPORTS')
foreach ($name in $implemented) {
    if (-not $aliasTargets.ContainsKey($name)) { $lines.Add("  $name") }
}
foreach ($entry in $ExportAliases.GetEnumerator() | Sort-Object Key) {
    $lines.Add("  $($entry.Key)=$($entry.Value)")
}
foreach ($name in $forwardExports) {
    if (-not $implementedSet.ContainsKey($name)) {
        $lines.Add("  $name=KERNEL32.$name")
    }
}

$outputPath = [IO.Path]::GetFullPath($Output)
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputPath)) | Out-Null
[IO.File]::WriteAllLines($outputPath, $lines, [Text.UTF8Encoding]::new($false))
Write-Output "Generated $outputPath with $($publicImplemented.Count) public implementations and $($forwardExports.Count) Kernel32 forwarders."
