[CmdletBinding()]
param(
    [ValidateSet(17, 21, 25)]
    [int[]] $JavaMajor = @(25),

    [ValidatePattern('^r[0-9]+$')]
    [string] $OutputRevision = 'r41',

    [ValidatePattern('^r[0-9]+$')]
    [string] $LwjglCompatRevision = 'r3',

    [ValidatePattern('^r[0-9]+$')]
    [string] $SdlCompatRevision = 'r1',

    [ValidateSet('xp', 'vista')]
    [string] $TargetOs = 'vista',

    [string] $WorkspaceRoot
)

$ErrorActionPreference = 'Stop'
$workspace = if ($WorkspaceRoot) { (Resolve-Path -LiteralPath $WorkspaceRoot).Path } else { (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..\..\..')).Path }
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
$openAlXpConfig = Join-Path $PSScriptRoot 'alsoft-xp.ini'
$lwjglCompatPayload = Join-Path $workspace "work\release-builds\lwjgl-memoryutil-compat-$LwjglCompatRevision\payload"
$sdlCompatPayload = Join-Path $workspace "work\release-builds\sdl3-isolated-compat-$SdlCompatRevision\payload"
$minecraft120NativeSource = Join-Path $workspace 'work\minecraft\official\versions\1.20.1\natives-windows-x64-xp-r2'
$minecraft120JnaJar = Join-Path $workspace 'work\minecraft\official\libraries\net\java\dev\jna\jna\5.12.1\jna-5.12.1.jar'
$minecraft1202NativeSource = Join-Path $workspace 'work\minecraft\official\versions\1.20.2\natives-windows-x64-xp-r1'
$minecraft1202JnaJar = Join-Path $workspace 'work\minecraft\official\libraries\net\java\dev\jna\jna\5.13.0\jna-5.13.0.jar'
$minecraft121NativeSource = Join-Path $workspace 'work\minecraft\official\versions\1.21.1\natives-windows-x64-xp-r3'
$minecraft12111JnaJar = Join-Path $workspace 'work\minecraft\official\libraries\net\java\dev\jna\jna\5.17.0\jna-5.17.0.jar'
$mesaCompatibility = Join-Path $workspace 'work\compat\minecraftxp\combined-26.2-targets\opengl32.dll'

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

function Expand-ZipEntryStrict {
    param(
        [Parameter(Mandatory = $true)][string] $ArchivePath,
        [Parameter(Mandatory = $true)][string] $EntryName,
        [Parameter(Mandatory = $true)][string] $DestinationPath
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        $entry = $archive.GetEntry($EntryName)
        if ($null -eq $entry) {
            throw "Archive entry is missing: $EntryName in $ArchivePath"
        }
        [IO.Compression.ZipFileExtensions]::ExtractToFile(
            $entry, $DestinationPath, $true)
    } finally {
        $archive.Dispose()
    }
}

foreach ($major in $JavaMajor) {
    $definition = $definitions[$major]
    $jdkSource = Join-Path $workspace $definition.Source
    $build = Join-Path $jdkSource "build\$($definition.Configuration)"
    $jdkImage = Join-Path $build 'images\jdk'
    $generatedInclude = Join-Path $build 'support\modules_include\java.base'
    $targetSuffix = if ($TargetOs -eq 'vista') { '-vista' } else { '' }
    $outputRoot = Join-Path $workspace "work\release-builds\minecraft-wrapper-jdk$major$targetSuffix-$OutputRevision"
    $payload = Join-Path $outputRoot 'payload'
    $payloadBin = Join-Path $payload 'bin'
    $payloadVmTests = Join-Path $payloadBin 'vmtests'
    $payloadPrivate = Join-Path $payload 'lib\legacy-windows\internal\launcher\executables'
    $payloadSoftware = Join-Path $payloadPrivate 'software'
    $payload120Private = Join-Path $payloadPrivate '1.20'
    $payload120Software = Join-Path $payload120Private 'software'
    $payload1202Private = Join-Path $payloadPrivate '1.20.2'
    $payload1202Software = Join-Path $payload1202Private 'software'
    $payload121Private = Join-Path $payloadPrivate '1.21'
    $payload121Software = Join-Path $payload121Private 'software'
    $payload12111Private = Join-Path $payloadPrivate '1.21.11'
    $payload12111Software = Join-Path $payload12111Private 'software'
    $payloadNative = Join-Path $payload "minecraft\$($definition.MinecraftVersion)\natives-xp-x64"
    $payload120Native = Join-Path $payload 'minecraft\1.20\natives-xp-x64'
    $payload1202Native = Join-Path $payload 'minecraft\1.20.2\natives-xp-x64'
    $payload121Native = Join-Path $payload 'minecraft\1.21\natives-xp-x64'
    $payload12111Native = Join-Path $payload 'minecraft\1.21.11\natives-xp-x64'
    $buildObjects = Join-Path $outputRoot 'objects'

    if (Test-Path -LiteralPath $outputRoot) {
        throw "Refusing to replace preserved wrapper build: $outputRoot"
    }
    foreach ($directory in @(
        $payloadBin, $payloadVmTests, $payloadPrivate, $payloadSoftware,
        $payloadNative, $buildObjects
    )) {
        [IO.Directory]::CreateDirectory($directory) | Out-Null
    }
    if ($major -eq 25) {
        foreach ($directory in @(
            $payload120Private, $payload120Software, $payload120Native,
            $payload1202Private, $payload1202Software, $payload1202Native,
            $payload121Private, $payload121Software, $payload121Native,
            $payload12111Private, $payload12111Software, $payload12111Native
        )) {
            [IO.Directory]::CreateDirectory($directory) | Out-Null
        }
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
        $requiredInputs += $openAlXpConfig
        $requiredInputs += $minecraft120NativeSource
        $requiredInputs += $minecraft120JnaJar
        $requiredInputs += $minecraft1202NativeSource
        $requiredInputs += $minecraft1202JnaJar
        $requiredInputs += $minecraft121NativeSource
        $requiredInputs += $minecraft12111JnaJar
        $requiredInputs += $mesaCompatibility
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
    $targetOptionsDefines = @()
    if ($TargetOs -eq 'vista') {
        $targetOptionsDefines += '/DMINECRAFT_TARGET_VISTA'
    }

    $optionsObject = Join-Path $buildObjects 'minecraft-wrapper-options.obj'
    & $cl /nologo /c /TP /O2 /MT /W4 /EHsc /GS- /D_CRT_SECURE_NO_WARNINGS `
        @targetOptionsDefines "/DMINECRAFT_JAVA_MAJOR=$major" @includes "/Fo$optionsObject" $source
    if ($LASTEXITCODE -ne 0) { throw "Compiling Java $major wrapper options failed." }
    $softwareOptionsObject = Join-Path $buildObjects 'minecraft-wrapper-options-software.obj'
    & $cl /nologo /c /TP /O2 /MT /W4 /EHsc /GS- /D_CRT_SECURE_NO_WARNINGS `
        /DMINECRAFT_SOFTWARE_ORIGINAL_MODULES @targetOptionsDefines `
        "/DMINECRAFT_JAVA_MAJOR=$major" @includes "/Fo$softwareOptionsObject" $source
    if ($LASTEXITCODE -ne 0) { throw "Compiling Java $major isolated software options failed." }
    if ($major -eq 25) {
        $options121Object = Join-Path $buildObjects 'minecraft-wrapper-options-121.obj'
        & $cl /nologo /c /TP /O2 /MT /W4 /EHsc /GS- /D_CRT_SECURE_NO_WARNINGS `
            /DMINECRAFT_MINIMAL_PRELOAD @targetOptionsDefines "/DMINECRAFT_JAVA_MAJOR=$major" `
            @includes "/Fo$options121Object" $source
        if ($LASTEXITCODE -ne 0) { throw 'Compiling Java 25 Minecraft 1.21 options failed.' }
        $software121OptionsObject = Join-Path $buildObjects 'minecraft-wrapper-options-121-software.obj'
        & $cl /nologo /c /TP /O2 /MT /W4 /EHsc /GS- /D_CRT_SECURE_NO_WARNINGS `
            /DMINECRAFT_MINIMAL_PRELOAD /DMINECRAFT_SOFTWARE_ORIGINAL_MODULES @targetOptionsDefines `
            "/DMINECRAFT_JAVA_MAJOR=$major" @includes `
            "/Fo$software121OptionsObject" $source
        if ($LASTEXITCODE -ne 0) { throw 'Compiling Java 25 Minecraft 1.21 software options failed.' }
    }

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
        [pscustomobject]@{ Directory=$payloadPrivate; Name='minecraft-java-runtime.exe'; Kind='console'; Imports=$preloadImports; Options=$optionsObject },
        [pscustomobject]@{ Directory=$payloadPrivate; Name='minecraft-javaw-runtime.exe'; Kind='windows'; Imports=$preloadImports; Options=$optionsObject },
        [pscustomobject]@{ Directory=$payloadSoftware; Name='minecraft-java-software.exe'; Kind='console'; Imports=$preloadImports; Options=$softwareOptionsObject },
        [pscustomobject]@{ Directory=$payloadSoftware; Name='minecraft-javaw-software.exe'; Kind='windows'; Imports=$preloadImports; Options=$softwareOptionsObject }
    )
    if ($major -eq 25) {
        $minimalPreloadImports = @('OpenAL.lib', 'glfw.lib', 'opengl32.lib')
        $launchers += @(
            [pscustomobject]@{ Directory=$payload120Private; Name='minecraft-java-runtime.exe'; Kind='console'; Imports=$minimalPreloadImports; Options=$options121Object },
            [pscustomobject]@{ Directory=$payload120Private; Name='minecraft-javaw-runtime.exe'; Kind='windows'; Imports=$minimalPreloadImports; Options=$options121Object },
            [pscustomobject]@{ Directory=$payload120Software; Name='minecraft-java-software.exe'; Kind='console'; Imports=$minimalPreloadImports; Options=$software121OptionsObject },
            [pscustomobject]@{ Directory=$payload120Software; Name='minecraft-javaw-software.exe'; Kind='windows'; Imports=$minimalPreloadImports; Options=$software121OptionsObject },
            [pscustomobject]@{ Directory=$payload1202Private; Name='minecraft-java-runtime.exe'; Kind='console'; Imports=$minimalPreloadImports; Options=$options121Object },
            [pscustomobject]@{ Directory=$payload1202Private; Name='minecraft-javaw-runtime.exe'; Kind='windows'; Imports=$minimalPreloadImports; Options=$options121Object },
            [pscustomobject]@{ Directory=$payload1202Software; Name='minecraft-java-software.exe'; Kind='console'; Imports=$minimalPreloadImports; Options=$software121OptionsObject },
            [pscustomobject]@{ Directory=$payload1202Software; Name='minecraft-javaw-software.exe'; Kind='windows'; Imports=$minimalPreloadImports; Options=$software121OptionsObject },
            [pscustomobject]@{ Directory=$payload121Private; Name='minecraft-java-runtime.exe'; Kind='console'; Imports=$minimalPreloadImports; Options=$options121Object },
            [pscustomobject]@{ Directory=$payload121Private; Name='minecraft-javaw-runtime.exe'; Kind='windows'; Imports=$minimalPreloadImports; Options=$options121Object },
            [pscustomobject]@{ Directory=$payload121Software; Name='minecraft-java-software.exe'; Kind='console'; Imports=$minimalPreloadImports; Options=$software121OptionsObject },
            [pscustomobject]@{ Directory=$payload121Software; Name='minecraft-javaw-software.exe'; Kind='windows'; Imports=$minimalPreloadImports; Options=$software121OptionsObject },
            [pscustomobject]@{ Directory=$payload12111Private; Name='minecraft-java-runtime.exe'; Kind='console'; Imports=$minimalPreloadImports; Options=$options121Object },
            [pscustomobject]@{ Directory=$payload12111Private; Name='minecraft-javaw-runtime.exe'; Kind='windows'; Imports=$minimalPreloadImports; Options=$options121Object },
            [pscustomobject]@{ Directory=$payload12111Software; Name='minecraft-java-software.exe'; Kind='console'; Imports=$minimalPreloadImports; Options=$software121OptionsObject },
            [pscustomobject]@{ Directory=$payload12111Software; Name='minecraft-javaw-software.exe'; Kind='windows'; Imports=$minimalPreloadImports; Options=$software121OptionsObject }
        )
    }
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

    # Stable public dispatchers set the XP OpenAL configuration before Windows
    # loads the real Java/OpenAL process. Runtime launchers stay in the private
    # executable tree, and software runtimes remain isolated below it.
    foreach ($dispatcher in @(
        [pscustomobject]@{ Directory=$payloadBin; Name='minecraft-java.exe'; Kind='console'; Defines=@('/DMINECRAFT_DISPATCH_HARDWARE', '/DMINECRAFT_LAUNCHER_MULTIMC') },
        [pscustomobject]@{ Directory=$payloadBin; Name='minecraft-javaw.exe'; Kind='windows'; Defines=@('/DMINECRAFT_DISPATCH_HARDWARE', '/DMINECRAFT_DISPATCH_WINDOWS', '/DMINECRAFT_LAUNCHER_MULTIMC') },
        [pscustomobject]@{ Directory=$payloadBin; Name='minecraft-javaw-olauncher.exe'; Kind='windows'; Defines=@('/DMINECRAFT_DISPATCH_HARDWARE', '/DMINECRAFT_DISPATCH_WINDOWS', '/DMINECRAFT_LAUNCHER_OLAUNCHER') },
        [pscustomobject]@{ Directory=$payloadVmTests; Name='minecraft-java-software-rendering-multimc.exe'; Kind='console'; Defines=@('/DMINECRAFT_LAUNCHER_MULTIMC') },
        [pscustomobject]@{ Directory=$payloadVmTests; Name='minecraft-javaw-software-rendering-multimc.exe'; Kind='windows'; Defines=@('/DMINECRAFT_DISPATCH_WINDOWS', '/DMINECRAFT_LAUNCHER_MULTIMC') },
        [pscustomobject]@{ Directory=$payloadVmTests; Name='minecraft-javaw-software-rendering-olauncher.exe'; Kind='windows'; Defines=@('/DMINECRAFT_DISPATCH_WINDOWS', '/DMINECRAFT_LAUNCHER_OLAUNCHER') }
    )) {
        $dispatcherDefines = @($dispatcher.Defines)
        if ($TargetOs -eq 'vista') {
            $dispatcherDefines += '/DMINECRAFT_VISTA_APPLICATION_COMPAT'
        }
        $object = Join-Path $buildObjects ("dispatcher-$($dispatcher.Name).obj")
        & $cl /nologo /c /TC /O2 /MT /W4 /GS- /D_CRT_SECURE_NO_WARNINGS `
            @dispatcherDefines @dispatcherIncludes "/Fo$object" $dispatcherSource
        if ($LASTEXITCODE -ne 0) { throw "Compiling Java $major $($dispatcher.Name) dispatcher failed." }
        $output = Join-Path $dispatcher.Directory $dispatcher.Name
        $subsystem = if ($dispatcher.Kind -eq 'windows') { '/SUBSYSTEM:WINDOWS,5.02' } else { '/SUBSYSTEM:CONSOLE,5.02' }
        & $link /nologo /machine:x64 $subsystem /osversion:5.02 "/out:$output" `
            $object @commonLibraries user32.lib /OPT:REF /OPT:ICF
        if ($LASTEXITCODE -ne 0) { throw "Linking Java $major $($dispatcher.Name) dispatcher failed." }
    }

    # Preserve the original v1.0.0 entry point and add an unmistakable named
    # MultiMC copy. These are physical, byte-identical files rather than links
    # or separately compiled binaries, so either path has exactly the same
    # behavior and hash.
    Copy-Item -LiteralPath (Join-Path $payloadBin 'minecraft-javaw.exe') `
        -Destination (Join-Path $payloadBin 'minecraft-javaw-multimc.exe')

    # Redirect any newly introduced Kernel32 imports through the same
    # application-local compatibility layer used by the JDK image.
    & $patcher -ImageRoot $payloadBin -LlvmReadObj $reader `
        -TargetWindowsMajor 5 -TargetWindowsMinor 2 `
        -ImportMappings @{ 'KERNEL32.dll' = 'JDKXP.dll' }
    & $patcher -ImageRoot $payloadPrivate -LlvmReadObj $reader `
        -TargetWindowsMajor 5 -TargetWindowsMinor 2 `
        -ImportMappings @{ 'KERNEL32.dll' = 'JDKXP.dll' }
    & $patcher -ImageRoot $payloadSoftware -LlvmReadObj $reader `
        -TargetWindowsMajor 5 -TargetWindowsMinor 2 `
        -ImportMappings @{ 'KERNEL32.dll' = 'JDKXP.dll' }
    if ($major -eq 25) {
        & $patcher -ImageRoot $payload120Private -LlvmReadObj $reader `
            -TargetWindowsMajor 5 -TargetWindowsMinor 2 `
            -ImportMappings @{ 'KERNEL32.dll' = 'JDKXP.dll' }
        & $patcher -ImageRoot $payload120Software -LlvmReadObj $reader `
            -TargetWindowsMajor 5 -TargetWindowsMinor 2 `
            -ImportMappings @{ 'KERNEL32.dll' = 'JDKXP.dll' }
        & $patcher -ImageRoot $payload1202Private -LlvmReadObj $reader `
            -TargetWindowsMajor 5 -TargetWindowsMinor 2 `
            -ImportMappings @{ 'KERNEL32.dll' = 'JDKXP.dll' }
        & $patcher -ImageRoot $payload1202Software -LlvmReadObj $reader `
            -TargetWindowsMajor 5 -TargetWindowsMinor 2 `
            -ImportMappings @{ 'KERNEL32.dll' = 'JDKXP.dll' }
        & $patcher -ImageRoot $payload121Private -LlvmReadObj $reader `
            -TargetWindowsMajor 5 -TargetWindowsMinor 2 `
            -ImportMappings @{ 'KERNEL32.dll' = 'JDKXP.dll' }
        & $patcher -ImageRoot $payload121Software -LlvmReadObj $reader `
            -TargetWindowsMajor 5 -TargetWindowsMinor 2 `
            -ImportMappings @{ 'KERNEL32.dll' = 'JDKXP.dll' }
        & $patcher -ImageRoot $payload12111Private -LlvmReadObj $reader `
            -TargetWindowsMajor 5 -TargetWindowsMinor 2 `
            -ImportMappings @{ 'KERNEL32.dll' = 'JDKXP.dll' }
        & $patcher -ImageRoot $payload12111Software -LlvmReadObj $reader `
            -TargetWindowsMajor 5 -TargetWindowsMinor 2 `
            -ImportMappings @{ 'KERNEL32.dll' = 'JDKXP.dll' }
    }
    Copy-Item -LiteralPath (Join-Path $workspace $definition.EnhancedJdkXp) `
        -Destination (Join-Path $payloadBin 'JDKXP.dll')
    Copy-Item -LiteralPath (Join-Path $workspace $definition.EnhancedJdkXp) `
        -Destination (Join-Path $payloadPrivate 'JDKXP.dll')

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
        # The wrappers set process-local ALSOFT_CONF to this verified XP
        # DirectSound configuration before Minecraft opens the audio device.
        Copy-Item -LiteralPath $openAlXpConfig `
            -Destination (Join-Path $compatTarget 'alsoft-xp.ini')
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
    $mesa = $mesaCompatibility
    Copy-Item -LiteralPath $mesa -Destination (Join-Path $payloadBin 'mesa3d32.dll') -Force

    # Keep the Mesa opengl32.dll in a sibling directory so it cannot shadow
    # the operating system OpenGL module used by the default hardware path.
    # Original native names also preserve XP x64 static-TLS module identity.
    Get-ChildItem -LiteralPath $payloadBin -File -Filter '*.dll' |
        Where-Object Name -notin @('glfw_mesa.dll', 'mesa3d32.dll') |
        Copy-Item -Destination $payloadSoftware -Force
    Copy-Item -LiteralPath $mesa -Destination (Join-Path $payloadSoftware 'opengl32.dll') -Force

    # Private launchers have static imports that Windows resolves before their
    # own code runs. Keep application-local copies beside those launchers while
    # leaving the canonical runtime DLLs in bin for Java and Minecraft.
    Get-ChildItem -LiteralPath $payloadBin -File -Filter '*.dll' |
        Copy-Item -Destination $payloadPrivate -Force

    if ($major -eq 25) {
        # Minecraft 1.21 uses LWJGL 3.3.x. Keep that ABI in a separate private
        # process directory so Windows never resolves it to the already-loaded
        # LWJGL 3.4.1/3.4.2 compatibility proxy used by Minecraft 26.
        $profileSpecificNames = @(
            'freetype.dll', 'glfw.dll', 'jemalloc.dll', 'jnidispatch.dll',
            'lwjgl.dll', 'lwjgl341.dll', 'lwjgl_opengl.dll', 'lwjgl_stb.dll',
            'lwjgl_tinyfd.dll', 'lwjgl_vma.dll', 'OpenAL.dll', 'SDL3.dll',
            'SDLS.dll', 'SDLU.dll'
        )
        foreach ($profileDirectory in @(
            $payload120Private, $payload120Software,
            $payload1202Private, $payload1202Software,
            $payload121Private, $payload121Software,
            $payload12111Private, $payload12111Software
        )) {
            Get-ChildItem -LiteralPath $payloadPrivate -File -Filter '*.dll' |
                Where-Object Name -notin $profileSpecificNames |
                Copy-Item -Destination $profileDirectory -Force
        }

        # Minecraft 1.20.x uses LWJGL 3.3.1 and JNA 5.12.1. Keep both native
        # ABIs isolated from the 1.21 (LWJGL 3.3.3/JNA 5.14) and Minecraft 26
        # processes. The JNA DLL is extracted from the exact upstream JAR used
        # by the 1.20.x client classpath, avoiding a Java/native version skew.
        $minecraft120Names = @(
            'glfw.dll', 'jemalloc.dll', 'lwjgl.dll', 'lwjgl_opengl.dll',
            'lwjgl_stb.dll', 'lwjgl_tinyfd.dll', 'OpenAL.dll'
        )
        foreach ($name in $minecraft120Names) {
            Copy-Item -LiteralPath (Join-Path $minecraft120NativeSource $name) `
                -Destination (Join-Path $payload120Private $name) -Force
            Copy-Item -LiteralPath (Join-Path $minecraft120NativeSource $name) `
                -Destination (Join-Path $payload120Software $name) -Force
        }
        $minecraft120Jna = Join-Path $buildObjects 'jnidispatch-5.12.1.dll'
        Expand-ZipEntryStrict -ArchivePath $minecraft120JnaJar `
            -EntryName 'com/sun/jna/win32-x86-64/jnidispatch.dll' `
            -DestinationPath $minecraft120Jna
        Copy-Item -LiteralPath $minecraft120Jna `
            -Destination (Join-Path $payload120Private 'jnidispatch.dll') -Force
        Copy-Item -LiteralPath $minecraft120Jna `
            -Destination (Join-Path $payload120Software 'jnidispatch.dll') -Force
        Copy-Item -LiteralPath $mesaCompatibility `
            -Destination (Join-Path $payload120Software 'opengl32.dll') -Force

        # Minecraft 1.20.2 moves to LWJGL 3.3.2 and JNA 5.13.0. It is a
        # distinct native ABI even though its Java major and release family
        # match 1.20/1.20.1.
        $minecraft1202Names = @(
            'glfw.dll', 'jemalloc.dll', 'lwjgl.dll', 'lwjgl_opengl.dll',
            'lwjgl_stb.dll', 'lwjgl_tinyfd.dll', 'OpenAL.dll'
        )
        foreach ($name in $minecraft1202Names) {
            Copy-Item -LiteralPath (Join-Path $minecraft1202NativeSource $name) `
                -Destination (Join-Path $payload1202Private $name) -Force
            Copy-Item -LiteralPath (Join-Path $minecraft1202NativeSource $name) `
                -Destination (Join-Path $payload1202Software $name) -Force
        }
        $minecraft1202Jna = Join-Path $buildObjects 'jnidispatch-5.13.0.dll'
        Expand-ZipEntryStrict -ArchivePath $minecraft1202JnaJar `
            -EntryName 'com/sun/jna/win32-x86-64/jnidispatch.dll' `
            -DestinationPath $minecraft1202Jna
        Copy-Item -LiteralPath $minecraft1202Jna `
            -Destination (Join-Path $payload1202Private 'jnidispatch.dll') -Force
        Copy-Item -LiteralPath $minecraft1202Jna `
            -Destination (Join-Path $payload1202Software 'jnidispatch.dll') -Force
        Copy-Item -LiteralPath $mesaCompatibility `
            -Destination (Join-Path $payload1202Software 'opengl32.dll') -Force

        $minecraft121Names = @(
            'glfw.dll', 'jemalloc.dll', 'jnidispatch.dll', 'lwjgl.dll',
            'lwjgl_opengl.dll', 'lwjgl_stb.dll', 'lwjgl_tinyfd.dll',
            'OpenAL.dll'
        )
        foreach ($name in $minecraft121Names) {
            Copy-Item -LiteralPath (Join-Path $minecraft121NativeSource $name) `
                -Destination (Join-Path $payload121Private $name) -Force
            Copy-Item -LiteralPath (Join-Path $minecraft121NativeSource $name) `
                -Destination (Join-Path $payload121Software $name) -Force
        }
        Copy-Item -LiteralPath $mesaCompatibility `
            -Destination (Join-Path $payload121Software 'opengl32.dll') -Force
        Copy-Item -LiteralPath (Join-Path $minecraft121NativeSource 'freetype.dll') `
            -Destination (Join-Path $payload121Native 'freetype.dll') -Force

        # Minecraft 1.21.11 retains LWJGL 3.3.3 but moves to JNA 5.17.0.
        # Keep that JNA ABI isolated from the 5.14.0 runtime used by 1.21 and
        # 1.21.1 while reusing the byte-identical LWJGL 3.3.3 modules.
        foreach ($name in @(
            'glfw.dll', 'jemalloc.dll', 'lwjgl.dll', 'lwjgl_opengl.dll',
            'lwjgl_stb.dll', 'lwjgl_tinyfd.dll', 'OpenAL.dll'
        )) {
            Copy-Item -LiteralPath (Join-Path $minecraft121NativeSource $name) `
                -Destination (Join-Path $payload12111Private $name) -Force
            Copy-Item -LiteralPath (Join-Path $minecraft121NativeSource $name) `
                -Destination (Join-Path $payload12111Software $name) -Force
        }
        $minecraft12111Jna = Join-Path $buildObjects 'jnidispatch-5.17.0.dll'
        Expand-ZipEntryStrict -ArchivePath $minecraft12111JnaJar `
            -EntryName 'com/sun/jna/win32-x86-64/jnidispatch.dll' `
            -DestinationPath $minecraft12111Jna
        Copy-Item -LiteralPath $minecraft12111Jna `
            -Destination (Join-Path $payload12111Private 'jnidispatch.dll') -Force
        Copy-Item -LiteralPath $minecraft12111Jna `
            -Destination (Join-Path $payload12111Software 'jnidispatch.dll') -Force
        Copy-Item -LiteralPath $mesaCompatibility `
            -Destination (Join-Path $payload12111Software 'opengl32.dll') -Force
        Copy-Item -LiteralPath (Join-Path $minecraft121NativeSource 'freetype.dll') `
            -Destination (Join-Path $payload12111Native 'freetype.dll') -Force

        # Re-run image normalization after all profile-specific native DLLs
        # have been copied. This covers the exact JNA binaries extracted above
        # as well as the compiled private launchers.
        foreach ($profileImageRoot in @(
            $payload120Private, $payload120Software,
            $payload1202Private, $payload1202Software,
            $payload121Private, $payload121Software,
            $payload12111Private, $payload12111Software
        )) {
            & $patcher -ImageRoot $profileImageRoot -LlvmReadObj $reader `
                -TargetWindowsMajor 5 -TargetWindowsMinor 2 `
                -ImportMappings @{ 'KERNEL32.dll' = 'JDKXP.dll' }
        }
    }

    $manifest = Join-Path $outputRoot 'SHA256SUMS.txt'
    Get-ChildItem -LiteralPath $payload -Recurse -File | Sort-Object FullName |
        Get-FileHash -Algorithm SHA256 | ForEach-Object {
            '{0}  {1}' -f $_.Hash, $_.Path.Substring($payload.Length + 1).Replace('\', '/')
        } | Set-Content -LiteralPath $manifest -Encoding ascii

    Write-Output "WRAPPER_BUILD_PASS=JDK$major PAYLOAD=$payload"
    Write-Output "WRAPPER_MANIFEST=$manifest"
}
