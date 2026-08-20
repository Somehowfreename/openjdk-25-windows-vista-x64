[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $MsvcRoot,

    [Parameter(Mandatory)]
    [string] $WindowsSdkRoot,

    [string] $WindowsSdkVersion = '10.0.19041.0',

    [string] $OutputDirectory = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
$compiler = Join-Path $MsvcRoot 'bin\Hostx64\x64\cl.exe'
$linker = Join-Path $MsvcRoot 'bin\Hostx64\x64\link.exe'
$source = Join-Path $PSScriptRoot 'import-sst.c'
$object = Join-Path $OutputDirectory 'import-sst.obj'
$output = Join-Path $OutputDirectory 'import-sst-xp-x64.exe'

foreach ($required in @($compiler, $linker, $source)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required input is missing: $required"
    }
}
[IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null

$includes = @(
    "/I$(Join-Path $MsvcRoot 'include')",
    "/I$(Join-Path $WindowsSdkRoot "Include\$WindowsSdkVersion\ucrt")",
    "/I$(Join-Path $WindowsSdkRoot "Include\$WindowsSdkVersion\shared")",
    "/I$(Join-Path $WindowsSdkRoot "Include\$WindowsSdkVersion\um")"
)
& $compiler /nologo /c /TC /O2 /MT /W4 /WX /GS- @includes `
    "/Fo$object" $source
if ($LASTEXITCODE -ne 0) { throw 'Compiling import-sst failed.' }

$libraries = @(
    "/LIBPATH:$(Join-Path $MsvcRoot 'lib\x64')",
    "/LIBPATH:$(Join-Path $MsvcRoot 'lib\onecore\x64')",
    "/LIBPATH:$(Join-Path $WindowsSdkRoot "Lib\$WindowsSdkVersion\ucrt\x64")",
    "/LIBPATH:$(Join-Path $WindowsSdkRoot "Lib\$WindowsSdkVersion\um\x64")"
)
& $linker /nologo /subsystem:console,5.02 /osversion:5.02 `
    "/out:$output" $object @libraries kernel32.lib crypt32.lib `
    /OPT:REF /OPT:ICF /Brepro
if ($LASTEXITCODE -ne 0) { throw 'Linking import-sst failed.' }

Write-Output "IMPORT_SST=$output"
Write-Output "SHA256=$((Get-FileHash -Algorithm SHA256 -LiteralPath $output).Hash)"
