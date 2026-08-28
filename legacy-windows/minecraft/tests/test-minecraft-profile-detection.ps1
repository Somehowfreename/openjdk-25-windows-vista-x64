[CmdletBinding()]
param([string] $WorkspaceRoot, [string] $OutputDirectory)

$ErrorActionPreference = 'Stop'
$workspace = if ($WorkspaceRoot) { (Resolve-Path -LiteralPath $WorkspaceRoot).Path } else { (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..\..\..\..')).Path }
$msvc = Join-Path $workspace 'work\toolchains\msvc-14.29-portable\Contents\VC\Tools\MSVC\14.29.30133'
$sdk = Join-Path $workspace 'work\toolchains\winsdk-10.0.19041-portable\Windows Kits\10'
$sdkVersion = '10.0.19041.0'
$cl = Join-Path $msvc 'bin\Hostx64\x64\cl.exe'
$link = Join-Path $msvc 'bin\Hostx64\x64\link.exe'
$output = if ($OutputDirectory) { [IO.Path]::GetFullPath($OutputDirectory) } else { Join-Path $env:TEMP 'LegacyOpenJDK-Minecraft-Profile-Test' }
$object = Join-Path $output 'minecraft_profile_detection_test.obj'
$executable = Join-Path $output 'minecraft_profile_detection_test.exe'
$source = Join-Path $PSScriptRoot 'minecraft_profile_detection_test.cpp'

foreach ($required in @($cl, $link, $source)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required profile-test input is missing: $required"
    }
}
[IO.Directory]::CreateDirectory($output) | Out-Null

$includes = @(
    (Join-Path $msvc 'include'),
    (Join-Path $sdk "Include\$sdkVersion\ucrt"),
    (Join-Path $sdk "Include\$sdkVersion\shared"),
    (Join-Path $sdk "Include\$sdkVersion\um")
) | ForEach-Object { "/I$_" }
$libraries = @(
    "/LIBPATH:$(Join-Path $msvc 'lib\x64')",
    "/LIBPATH:$(Join-Path $msvc 'lib\onecore\x64')",
    "/LIBPATH:$(Join-Path $sdk "Lib\$sdkVersion\ucrt\x64")",
    "/LIBPATH:$(Join-Path $sdk "Lib\$sdkVersion\um\x64")"
)

& $cl /nologo /c /TP /O2 /MT /W4 @includes "/Fo$object" $source
if ($LASTEXITCODE -ne 0) { throw 'Compiling profile detection test failed.' }
& $link /nologo /machine:x64 /subsystem:console "/out:$executable" `
    $object @libraries
if ($LASTEXITCODE -ne 0) { throw 'Linking profile detection test failed.' }
& $executable
if ($LASTEXITCODE -ne 0) { throw 'Minecraft profile detection test failed.' }
