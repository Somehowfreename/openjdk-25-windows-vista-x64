[CmdletBinding()]
param(
    [ValidateSet(17, 21, 25)]
    [int[]] $JavaMajor = @(17, 21, 25),

    [ValidatePattern('^r[0-9]+$')]
    [string] $Revision = 'r9',

    [ValidatePattern('^r[0-9]+$')]
    [string] $SupportRevision = $Revision,

    [ValidateSet('xp', 'vista')]
    [string[]] $TargetOs = @('xp', 'vista')
)

$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..\..\..')).Path
$reader = Join-Path $workspace 'work\toolchains\llvm-mingw-20260616-msvcrt-x86_64\bin\llvm-readobj.exe'
$patcher = Join-Path $workspace 'work\compat\jdkxp\patch-image.ps1'

$images = @(
    [pscustomobject]@{
        JavaMajor = 17
        Target = 'xp'
        Id = "jdk17-xp-x64-minecraft-$Revision"
        Base = 'work\artifacts\openjdk-17.0.20+1-legacy-windows-x64'
        Support = "work\release-builds\minecraft-wrapper-jdk17-$SupportRevision\payload"
        Output = "work\artifacts\openjdk-17.0.20-xp-x64-minecraft-wrapper-$Revision"
    },
    [pscustomobject]@{
        JavaMajor = 17
        Target = 'vista'
        Id = "jdk17-vista-x64-minecraft-$Revision"
        Base = 'work\artifacts\openjdk-17.0.20-xp-vista-x64-preview3'
        Support = "work\release-builds\minecraft-wrapper-jdk17-$SupportRevision\payload"
        Output = "work\artifacts\openjdk-17.0.20-vista-x64-minecraft-wrapper-$Revision"
    },
    [pscustomobject]@{
        JavaMajor = 21
        Target = 'xp'
        Id = "jdk21-xp-x64-minecraft-$Revision"
        Base = 'work\artifacts\openjdk-21.0.12+1-legacy-windows-x64'
        Support = "work\release-builds\minecraft-wrapper-jdk21-$SupportRevision\payload"
        Output = "work\artifacts\openjdk-21.0.12-xp-x64-minecraft-wrapper-$Revision"
    },
    [pscustomobject]@{
        JavaMajor = 21
        Target = 'vista'
        Id = "jdk21-vista-x64-minecraft-$Revision"
        Base = 'work\artifacts\openjdk-21.0.12-xp-vista-x64-candidate8'
        Support = "work\release-builds\minecraft-wrapper-jdk21-$SupportRevision\payload"
        Output = "work\artifacts\openjdk-21.0.12-vista-x64-minecraft-wrapper-$Revision"
    },
    [pscustomobject]@{
        JavaMajor = 25
        Target = 'xp'
        Id = "jdk25-xp-x64-minecraft-$Revision"
        Base = 'work\artifacts\openjdk-25.0.4-xp-x64-certified-final'
        Support = "work\release-builds\minecraft-wrapper-jdk25-$SupportRevision\payload"
        Output = "work\artifacts\openjdk-25.0.4-xp-x64-minecraft-wrapper-$Revision"
    },
    [pscustomobject]@{
        JavaMajor = 25
        Target = 'vista'
        Id = "jdk25-vista-x64-minecraft-$Revision"
        Base = 'work\artifacts\openjdk-25.0.4-xp-x64-certified-final'
        Support = "work\release-builds\minecraft-wrapper-jdk25-$SupportRevision\payload"
        Output = "work\artifacts\openjdk-25.0.4-vista-x64-minecraft-wrapper-$Revision"
    }
)

$images = @($images | Where-Object {
    $_.JavaMajor -in $JavaMajor -and $_.Target -in $TargetOs
})

foreach ($image in $images) {
    $base = Join-Path $workspace $image.Base
    $support = Join-Path $workspace $image.Support
    $output = Join-Path $workspace $image.Output
    foreach ($required in @($base, $support)) {
        if (-not (Test-Path -LiteralPath $required -PathType Container)) {
            throw "Required image input is missing: $required"
        }
    }
    if (Test-Path -LiteralPath $output) {
        throw "Refusing to replace preserved assembled image: $output"
    }

    [IO.Directory]::CreateDirectory($output) | Out-Null
    if ($image.Target -eq 'vista') {
        # The XP-local DWMAPI compatibility DLL is intentionally absent from
        # Vista images.  Keeping it beside the launchers shadows Vista's own
        # dwmapi.dll and breaks native desktop components that import later
        # Vista ordinals (including ordinal 100).  Copy file-by-file so a
        # preserved XP image never has to be modified or deleted.
        $excludedVistaFiles = @(
            'bin\DWMAPI.dll',
            'minecraft-software\DWMAPI.dll'
        )
        foreach ($sourceTree in @($base, $support)) {
            Get-ChildItem -LiteralPath $sourceTree -Recurse -File | ForEach-Object {
                $relative = $_.FullName.Substring($sourceTree.Length + 1)
                if ($relative -in $excludedVistaFiles) { return }
                $destination = Join-Path $output $relative
                [IO.Directory]::CreateDirectory((Split-Path -Parent $destination)) | Out-Null
                Copy-Item -LiteralPath $_.FullName -Destination $destination -Force
            }
        }
    } else {
        Copy-Item -Path (Join-Path $base '*') -Destination $output -Recurse
        Copy-Item -Path (Join-Path $support '*') -Destination $output -Recurse -Force
    }

    if ($image.JavaMajor -eq 25) {
        # The final OpenJDK build contains the source-level XP clipboard
        # fallback. The older certified game image predates that rebuild, so
        # overlay the rebuilt AWT binary and redirect its Kernel32 imports
        # through the runtime's application-local compatibility DLL.
        $rebuiltAwt = Join-Path $workspace 'work\sources\openjdk25u-xp\build\w25xp-release-final1\images\jdk\bin\awt.dll'
        Copy-Item -LiteralPath $rebuiltAwt -Destination (Join-Path $output 'bin\awt.dll') -Force
        & $patcher -ImageRoot (Join-Path $output 'bin') -LlvmReadObj $reader `
            -TargetWindowsMajor 5 -TargetWindowsMinor 2 `
            -ImportMappings @{ 'KERNEL32.dll' = 'JDKXP.dll' }
    }

    $requiredRelatives = @(
        'bin\java.exe',
        'bin\javaw.exe',
        'bin\minecraft-java.exe',
        'bin\minecraft-javaw.exe',
        'bin\minecraft-java-runtime.exe',
        'bin\minecraft-javaw-runtime.exe',
        'bin\minecraft-java-software.exe',
        'bin\minecraft-javaw-software.exe',
        'minecraft-software\minecraft-java-software.exe',
        'minecraft-software\minecraft-javaw-software.exe',
        'minecraft-software\opengl32.dll',
        'bin\JDKXP.dll',
        'bin\OpenAL.dll',
        'bin\glfw.dll',
        'bin\lwjgl.dll',
        'bin\lwjgl341.dll',
        'bin\SDL3.dll',
        'bin\SDLS.dll',
        'bin\SDLU.dll',
        'minecraft-software\lwjgl.dll',
        'minecraft-software\lwjgl341.dll',
        'minecraft-software\SDL3.dll',
        'minecraft-software\SDLS.dll',
        'minecraft-software\SDLU.dll'
    )
    if ($image.JavaMajor -eq 25) {
        $requiredRelatives += @(
            'minecraft\26.2\compat\alsoft-xp.ini'
        )
    }
    foreach ($requiredRelative in $requiredRelatives) {
        $required = Join-Path $output $requiredRelative
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Assembled image $($image.Id) is incomplete: $required"
        }
    }

    $manifest = Join-Path $output 'MINECRAFT-WRAPPER-SHA256SUMS.txt'
    Get-ChildItem -LiteralPath $support -Recurse -File |
        Where-Object {
            $relative = $_.FullName.Substring($support.Length + 1)
            $image.Target -ne 'vista' -or $relative -notin $excludedVistaFiles
        } |
        Sort-Object FullName |
        ForEach-Object {
            $relative = $_.FullName.Substring($support.Length + 1)
            $installed = Join-Path $output $relative
            $hash = Get-FileHash -LiteralPath $installed -Algorithm SHA256
            '{0}  {1}' -f $hash.Hash, $relative.Replace('\', '/')
        } | Set-Content -LiteralPath $manifest -Encoding ascii

    Write-Output "ASSEMBLED_IMAGE_PASS=$($image.Id) OUTPUT=$output"
}
