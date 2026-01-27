; Silver Stone Windows Installer Script
; Built with Inno Setup 6.x

#define MyAppName "Silver Stone"
#define MyAppPublisher "SS Architects"
#define MyAppURL "https://github.com/ssapp1632000/working-tracker-app"
#define MyAppExeName "silver_stone.exe"

; Version will be passed from command line: iscc /DMyAppVersion=1.0.4 silver_stone.iss
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif

[Setup]
; App identity
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}/releases

; Install location - user's local app data (no admin required)
DefaultDirName={localappdata}\{#MyAppName}
DisableProgramGroupPage=yes
DefaultGroupName={#MyAppName}

; Output settings
OutputDir=..\Output
OutputBaseFilename=SilverStone-Setup-{#MyAppVersion}
SetupIconFile=..\assets\images\app_icon.ico
Compression=lzma
SolidCompression=yes

; Installer behavior
PrivilegesRequired=lowest
WizardStyle=modern
DisableWelcomePage=no
DisableDirPage=yes
DisableReadyPage=yes

; Uninstall settings
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}

; Allow running without admin (user-level install)
PrivilegesRequiredOverridesAllowed=dialog

; Silent install support for auto-updates
; When run with /SILENT or /VERYSILENT, no UI is shown
AllowNoIcons=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Copy all files from the Flutter build output
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; Start Menu shortcut
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
; Desktop shortcut (optional)
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; Launch app after installation (unless silent mode)
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
// Close running instance before installation
function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
begin
  Result := True;
  // Try to close running instance gracefully
  if Exec('taskkill', '/F /IM silver_stone.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
  begin
    // Wait a moment for the process to fully terminate
    Sleep(500);
  end;
end;

// Restart the app after silent update
procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
begin
  if CurStep = ssPostInstall then
  begin
    // If this is a silent install (auto-update), restart the app
    if WizardSilent then
    begin
      Exec(ExpandConstant('{app}\{#MyAppExeName}'), '', '', SW_SHOWNORMAL, ewNoWait, ResultCode);
    end;
  end;
end;
