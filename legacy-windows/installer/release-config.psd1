@{
    SourceCommit = 'b0f07b6eb7c8d66771d81e8c41dca0173d50b9d2'
    Packages = @(
        @{
            Id = 'jdk25-xp-x64'
            Name = 'OpenJDK 25.0.4 for Windows XP x64'
            Display = '25.0.4-internal-xp-x64-certified-r1'
            FileVersion = '25.0.4.1'
            Target = 'xp'
            Os = 'Windows XP Professional x64 Edition SP2'
            Folder = 'jdk-25.0.4-xp-x64'
            Payload = 'OpenJDK source backport, XP-certified image'
            Output = 'OpenJDK25U-jdk_x64_windows-xp_25.0.4-certified-r1.exe'
        }
        @{
            Id = 'jdk25-vista-x64'
            Name = 'OpenJDK 25.0.4 for Windows Vista x64'
            Display = '25.0.4-internal-vista-x64-certified-r1'
            FileVersion = '25.0.4.2'
            Target = 'vista'
            Os = 'Windows Vista SP2 x64'
            Folder = 'jdk-25.0.4-vista-x64'
            Payload = 'OpenJDK source backport, Vista-certified image'
            Output = 'OpenJDK25U-jdk_x64_windows-vista_25.0.4-certified-r1.exe'
        }
        @{
            Id = 'jdk25-win7-x64'
            Name = 'Eclipse Temurin OpenJDK 25.0.4 for Windows 7 x64'
            Display = '25.0.4+7-LTS'
            FileVersion = '25.0.4.7'
            Target = 'win7'
            Os = 'Windows 7 SP1 x64'
            Folder = 'jdk-25.0.4-win7-x64'
            Payload = 'Unmodified Eclipse Temurin 25.0.4+7'
            Output = 'OpenJDK25U-jdk_x64_windows-7_25.0.4_7-temurin.exe'
        }
    )
}
