[CmdletBinding()]
param(
    [ValidateSet(17, 21, 25)]
    [int[]] $JavaMajor = @(17, 21, 25),

    [ValidatePattern('^r[0-9]+$')]
    [string] $OutputRevision = 'r9',

    [ValidatePattern('^r[0-9]+$')]
    [string] $LwjglCompatRevision = 'r3',

    [ValidatePattern('^r[0-9]+$')]
    [string] $SdlCompatRevision = 'r1'
)

$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..\..\..')).Path
$msvc = Join-Path $workspace 'work\toolchains\msvc-14.29-portable\Contents\VC\Tools\MSVC\14.29.30133'
$sdk = Join-Path $workspace 'work\toolchains\winsdk-10.0.19041-portable\Windows Kits\10'
$sdkVersion = '10.0.19041.0'
$cl = Join-Path $msvc 'bin\Hostx64\x64\cl.exe'
$link = Join-Path $msvc 'bin\Hostx64\x64\link.exe'
$reader = Join-Path $workspace 'work\toolchains\llvm-mingw-20260616-msvcrt-x86_64\bin\llvm-readobj.exe'
$patcher = Join-Path $workspace 'work\compat\jdkxp\patch-image.ps1'
$preloadLibraries = Join-Path $workspace 'work\compat\minecraftxp\preload'
$source = Join-Path $PSScriptRoot 'minecraft_wrapper_options.cpp'
$dispatcherSource = Join-Path $PSScriptRoot 'minecraft_software_dispatcher.c'
$lwjglCompatPayload = Join-Path $workspace "work\release-builds\lwjgl-memoryutil-compat-$LwjglCompatRevision\payload"
$sdlCompatPayload = Join-Path $workspace "work\release-builds\sdl3-isolated-compat-$SdlCompatRevision\payload"

$definitions = @{
    17 = [pscustomobject]@{
        Source = 'work\sources\openjdk17u-xp'
        Configuration = 'w17xp-release-final1'
        Version = '17.0.20'
        Native = 'work\minecraft\official\versions\1.20.1\natives-windows-x64-xp-r2'
        EnhancedJdkXp = 'work\release-builds\openjdk17-jdkxp-minecraft-final1\JDKXP.dll'
        MinecraftVersion = '1.20.1'
        FullPreload = $false
    }
    21 = [pscustomobject]@{
        Source = 'work\sources\openjdk21u-xp'
        Configuration = 'w21xp-release-final1'
        Version = '21.0.12'
        Native = 'work\minecraft\official\versions\1.21.1\natives-windows-x64-xp-r3'
        EnhancedJdkXp = 'work\release-builds\openjdk21-jdkxp-minecraft-final1\JDKXP.dll'
        MinecraftVersion = '1.21.1'
        FullPreload = $false
    }
    25 = [pscustomobject]@{
        Source = 'work\sources\openjdk25u-xp'
        Configuration = 'w25xp-release-final1'
        Version = '25.0.4'
        Native = 'work\minecraft\xp-known-good\certified-final\versions\26.2\natives-windows-x64'
        EnhancedJdkXp = 'work\artifacts\openjdk-25.0.4-xp-x64-certified-final\bin\JDKXP.dll'
        MinecraftVersion = '26.2'
        FullPreload = $true
    }
}

foreach ($required in @($cl, $link, $reader, $patcher, $source, $dispatcherSource)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required build input is missing: $required"
    }
}

$commonIncludes = @(
    (Join-Path $msvc 'include'),
    (Join-Path $sdk "Include\$sdkVersion\ucrt"),
    (Join-Path $sdk "Include\$sdkVersion\shared"),
    (Join-Path $sdk "Include\$sdkVersion\um")
)
$commonLibraries = @(
    "/LIBPATH:$(Join-Path $msvc 'lib\x64')",
    "/LIBPATH:$(Join-Path $msvc 'lib\onecore\x64')",
    "/LIBPATH:$(Join-Path $sdk "Lib\$sdkVersion\ucrt\x64")",
    "/LIBPATH:$(Join-Path $sdk "Lib\$sdkVersion\um\x64")",
    "/LIBPATH:$preloadLibraries"
)
$dispatcherIncludes = @($commonIncludes | ForEach-Object { "/I$_" })

foreach ($major in $JavaMajor) {
    $definition = $definitions[$major]
    $jdkSource = Join-Path $workspace $definition.Source
    $build = Join-Path $jdkSource "build\$($definition.Configuration)"
    $jdkImage = Join-Path $build 'images\jdk'
    $generatedInclude = Join-Path $build 'support\modules_include\java.base'
    $outputRoot = Join-Path $workspace "work\release-builds\minecraft-wrapper-jdk$major-$OutputRevision"
    $payload = Join-Path $outputRoot 'payload'
    $payloadBin = Join-Path $payload 'bin'
    $payloadSoftware = Join-Path $payload 'minecraft-software'
    $payloadNative = Join-Path $payload "minecraft\$($definition.MinecraftVersion)\natives-xp-x64"
    $buildObjects = Join-Path $outputRoot 'objects'

    if (Test-Path -LiteralPath $outputRoot) {
        throw "Refusing to replace preserved wrapper build: $outputRoot"
    }
    foreach ($directory in @($payloadBin, $payloadSoftware, $payloadNative, $buildObjects)) {
        [IO.Directory]::CreateDirectory($directory) | Out-Null
    }

    $requiredInputs = @(
        $jdkImage,
        $generatedInclude,
        (Join-Path $jdkSource 'src\java.base\share\native\launcher\main.c'),
        (Join-Path $build 'support\native\java.base\libjli\jli.lib'),
        (Join-Path $build 'support\modules_libs\java.base\jvm.lib'),
        (Join-Path $workspace $definition.Native),
        (Join-Path $workspace $definition.EnhancedJdkXp),
        (Join-Path $preloadLibraries 'OpenAL.lib'),
        (Join-Path $preloadLibraries 'glfw.lib'),
        (Join-Path $preloadLibraries 'glfw_mesa.lib'),
        (Join-Path $preloadLibraries 'mesa3d32.lib')
    )
    if ($definition.FullPreload) {
        $requiredInputs += @('lwjgl.lib', 'lwjgl_opengl.lib', 'lwjgl_stb.lib', 'lwjgl_tinyfd.lib') |
            ForEach-Object { Join-Path $preloadLibraries $_ }
        $requiredInputs += @('lwjgl.dll', 'lwjgl341.dll') |
            ForEach-Object { Join-Path $lwjglCompatPayload $_ }
        $requiredInputs += @('SDL3.dll', 'SDLS.dll', 'SDLU.dll') |
            ForEach-Object { Join-Path $sdlCompatPayload $_ }
    }
    foreach ($required in $requiredInputs) {
        if (-not (Test-Path -LiteralPath $required)) {
            throw "Java $major wrapper input is missing: $required"
        }
    }

    $includes = @(
        $commonIncludes
        (Join-Path $jdkSource 'src\java.base\share\native\launcher')
        (Join-Path $jdkSource 'src\java.base\share\native\libjli')
        (Join-Path $jdkSource 'src\java.base\windows\native\libjli')
        (Join-Path $jdkSource 'src\java.base\share\native\include')
        (Join-Path $jdkSource 'src\java.base\windows\native\include')
        (Join-Path $jdkSource 'src\hotspot\share\include')
        (Join-Path $jdkSource 'src\hotspot\os\windows\include')
        $generatedInclude
    ) | ForEach-Object { "/I$_" }

    $optionsObject = Join-Path $buildObjects 'minecraft-wrapper-options.obj'
    & $cl /nologo /c /TP /O2 /MT /W4 /EHsc /GS- /D_CRT_SECURE_NO_WARNINGS `
        "/DMINECRAFT_JAVA_MAJOR=$major" @includes "/Fo$optionsObject" $source
    if ($LASTEXITCODE -ne 0) { throw "Compiling Java $major wrapper options failed." }
    $softwareOptionsObject = Join-Path $buildObjects 'minecraft-wrapper-options-software.obj'
    & $cl /nologo /c /TP /O2 /MT /W4 /EHsc /GS- /D_CRT_SECURE_NO_WARNINGS /DMINECRAFT_SOFTWARE_ORIGINAL_MODULES "/DMINECRAFT_JAVA_MAJOR=$major" @includes "/Fo$softwareOptionsObject" $source
    if ($LASTEXITCODE -ne 0) { throw "Compiling Java $major isolated software options failed." }

    $mainObjects = @{}
    foreach ($kind in @('console', 'windows')) {
        $mainObject = Join-Path $buildObjects "main-$kind.obj"
        $defines = @('/DWIN32', '/D_WINDOWS', '/DMINECRAFT_LEGACY_WRAPPER', "/DVERSION_STRING=`"$($definition.Version)`"", '/DENABLE_ARG_FILES')
        if ($kind -eq 'windows') { $defines += '/DJAVAW' }
        & $cl /nologo /c /TC /O2 /MT /W3 @defines @includes "/Fo$mainObject" `
            (Join-Path $jdkSource 'src\java.base\share\native\launcher\main.c')
        if ($LASTEXITCODE -ne 0) { throw "Compiling Java $major $kind launcher entry point failed." }
        $mainObjects[$kind] = $mainObject
    }

    $jliLibrary = Join-Path $build 'support\native\java.base\libjli\jli.lib'
    $jvmLibrary = Join-Path $build 'support\modules_libs\java.base\jvm.lib'
    $preloadImports = @('OpenAL.lib', 'glfw.lib', 'opengl32.lib')
    $softwareImports = @('OpenAL.lib', 'glfw_mesa.lib', 'mesa3d32.lib')
    if ($definition.FullPreload) {
        $bindingImports = @('lwjgl.lib', 'lwjgl_opengl.lib', 'lwjgl_stb.lib', 'lwjgl_tinyfd.lib')
        $preloadImports = @('OpenAL.lib') + $bindingImports + @('glfw.lib', 'opengl32.lib')
        $softwareImports = @('OpenAL.lib') + $bindingImports + @('glfw_mesa.lib', 'mesa3d32.lib')
    }

    $launchers = @(
        [pscustomobject]@{ Directory=$payloadBin; Name='minecraft-java.exe'; Kind='console'; Imports=$preloadImports; Options=$optionsObject },
        [pscustomobject]@{ Directory=$payloadBin; Name='minecraft-javaw.exe'; Kind='windows'; Imports=$preloadImports; Options=$optionsObject },
        [pscustomobject]@{ Directory=$payloadSoftware; Name='minecraft-java-software.exe'; Kind='console'; Imports=$preloadImports; Options=$softwareOptionsObject },
        [pscustomobject]@{ Directory=$payloadSoftware; Name='minecraft-javaw-software.exe'; Kind='windows'; Imports=$preloadImports; Options=$softwareOptionsObject }
    )
    foreach ($launcher in $launchers) {
        $output = Join-Path $launcher.Directory $launcher.Name
        $subsystem = if ($launcher.Kind -eq 'windows') { '/SUBSYSTEM:WINDOWS,5.02' } else { '/SUBSYSTEM:CONSOLE,5.02' }
        & $link /nologo /machine:x64 $subsystem /osversion:5.02 `
            /include:minecraft_legacy_native_preload_anchor "/out:$output" `
            "/implib:$(Join-Path $buildObjects ($launcher.Name + '.lib'))" `
            $mainObjects[$launcher.Kind] $launcher.Options $jliLibrary $jvmLibrary `
            @commonLibraries @($launcher.Imports) /OPT:REF /OPT:ICF
        if ($LASTEXITCODE -ne 0) { throw "Linking Java $major $($launcher.Name) failed." }
    }

    # Preserve the familiar bin\minecraft-java[w]-software.exe entry points
    # while keeping Mesa and the original GLFW/OpenGL module names isolated in
    # the sibling minecraft-software directory.
    foreach ($dispatcher in @(
        [pscustomobject]@{ Name='minecraft-java-software.exe'; Kind='console'; Defines=@() },
        [pscustomobject]@{ Name='minecraft-javaw-software.exe'; Kind='windows'; Defines=@('/DMINECRAFT_DISPATCH_WINDOWS') }
    )) {
        $object = Join-Path $buildObjects ("dispatcher-$($dispatcher.Kind).obj")
        & $cl /nologo /c /TC /O2 /MT /W4 /GS- /D_CRT_SECURE_NO_WARNINGS `
            @($dispatcher.Defines) @dispatcherIncludes "/Fo$object" $dispatcherSource
        if ($LASTEXITCODE -ne 0) { throw "Compiling Java $major $($dispatcher.Name) dispatcher failed." }
        $output = Join-Path $payloadBin $dispatcher.Name
        $subsystem = if ($dispatcher.Kind -eq 'windows') { '/SUBSYSTEM:WINDOWS,5.02' } else { '/SUBSYSTEM:CONSOLE,5.02' }
        & $link /nologo /machine:x64 $subsystem /osversion:5.02 "/out:$output" `
            $object @commonLibraries user32.lib /OPT:REF /OPT:ICF
        if ($LASTEXITCODE -ne 0) { throw "Linking Java $major $($dispatcher.Name) dispatcher failed." }
    }

    # Redirect any newly introduced Kernel32 imports through the same
    # application-local compatibility layer used by the JDK image.
    & $patcher -ImageRoot $payloadBin -LlvmReadObj $reader `
        -TargetWindowsMajor 5 -TargetWindowsMinor 2 `
        -ImportMappings @{ 'KERNEL32.dll' = 'JDKXP.dll' }
    & $patcher -ImageRoot $payloadSoftware -LlvmReadObj $reader `
        -TargetWindowsMajor 5 -TargetWindowsMinor 2 `
        -ImportMappings @{ 'KERNEL32.dll' = 'JDKXP.dll' }

    Copy-Item -LiteralPath (Join-Path $workspace $definition.EnhancedJdkXp) `
        -Destination (Join-Path $payloadBin 'JDKXP.dll')

    $nativeSource = Join-Path $workspace $definition.Native
    if ($major -eq 25) {
        Get-ChildItem -LiteralPath (Join-Path $nativeSource 'lwjgl') -File -Filter '*.dll' |
            # Keep the runtime's already-certified superset forwarders. The
            # game-native directory also contains narrower JDKA/JDKD/JDKS/JDKU
            # builds; replacing the runtime copies drops exports needed by the
            # JDK and Mesa when everything is installed into one bin folder.
            Where-Object Name -notin @(
                'freetype.dll', 'JDKXP.dll',
                'JDKA.dll', 'JDKD.dll', 'JDKS.dll', 'JDKU.dll'
            ) |
            Copy-Item -Destination $payloadBin -Force
        Copy-Item -LiteralPath (Join-Path $nativeSource 'jna\jnidispatch.dll') -Destination $payloadBin -Force
        Copy-Item -LiteralPath (Join-Path $nativeSource 'lwjgl\freetype.dll') -Destination $payloadNative

        # Install the certified LWJGL 3.4.1 native under a private module name
        # and expose its complete API through the forwarding proxy. The proxy
        # additionally supplies the MemoryUtil page-size and cache-line-size
        # JNI methods introduced by LWJGL 3.4.2 (Minecraft 26.3 Snapshot 9).
        Copy-Item -LiteralPath (Join-Path $lwjglCompatPayload 'lwjgl341.dll') `
            -Destination $payloadBin -Force
        Copy-Item -LiteralPath (Join-Path $lwjglCompatPayload 'lwjgl.dll') `
            -Destination $payloadBin -Force

        # Snapshot 9's SDL 3 native uses private shell/user compatibility
        # module names. This keeps SDL's larger proxy surfaces isolated from
        # the JDK's own JDKS.dll and JDKU.dll modules.
        Copy-Item -LiteralPath (Join-Path $sdlCompatPayload 'SDL3.dll') `
            -Destination $payloadBin -Force
        Copy-Item -LiteralPath (Join-Path $sdlCompatPayload 'SDLS.dll') `
            -Destination $payloadBin -Force
        Copy-Item -LiteralPath (Join-Path $sdlCompatPayload 'SDLU.dll') `
            -Destination $payloadBin -Force
        $compatSource = Join-Path $workspace 'work\minecraft\compat\26.2\jtracy\jtracy-1.0.37-natives-windows-xp.jar'
        $compatTarget = Join-Path $payload 'minecraft\26.2\compat'
        [IO.Directory]::CreateDirectory($compatTarget) | Out-Null
        Copy-Item -LiteralPath $compatSource -Destination $compatTarget
        Copy-Item -LiteralPath (Join-Path $workspace 'work\minecraft\official\versions\26.2\natives-windows-x64\Tracy_LICENSE') `
            -Destination $compatTarget
    } else {
        Get-ChildItem -LiteralPath $nativeSource -File -Filter '*.dll' |
            Where-Object Name -notin @('JDKXP.dll', 'freetype.dll') |
            Copy-Item -Destination $payloadBin -Force
        if ($major -eq 21) {
            Copy-Item -LiteralPath (Join-Path $nativeSource 'freetype.dll') -Destination $payloadNative
        }
    }

    # The software launchers deliberately import these private module names;
    # the default minecraft-java[w].exe continues to use the system OpenGL
    # implementation and therefore the physical GPU driver where available.
    Copy-Item -LiteralPath (Join-Path $preloadLibraries 'glfw_mesa.dll') -Destination $payloadBin -Force
    $mesa = Join-Path $workspace 'work\compat\minecraftxp\combined-26.2-targets\opengl32.dll'
    Copy-Item -LiteralPath $mesa -Destination (Join-Path $payloadBin 'mesa3d32.dll') -Force

    # Keep the Mesa opengl32.dll in a sibling directory so it cannot shadow
    # the operating system OpenGL module used by the default hardware path.
    # Original native names also preserve XP x64 static-TLS module identity.
    Get-ChildItem -LiteralPath $payloadBin -File -Filter '*.dll' |
        Where-Object Name -notin @('glfw_mesa.dll', 'mesa3d32.dll') |
        Copy-Item -Destination $payloadSoftware -Force
    Copy-Item -LiteralPath $mesa -Destination (Join-Path $payloadSoftware 'opengl32.dll') -Force

    $manifest = Join-Path $outputRoot 'SHA256SUMS.txt'
    Get-ChildItem -LiteralPath $payload -Recurse -File | Sort-Object FullName |
        Get-FileHash -Algorithm SHA256 | ForEach-Object {
            '{0}  {1}' -f $_.Hash, $_.Path.Substring($payload.Length + 1).Replace('\', '/')
        } | Set-Content -LiteralPath $manifest -Encoding ascii

    Write-Output "WRAPPER_BUILD_PASS=JDK$major PAYLOAD=$payload"
    Write-Output "WRAPPER_MANIFEST=$manifest"
}
