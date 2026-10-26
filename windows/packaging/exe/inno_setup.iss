[Setup]
AppId={{APP_ID}}
AppVersion={{APP_VERSION}}
AppName={{DISPLAY_NAME}}
AppPublisher={{PUBLISHER_NAME}}
AppPublisherURL={{PUBLISHER_URL}}
AppSupportURL={{PUBLISHER_URL}}
AppUpdatesURL={{PUBLISHER_URL}}
DefaultDirName={code:GetInstallDir}
; Resolve both registry views and installation scopes before choosing a path.
UsePreviousAppDir=no
DisableDirPage=no
DisableProgramGroupPage=yes
OutputDir=.
OutputBaseFilename={{OUTPUT_BASE_FILENAME}}
Compression=lzma
SolidCompression=yes
SetupIconFile={{SETUP_ICON_FILE}}
WizardStyle=modern
PrivilegesRequired={{PRIVILEGES_REQUIRED}}
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
CloseApplications=yes
CloseApplicationsFilter=piliplus.exe,pilipili.exe
RestartApplications=no

[InstallDelete]
Type: files; Name: "{app}\piliplus.exe"
Type: files; Name: "{autoprograms}\PiliPlus.lnk"
Type: files; Name: "{autodesktop}\PiliPlus.lnk"
Type: files; Name: "{userstartup}\PiliPlus.lnk"

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce
Name: "launchAtStartup"; Description: "{cm:AutoStartProgram,{{DISPLAY_NAME}}}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{{SOURCE_DIR}}\\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; NOTE: Don't use "Flags: ignoreversion" on any shared system files

[Icons]
Name: "{autoprograms}\\{{DISPLAY_NAME}}"; Filename: "{app}\\{{EXECUTABLE_NAME}}"
Name: "{autodesktop}\\{{DISPLAY_NAME}}"; Filename: "{app}\\{{EXECUTABLE_NAME}}"; Tasks: desktopicon
Name: "{userstartup}\\{{DISPLAY_NAME}}"; Filename: "{app}\\{{EXECUTABLE_NAME}}"; WorkingDir: "{app}"; Tasks: launchAtStartup

[Registry]
Root: HKCU; Subkey: "Software\\Classes\\bilibili"; ValueType: string; ValueData: "URL:Bilibili Protocol"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\\Classes\\bilibili"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\\Classes\\bilibili\\DefaultIcon"; ValueType: string; ValueData: "{app}\\{{EXECUTABLE_NAME}},0"
Root: HKCU; Subkey: "Software\\Classes\\bilibili\\shell\\open\\command"; ValueType: string; ValueData: """{app}\\{{EXECUTABLE_NAME}}"" ""%1"""

[Run]
Filename: "{app}\\{{EXECUTABLE_NAME}}"; Description: "{cm:LaunchProgram,{{DISPLAY_NAME}}}"; Flags: runascurrentuser nowait postinstall skipifsilent

[Code]
var
  PreviousDirChecked: Boolean;
  PreviousDir: String;

function RegisteredInstallDir(Root: Integer; const Key: String): String;
var
  Candidate: String;
begin
  Result := '';
  if not RegQueryStringValue(Root, Key, 'Inno Setup: App Path', Candidate) then
    RegQueryStringValue(Root, Key, 'InstallLocation', Candidate);
  Candidate := RemoveQuotes(Trim(Candidate));
  if (Candidate <> '') and
     (FileExists(AddBackslash(Candidate) + 'pilipili.exe') or
      FileExists(AddBackslash(Candidate) + 'piliplus.exe')) then
    Result := Candidate;
end;

function FindPreviousDir: String;
var
  Key, LegacyKey: String;
begin
  if not PreviousDirChecked then begin
    PreviousDirChecked := True;
    Key := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{{APP_ID}}_is1';
    LegacyKey := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\' +
      '{' + '{{APP_ID}}' + '}_is1';
    PreviousDir := RegisteredInstallDir(HKLM64, Key);
    if PreviousDir = '' then PreviousDir := RegisteredInstallDir(HKLM32, Key);
    if PreviousDir = '' then PreviousDir := RegisteredInstallDir(HKCU64, Key);
    if PreviousDir = '' then PreviousDir := RegisteredInstallDir(HKCU32, Key);
    if PreviousDir = '' then PreviousDir := RegisteredInstallDir(HKLM64, LegacyKey);
    if PreviousDir = '' then PreviousDir := RegisteredInstallDir(HKLM32, LegacyKey);
    if PreviousDir = '' then PreviousDir := RegisteredInstallDir(HKCU64, LegacyKey);
    if PreviousDir = '' then PreviousDir := RegisteredInstallDir(HKCU32, LegacyKey);
    if PreviousDir <> '' then
      Log('Pilipili upgrade directory: ' + PreviousDir)
    else
      Log('Pilipili: no existing installation found');
  end;
  Result := PreviousDir;
end;

function GetInstallDir(Param: String): String;
begin
  Result := FindPreviousDir;
  if Result = '' then Result := ExpandConstant('{{INSTALL_DIR_NAME}}');
end;

procedure InitializeWizard;
begin
  Log('Pilipili selected install directory: ' + WizardDirValue);
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := (PageID = wpSelectDir) and (FindPreviousDir <> '');
end;
