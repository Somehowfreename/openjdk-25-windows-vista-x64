param(
    [Parameter(Mandatory = $true)][string]$ImageRoot,
    [Parameter(Mandatory = $true)][string]$LlvmReadObj,
    [ValidateRange(0, 65535)][int]$TargetWindowsMajor = 5,
    [ValidateRange(0, 65535)][int]$TargetWindowsMinor = 2,
    [hashtable]$ImportMappings = @{ 'KERNEL32.dll' = 'JDKXP.dll' }
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $ImageRoot).Path
$reader = (Resolve-Path -LiteralPath $LlvmReadObj).Path
$patchedFiles = 0
$patchedOccurrences = 0
$headerPatchedFiles = 0

foreach ($entry in $ImportMappings.GetEnumerator()) {
    if ([Text.Encoding]::ASCII.GetByteCount($entry.Value) -gt
        [Text.Encoding]::ASCII.GetByteCount($entry.Key)) {
        throw "Replacement import name '$($entry.Value)' is longer than '$($entry.Key)'"
    }
}

function Set-UInt16LittleEndian {
    param([byte[]]$Bytes, [int]$Offset, [int]$Value)
    $Bytes[$Offset] = $Value -band 0xff
    $Bytes[$Offset + 1] = ($Value -shr 8) -band 0xff
}

Get-ChildItem -LiteralPath $root -Recurse -File |
    Where-Object { $_.Extension -in '.exe', '.dll', '.drv' } |
    ForEach-Object {
        $bytes = [IO.File]::ReadAllBytes($_.FullName)
        if ($bytes.Length -lt 64 -or $bytes[0] -ne 0x4d -or $bytes[1] -ne 0x5a) {
            return
        }
        $peOffset = [BitConverter]::ToUInt32($bytes, 0x3c)
        $optionalOffset = $peOffset + 24
        if ($optionalOffset + 52 -gt $bytes.Length -or
            $bytes[$peOffset] -ne 0x50 -or $bytes[$peOffset + 1] -ne 0x45 -or
            $bytes[$peOffset + 2] -ne 0 -or $bytes[$peOffset + 3] -ne 0) {
            return
        }
        $magic = [BitConverter]::ToUInt16($bytes, $optionalOffset)
        if ($magic -notin 0x10b, 0x20b) { return }

        $headerChanged =
            [BitConverter]::ToUInt16($bytes, $optionalOffset + 40) -ne $TargetWindowsMajor -or
            [BitConverter]::ToUInt16($bytes, $optionalOffset + 42) -ne $TargetWindowsMinor -or
            [BitConverter]::ToUInt16($bytes, $optionalOffset + 48) -ne $TargetWindowsMajor -or
            [BitConverter]::ToUInt16($bytes, $optionalOffset + 50) -ne $TargetWindowsMinor
        if ($headerChanged) {
            Set-UInt16LittleEndian $bytes ($optionalOffset + 40) $TargetWindowsMajor
            Set-UInt16LittleEndian $bytes ($optionalOffset + 42) $TargetWindowsMinor
            Set-UInt16LittleEndian $bytes ($optionalOffset + 48) $TargetWindowsMajor
            Set-UInt16LittleEndian $bytes ($optionalOffset + 50) $TargetWindowsMinor
            ++$headerPatchedFiles
        }

        $imports = & $reader --coff-imports $_.FullName 2>$null
        $importsText = $imports -join "`n"
        $changes = 0
        if ($LASTEXITCODE -eq 0) {
            foreach ($entry in $ImportMappings.GetEnumerator()) {
                $oldModule = $entry.Key.ToString()
                $newModule = $entry.Value.ToString()
                # A proxy must keep its own import of the real system module;
                # replacing it would create a self-import. Other proxies are
                # still processed, allowing JDKI's Kernel32 dependency to be
                # routed through JDKXP in the same pass.
                if ($_.Name -ieq $newModule) {
                    continue
                }
                $matchedModules = @(
                    [regex]::Matches(
                        $importsText,
                        "(?im)^  Name: ($([regex]::Escape($oldModule)))$") |
                        ForEach-Object { $_.Groups[1].Value } |
                        Sort-Object -Unique
                )
                if ($matchedModules.Count -eq 0) {
                    continue
                }
                $newName = [Text.Encoding]::ASCII.GetBytes($newModule)
                $moduleChanges = 0
                # Converting once and using the runtime's ordinal substring search is
                # dramatically faster than comparing every byte in PowerShell for
                # large native images (Mesa's opengl32.dll is nearly 40 MiB). ASCII
                # decoding remains one character per input byte, including NULs, so
                # the returned character offset is also the exact file offset.
                foreach ($matchedModule in $matchedModules) {
                    $oldName = [Text.Encoding]::ASCII.GetBytes($matchedModule)
                    $byteText = [Text.Encoding]::ASCII.GetString($bytes)
                    $offset = 0
                    while (($offset = $byteText.IndexOf(
                                $matchedModule, $offset,
                                [StringComparison]::Ordinal)) -ge 0) {

                        for ($index = 0; $index -lt $oldName.Length; ++$index) {
                            $bytes[$offset + $index] = if ($index -lt $newName.Length) {
                                $newName[$index]
                            } else {
                                0
                            }
                        }
                        ++$moduleChanges
                        ++$changes
                        $offset += $oldName.Length
                    }
                }
                if ($moduleChanges -eq 0) {
                    throw "Import parser found $oldModule, but its name was not found in $($_.FullName)"
                }
            }
            if ($changes -ne 0) {
                ++$patchedFiles
                $patchedOccurrences += $changes
            }
        }

        if ($headerChanged -or $changes -ne 0) {
            [IO.File]::WriteAllBytes($_.FullName, $bytes)
        }
    }

Write-Output "Patched $patchedOccurrences import module names in $patchedFiles PE files under $root."
Write-Output "Set Windows OS and subsystem version $TargetWindowsMajor.$TargetWindowsMinor in $headerPatchedFiles PE files."
