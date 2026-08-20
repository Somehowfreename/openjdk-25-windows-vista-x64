Unicode true
ManifestSupportedOS none
XPStyle on
RequestExecutionLevel admin
CRCCheck force
SetCompressor /SOLID lzma
SetDatablockOptimize on
SetDateSave on
ShowInstDetails show
ShowUninstDetails show

!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "WinVer.nsh"
!include "x64.nsh"
!include "FileFunc.nsh"

!ifndef PRODUCT_ID
  !error "PRODUCT_ID is required"
!endif
!ifndef PRODUCT_NAME
  !error "PRODUCT_NAME is required"
!endif
!ifndef DISPLAY_VERSION
  !error "DISPLAY_VERSION is required"
!endif
!ifndef FILE_VERSION
  !error "FILE_VERSION is required"
!endif
!ifndef TARGET_OS
  !error "TARGET_OS is required"
!endif
!ifndef OS_LABEL
  !error "OS_LABEL is required"
!endif
!ifndef INSTALL_FOLDER
  !error "INSTALL_FOLDER is required"
!endif
!ifndef RUNTIME_DIR
  !error "RUNTIME_DIR is required"
!endif
!ifndef OUTPUT_FILE
  !error "OUTPUT_FILE is required"
!endif
!ifndef LICENSE_FILE
  !error "LICENSE_FILE is required"
!endif
!ifndef ADDITIONAL_LICENSE_FILE
  !error "ADDITIONAL_LICENSE_FILE is required"
!endif
!ifndef ASSEMBLY_EXCEPTION_FILE
  !error "ASSEMBLY_EXCEPTION_FILE is required"
!endif
!ifndef PAYLOAD_MANIFEST
  !error "PAYLOAD_MANIFEST is required"
!endif
!ifndef SOURCE_COMMIT
  !error "SOURCE_COMMIT is required"
!endif
!ifndef PAYLOAD_KIND
  !error "PAYLOAD_KIND is required"
!endif
!ifndef ESTIMATED_SIZE_KB
  !define ESTIMATED_SIZE_KB 0
!endif

!define COMPANY_NAME "Legacy Windows OpenJDK Community Build"
!define PRODUCT_REG_KEY "Software\LegacyOpenJDK\JDK\${PRODUCT_ID}"
!define UNINSTALL_REG_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\LegacyOpenJDK-${PRODUCT_ID}"
!define INSTALL_MARKER "LegacyOpenJDK|${PRODUCT_ID}|${SOURCE_COMMIT}"

Name "${PRODUCT_NAME}"
Caption "${PRODUCT_NAME} Setup"
OutFile "${OUTPUT_FILE}"
InstallDir "$PROGRAMFILES64\Legacy OpenJDK\${INSTALL_FOLDER}"
InstallDirRegKey HKLM "${PRODUCT_REG_KEY}" "InstallLocation"
BrandingText "Legacy Windows OpenJDK"

VIProductVersion "${FILE_VERSION}"
VIAddVersionKey /LANG=1033 "ProductName" "${PRODUCT_NAME}"
VIAddVersionKey /LANG=1033 "ProductVersion" "${DISPLAY_VERSION}"
VIAddVersionKey /LANG=1033 "FileDescription" "${PRODUCT_NAME} installer"
VIAddVersionKey /LANG=1033 "FileVersion" "${DISPLAY_VERSION}"
VIAddVersionKey /LANG=1033 "CompanyName" "${COMPANY_NAME}"
VIAddVersionKey /LANG=1033 "LegalCopyright" "OpenJDK contributors; GPLv2 with Classpath Exception"

!define MUI_ABORTWARNING
!define MUI_ICON "${NSISDIR}\Contrib\Graphics\Icons\orange-install.ico"
!define MUI_UNICON "${NSISDIR}\Contrib\Graphics\Icons\orange-uninstall.ico"
!define MUI_FINISHPAGE_NOAUTOCLOSE
!define MUI_UNFINISHPAGE_NOAUTOCLOSE

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "${LICENSE_FILE}"
!define MUI_PAGE_CUSTOMFUNCTION_PRE PrepareInstallDirectory
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH

!insertmacro MUI_LANGUAGE "English"

Function PrepareInstallDirectory
  StrCmp $INSTDIR "" 0 done
  SetRegView 64
  ReadRegStr $0 HKLM "${PRODUCT_REG_KEY}" "InstallLocation"
  StrCmp $0 "" use_default
    StrCpy $INSTDIR $0
    Goto done
  use_default:
    StrCpy $INSTDIR "$PROGRAMFILES64\Legacy OpenJDK\${INSTALL_FOLDER}"
  done:
FunctionEnd

Function .onInit
  SetRegView 64
  ${IfNot} ${IsNativeAMD64}
    MessageBox MB_ICONSTOP|MB_OK "This package requires an x86-64 edition of Windows."
    Abort
  ${EndIf}

  !if "${TARGET_OS}" == "xp"
    ; WinVer intentionally normalizes XP Professional x64 (NT 5.2 workstation)
    ; to the XP product family, rather than the Server 2003 family.
    ${IfNot} ${IsWinXP}
      MessageBox MB_ICONSTOP|MB_OK "This package is only for Windows XP Professional x64 Edition SP2 (NT 5.2 workstation)."
      Abort
    ${EndIf}
    ${If} ${IsServerOS}
      MessageBox MB_ICONSTOP|MB_OK "Windows Server 2003 is not a certified target. Use this package only on Windows XP Professional x64 Edition SP2."
      Abort
    ${EndIf}
    ${IfNot} ${AtLeastServicePack} 2
      MessageBox MB_ICONSTOP|MB_OK "Windows XP Professional x64 Edition Service Pack 2 is required."
      Abort
    ${EndIf}
  !else if "${TARGET_OS}" == "vista"
    ${IfNot} ${IsWinVista}
      MessageBox MB_ICONSTOP|MB_OK "This package is only for Windows Vista SP2 x64."
      Abort
    ${EndIf}
    ${IfNot} ${AtLeastServicePack} 2
      MessageBox MB_ICONSTOP|MB_OK "Windows Vista Service Pack 2 is required."
      Abort
    ${EndIf}
  !else if "${TARGET_OS}" == "win7"
    ${IfNot} ${IsWin7}
      MessageBox MB_ICONSTOP|MB_OK "This package is only for Windows 7 SP1 x64."
      Abort
    ${EndIf}
    ${IfNot} ${AtLeastServicePack} 1
      MessageBox MB_ICONSTOP|MB_OK "Windows 7 Service Pack 1 is required."
      Abort
    ${EndIf}
  !else
    !error "Unknown TARGET_OS"
  !endif

  Call PrepareInstallDirectory
FunctionEnd

Function ValidateInstallDirectory
  Call PrepareInstallDirectory
  StrCpy $1 $INSTDIR
  ; NSIS's GetFullPathName returns an empty string for a not-yet-created
  ; destination on XP. The Win32 API canonicalizes it without requiring it
  ; to exist, including collapsing relative components such as "..".
  System::Call 'kernel32::GetFullPathName(t r1, i ${NSIS_MAX_STRLEN}, t.r2, p 0)i.r3'
  StrCmp $3 0 invalid
  StrCpy $INSTDIR $2
  ${GetRoot} "$INSTDIR" $0
  StrCmp $INSTDIR $0 invalid
  StrCmp $INSTDIR "$WINDIR" invalid
  StrCmp $INSTDIR "$SYSDIR" invalid
  StrCmp $INSTDIR "$PROGRAMFILES64" invalid
  StrCmp $INSTDIR "$PROGRAMFILES32" invalid
  Return

  invalid:
    MessageBox MB_ICONSTOP|MB_OK "Choose a dedicated subdirectory for this JDK. A drive root, Windows directory, system directory, or Program Files root is not a safe installation target."
    Abort
FunctionEnd

Section "OpenJDK" SecOpenJDK
  SectionIn RO
  Call ValidateInstallDirectory
  SetRegView 64
  SetShellVarContext all
  SetOverwrite on
  SetOutPath "$INSTDIR"

  File /r "${RUNTIME_DIR}\*"
  File /oname=LICENSE "${LICENSE_FILE}"
  File /oname=ADDITIONAL_LICENSE_INFO "${ADDITIONAL_LICENSE_FILE}"
  File /oname=ASSEMBLY_EXCEPTION "${ASSEMBLY_EXCEPTION_FILE}"
  File /oname=PAYLOAD-SHA256SUMS.txt "${PAYLOAD_MANIFEST}"

  FileOpen $0 "$INSTDIR\.legacy-openjdk-install" w
  FileWrite $0 "${INSTALL_MARKER}"
  FileClose $0

  FileOpen $0 "$INSTDIR\LEGACY-WINDOWS-PORT.txt" w
  FileWrite $0 "${PRODUCT_NAME}$\r$\n"
  FileWrite $0 "Target operating system: ${OS_LABEL}$\r$\n"
  FileWrite $0 "Payload: ${PAYLOAD_KIND}$\r$\n"
  FileWrite $0 "Source commit: ${SOURCE_COMMIT}$\r$\n"
  FileWrite $0 "Compatibility code is application-local and does not patch Windows system files.$\r$\n"
  FileWrite $0 "No PATH or JAVA_HOME value is changed. Select $INSTDIR\bin\javaw.exe in your launcher.$\r$\n"
  FileClose $0

  WriteUninstaller "$INSTDIR\uninstall.exe"

  WriteRegStr HKLM "${PRODUCT_REG_KEY}" "DisplayName" "${PRODUCT_NAME}"
  WriteRegStr HKLM "${PRODUCT_REG_KEY}" "DisplayVersion" "${DISPLAY_VERSION}"
  WriteRegStr HKLM "${PRODUCT_REG_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${PRODUCT_REG_KEY}" "JavaHome" "$INSTDIR"
  WriteRegStr HKLM "${PRODUCT_REG_KEY}" "TargetOS" "${OS_LABEL}"
  WriteRegStr HKLM "${PRODUCT_REG_KEY}" "SourceCommit" "${SOURCE_COMMIT}"

  WriteRegStr HKLM "${UNINSTALL_REG_KEY}" "DisplayName" "${PRODUCT_NAME}"
  WriteRegStr HKLM "${UNINSTALL_REG_KEY}" "DisplayVersion" "${DISPLAY_VERSION}"
  WriteRegStr HKLM "${UNINSTALL_REG_KEY}" "Publisher" "${COMPANY_NAME}"
  WriteRegStr HKLM "${UNINSTALL_REG_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${UNINSTALL_REG_KEY}" "DisplayIcon" "$INSTDIR\bin\java.exe"
  WriteRegStr HKLM "${UNINSTALL_REG_KEY}" "UninstallString" "$\"$INSTDIR\uninstall.exe$\""
  WriteRegStr HKLM "${UNINSTALL_REG_KEY}" "QuietUninstallString" "$\"$INSTDIR\uninstall.exe$\" /S"
  WriteRegDWORD HKLM "${UNINSTALL_REG_KEY}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINSTALL_REG_KEY}" "NoRepair" 1
  WriteRegDWORD HKLM "${UNINSTALL_REG_KEY}" "EstimatedSize" ${ESTIMATED_SIZE_KB}
SectionEnd

Function un.onInit
  SetRegView 64
  ReadRegStr $0 HKLM "${PRODUCT_REG_KEY}" "InstallLocation"
  !ifdef INSTALLER_DEBUG
    MessageBox MB_OK "REGISTRY=[$0]$\r$\nINSTDIR=[$INSTDIR]$\r$\nEXEDIR=[$EXEDIR]"
  !endif
  StrCmp $0 "" invalid
  StrCpy $3 $INSTDIR
  ; XP starts the second-stage uninstaller with an 8.3 $INSTDIR even though
  ; the registered path is long. Expand both existing paths before comparing.
  System::Call 'kernel32::GetLongPathName(t r0, t.r4, i ${NSIS_MAX_STRLEN})i.r5'
  StrCmp $5 0 invalid
  System::Call 'kernel32::GetLongPathName(t r3, t.r6, i ${NSIS_MAX_STRLEN})i.r7'
  StrCmp $7 0 invalid
  StrCmp $4 $6 paths_match invalid

  paths_match:
  StrCpy $INSTDIR $6
  ${GetRoot} "$INSTDIR" $1
  StrCmp $INSTDIR $1 invalid
  StrCmp $INSTDIR "$WINDIR" invalid
  StrCmp $INSTDIR "$SYSDIR" invalid
  StrCmp $INSTDIR "$PROGRAMFILES64" invalid
  StrCmp $INSTDIR "$PROGRAMFILES32" invalid
  IfFileExists "$INSTDIR\.legacy-openjdk-install" marker_exists invalid

  marker_exists:
  FileOpen $1 "$INSTDIR\.legacy-openjdk-install" r
  FileRead $1 $2
  FileClose $1
  StrCmp $2 "${INSTALL_MARKER}" valid invalid

  invalid:
    MessageBox MB_ICONSTOP|MB_OK "The installation marker is missing or invalid, or the target is unsafe. No files were removed."
    Abort

  valid:
FunctionEnd

Section "Uninstall"
  SetRegView 64
  DeleteRegKey HKLM "${UNINSTALL_REG_KEY}"
  DeleteRegKey HKLM "${PRODUCT_REG_KEY}"
  RMDir /r "$INSTDIR"
SectionEnd
