[CmdletBinding()]
param(
    [ValidateSet(17, 21, 25)]
    [int[]] $JavaMajor = @(25),

    [ValidatePattern('^r[0-9]+$')]
    [string] $Revision = 'r41',

    [ValidatePattern('^r[0-9]+$')]
    [string] $SupportRevision = $Revision,

    [ValidateSet('xp', 'vista')]
    [string[]] $TargetOs = @('vista'),
    [string] $WorkspaceRoot
)

$ErrorActionPreference = 'Stop'
$workspace = if ($WorkspaceRoot) { (Resolve-Path -LiteralPath $WorkspaceRoot).Path } else { (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..\..\..')).Path }
$reader = Join-Path $workspace 'work\toolchains\llvm-mingw-20260616-msvcrt-x86_64\bin\llvm-readobj.exe'
$patcher = Join-Path $workspace 'work\compat\jdkxp\patch-image.ps1'
$privateExecutableRelative = 'lib\legacy-windows\internal\launcher\executables'
$publicWrapperNames = @(
    'minecraft-java.exe',
    'minecraft-javaw.exe',
    'minecraft-javaw-multimc.exe',
    'minecraft-javaw-olauncher.exe'
)
$vmTestWrapperNames = @(
    'minecraft-java-software-rendering-multimc.exe',
    'minecraft-javaw-software-rendering-multimc.exe',
    'minecraft-javaw-software-rendering-olauncher.exe'
)
$legacyVmTestWrapperNames = @(
    'minecraft-java-software.exe',
    'minecraft-javaw-software.exe',
    'minecraft-javaw-software-olauncher.exe'
)

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
        Support = "work\release-builds\minecraft-wrapper-jdk17-vista-$SupportRevision\payload"
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
        Support = "work\release-builds\minecraft-wrapper-jdk21-vista-$SupportRevision\payload"
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
        Support = "work\release-builds\minecraft-wrapper-jdk25-vista-$SupportRevision\payload"
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
    $excludedVistaFiles = @(
        'bin\DWMAPI.dll',
        'minecraft-software\DWMAPI.dll',
        "$privateExecutableRelative\DWMAPI.dll",
        "$privateExecutableRelative\software\DWMAPI.dll"
    )

    # Copy the preserved base first, mapping every non-wrapper executable out
    # of bin and mapping the old software-runtime directory below the same
    # private tree. The support payload is then overlaid at its final paths.
    foreach ($sourceDescription in @(
        [pscustomobject]@{ Root = $base; IsBase = $true },
        [pscustomobject]@{ Root = $support; IsBase = $false }
    )) {
        $sourceTree = $sourceDescription.Root
        Get-ChildItem -LiteralPath $sourceTree -Recurse -File | ForEach-Object {
            $relative = $_.FullName.Substring($sourceTree.Length + 1)
            $mappedRelative = $relative

            if ($sourceDescription.IsBase -and
                $relative.StartsWith('bin\', [StringComparison]::OrdinalIgnoreCase) -and
                [IO.Path]::GetFileName($relative) -in $legacyVmTestWrapperNames) {
                $legacyName = [IO.Path]::GetFileName($relative)
                $mappedName = $legacyName.Replace('-software.exe', '-software-rendering-multimc.exe').Replace(
                    '-software-olauncher.exe', '-software-rendering-olauncher.exe')
                $mappedRelative = Join-Path 'bin\vmtests' $mappedName
            } elseif ($sourceDescription.IsBase -and
                $relative.StartsWith('bin\', [StringComparison]::OrdinalIgnoreCase) -and
                [IO.Path]::GetExtension($relative).Equals('.exe', [StringComparison]::OrdinalIgnoreCase) -and
                [IO.Path]::GetFileName($relative) -notin $publicWrapperNames) {
                $mappedRelative = Join-Path $privateExecutableRelative ([IO.Path]::GetFileName($relative))
            } elseif ($sourceDescription.IsBase -and
                      $relative.StartsWith('minecraft-software\', [StringComparison]::OrdinalIgnoreCase)) {
                $mappedRelative = Join-Path "$privateExecutableRelative\software" `
                    $relative.Substring('minecraft-software\'.Length)
            }

            if ($image.Target -eq 'vista' -and
                ($relative -in $excludedVistaFiles -or $mappedRelative -in $excludedVistaFiles)) {
                return
            }
            $destination = Join-Path $output $mappedRelative
            [IO.Directory]::CreateDirectory((Split-Path -Parent $destination)) | Out-Null
            Copy-Item -LiteralPath $_.FullName -Destination $destination -Force
        }
    }

    if ($image.JavaMajor -eq 25) {
        # Keep the rebuilt native launchers, module image, JMODs, source
        # archive, and CDS archives together. Mixing the older certified
        # module image or CDS archives with rebuilt native binaries produces
        # an incoherent runtime (and HotSpot rejects the stale CDS archives).
        $rebuiltJdk = Join-Path $workspace 'work\sources\openjdk25u-xp\build\w25xp-release-final1\images\jdk'
        $rebuiltJdkBin = Join-Path $rebuiltJdk 'bin'
        $rebuiltPrivateExecutableDirectory = Join-Path $output $privateExecutableRelative
        [IO.Directory]::CreateDirectory($rebuiltPrivateExecutableDirectory) | Out-Null

        Get-ChildItem -LiteralPath $rebuiltJdkBin -File -Filter '*.exe' |
            ForEach-Object {
                Copy-Item -LiteralPath $_.FullName `
                    -Destination (Join-Path $rebuiltPrivateExecutableDirectory $_.Name) -Force
            }

        foreach ($coherentRuntimeFile in @('lib\modules', 'lib\src.zip')) {
            $sourceRuntimeFile = Join-Path $rebuiltJdk $coherentRuntimeFile
            $destinationRuntimeFile = Join-Path $output $coherentRuntimeFile
            [IO.Directory]::CreateDirectory((Split-Path -Parent $destinationRuntimeFile)) | Out-Null
            Copy-Item -LiteralPath $sourceRuntimeFile -Destination $destinationRuntimeFile -Force
        }

        $rebuiltJmods = Join-Path $rebuiltJdk 'jmods'
        $outputJmods = Join-Path $output 'jmods'
        [IO.Directory]::CreateDirectory($outputJmods) | Out-Null
        Get-ChildItem -LiteralPath $rebuiltJmods -File -Filter '*.jmod' |
            ForEach-Object {
                Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $outputJmods $_.Name) -Force
            }

        Get-ChildItem -LiteralPath $rebuiltJdk -Recurse -File -Filter '*.jsa' |
            ForEach-Object {
                $relativeJsa = $_.FullName.Substring($rebuiltJdk.Length + 1)
                $destinationJsa = Join-Path $output $relativeJsa
                [IO.Directory]::CreateDirectory((Split-Path -Parent $destinationJsa)) | Out-Null
                Copy-Item -LiteralPath $_.FullName -Destination $destinationJsa -Force
            }

        # The final OpenJDK build contains the source-level XP clipboard
        # fallback. Redirect its Kernel32 imports through the runtime's
        # application-local compatibility DLL.
        $rebuiltAwt = Join-Path $rebuiltJdkBin 'awt.dll'
        $rebuiltJli = Join-Path $rebuiltJdkBin 'jli.dll'
        $rebuiltJvm = Join-Path $rebuiltJdkBin 'jvm.dll'
        Copy-Item -LiteralPath $rebuiltAwt -Destination (Join-Path $output 'bin\awt.dll') -Force
        Copy-Item -LiteralPath $rebuiltJli -Destination (Join-Path $output 'bin\jli.dll') -Force
        Copy-Item -LiteralPath $rebuiltJvm -Destination (Join-Path $output 'bin\jvm.dll') -Force
        & $patcher -ImageRoot (Join-Path $output 'bin') -LlvmReadObj $reader `
            -TargetWindowsMajor 5 -TargetWindowsMinor 2 `
            -ImportMappings @{ 'KERNEL32.dll' = 'JDKXP.dll' }
    }

    $privateExecutableDirectory = Join-Path $output $privateExecutableRelative
    [IO.Directory]::CreateDirectory($privateExecutableDirectory) | Out-Null

    # Windows resolves statically imported DLLs before launcher code executes.
    # Copy every application-local dependency available in bin beside the
    # private launchers. System DLLs are intentionally left to Windows.
    Get-ChildItem -LiteralPath $privateExecutableDirectory -File -Filter '*.exe' |
        ForEach-Object {
            $imports = & $reader --coff-imports $_.FullName
            if ($LASTEXITCODE -ne 0) {
                throw "Reading private executable imports failed: $($_.FullName)"
            }
            $imports | Select-String '^  Name: ' | ForEach-Object {
                $importName = $_.Line.Substring(8).Trim()
                $sourceDependency = Join-Path $output "bin\$importName"
                if (Test-Path -LiteralPath $sourceDependency -PathType Leaf) {
                    Copy-Item -LiteralPath $sourceDependency `
                        -Destination (Join-Path $privateExecutableDirectory $importName) -Force
                }
            }
        }

    $actualBinExecutables = @(Get-ChildItem -LiteralPath (Join-Path $output 'bin') `
        -File -Filter '*.exe' | Select-Object -ExpandProperty Name | Sort-Object)
    $expectedBinExecutables = @($publicWrapperNames | Sort-Object)
    $unexpectedBinExecutables = @(Compare-Object $expectedBinExecutables $actualBinExecutables)
    if ($unexpectedBinExecutables.Count -ne 0) {
        throw "Assembled image $($image.Id) has an invalid public bin executable set: $($unexpectedBinExecutables | Out-String)"
    }
    $actualVmTestExecutables = @(Get-ChildItem -LiteralPath (Join-Path $output 'bin\vmtests') `
        -File -Filter '*.exe' | Select-Object -ExpandProperty Name | Sort-Object)
    $expectedVmTestExecutables = @($vmTestWrapperNames | Sort-Object)
    $unexpectedVmTestExecutables = @(Compare-Object $expectedVmTestExecutables $actualVmTestExecutables)
    if ($unexpectedVmTestExecutables.Count -ne 0) {
        throw "Assembled image $($image.Id) has an invalid VM-test executable set: $($unexpectedVmTestExecutables | Out-String)"
    }

    $requiredRelatives = @(
        'bin\minecraft-java.exe',
        'bin\minecraft-javaw.exe',
        'bin\minecraft-javaw-multimc.exe',
        'bin\minecraft-javaw-olauncher.exe',
        'bin\vmtests\minecraft-javaw-software-rendering-olauncher.exe',
        'bin\vmtests\minecraft-java-software-rendering-multimc.exe',
        'bin\vmtests\minecraft-javaw-software-rendering-multimc.exe',
        "$privateExecutableRelative\java.exe",
        "$privateExecutableRelative\javaw.exe",
        "$privateExecutableRelative\javac.exe",
        "$privateExecutableRelative\jar.exe",
        "$privateExecutableRelative\jlink.exe",
        "$privateExecutableRelative\jpackage.exe",
        "$privateExecutableRelative\minecraft-java-runtime.exe",
        "$privateExecutableRelative\minecraft-javaw-runtime.exe",
        "$privateExecutableRelative\software\minecraft-java-software.exe",
        "$privateExecutableRelative\software\minecraft-javaw-software.exe",
        "$privateExecutableRelative\software\opengl32.dll",
        'bin\JDKXP.dll',
        'bin\OpenAL.dll',
        'bin\glfw.dll',
        'bin\lwjgl.dll',
        'bin\lwjgl341.dll',
        'bin\SDL3.dll',
        'bin\SDLS.dll',
        'bin\SDLU.dll',
        "$privateExecutableRelative\software\lwjgl.dll",
        "$privateExecutableRelative\software\lwjgl341.dll",
        "$privateExecutableRelative\software\SDL3.dll",
        "$privateExecutableRelative\software\SDLS.dll",
        "$privateExecutableRelative\software\SDLU.dll"
    )
    if ($image.JavaMajor -eq 25) {
        $requiredRelatives += @(
            'minecraft\26.2\compat\alsoft-xp.ini',
            'minecraft\1.21\natives-xp-x64\freetype.dll',
            "$privateExecutableRelative\1.21\minecraft-java-runtime.exe",
            "$privateExecutableRelative\1.21\minecraft-javaw-runtime.exe",
            "$privateExecutableRelative\1.21\lwjgl.dll",
            "$privateExecutableRelative\1.21\software\minecraft-java-software.exe",
            "$privateExecutableRelative\1.21\software\minecraft-javaw-software.exe",
            "$privateExecutableRelative\1.21\software\lwjgl.dll",
            "$privateExecutableRelative\1.21\software\opengl32.dll"
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
