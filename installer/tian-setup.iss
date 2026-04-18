; TIAN — Talk Is All you Need
; Windows Installer Script for Inno Setup 6+
;
; Build:   iscc installer\tian-setup.iss          (from repo root)
; Output:  installer\dist\tian-setup-<version>.exe
;
; Download Inno Setup 6: https://jrsoftware.org/isdl.php

#define AppName      "TIAN"
#define AppVersion   "1.0.0"
#define AppPublisher "TIAN Project"
#define AppURL       "https://github.com/your-org/tian"
#define AppExeName   "tian-cli.bat"
#define AppGUID      "{{6F3A2B1C-D4E5-4F60-9A7B-8C9D0E1F2A3B}"

[Setup]
AppId={#AppGUID}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}/issues
AppUpdatesURL={#AppURL}/releases
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
; Allow user to choose install dir
DisableDirPage=no
; Single Start-Menu group entry
DisableProgramGroupPage=yes
; Compressed single-file exe
OutputDir=dist
OutputBaseFilename=tian-setup-{#AppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
; Require Windows 10+
MinVersion=10.0
; Need admin for PATH and Program Files
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog
; Modern Wizard UI
WizardStyle=modern
WizardSizePercent=120
; Icon (optional — place tian.ico in installer\assets\ to enable)
; SetupIconFile=assets\tian.ico
; License shown before install
; LicenseFile=..\LICENSE

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "addtopath";   Description: "Add tian-cli to system PATH (recommended)"; \
                     GroupDescription: "System integration:"; Flags: checkedonce
Name: "desktopicon"; Description: "Create a Desktop shortcut for the Setup Wizard"; \
                     GroupDescription: "Shortcuts:"; Flags: unchecked

[Files]
; CLI scripts
Source: "..\cli\*";        DestDir: "{app}\cli";    Flags: ignoreversion recursesubdirs createallsubdirs
; Config and catalog
Source: "..\config\*";     DestDir: "{app}\config"; Flags: ignoreversion recursesubdirs createallsubdirs
; Built-in skills
Source: "..\skills\*";     DestDir: "{app}\skills"; Flags: ignoreversion recursesubdirs createallsubdirs
; Setup wizard (lib + pages)
Source: "..\wizard\*";     DestDir: "{app}\wizard"; Flags: ignoreversion recursesubdirs createallsubdirs
; Entry-point scripts
Source: "..\tian-cli.bat"; DestDir: "{app}";        Flags: ignoreversion
Source: "..\setup.bat";    DestDir: "{app}";        Flags: ignoreversion

[Icons]
; Start Menu
Name: "{group}\TIAN Setup Wizard";                 Filename: "{app}\setup.bat";   WorkingDir: "{app}"
Name: "{group}\TIAN CLI (Command Prompt)";         Filename: "{sys}\cmd.exe";     Parameters: "/k cd /d ""{app}"" && echo Type: tian-cli help"; WorkingDir: "{app}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}";  Filename: "{uninstallexe}"
; Desktop (optional task)
Name: "{commondesktop}\TIAN Setup Wizard";         Filename: "{app}\setup.bat";   WorkingDir: "{app}"; Tasks: desktopicon

[Run]
; Offer to launch the Setup Wizard right after installation
Filename: "{app}\setup.bat"; \
  Description: "Launch TIAN Setup Wizard now"; \
  Flags: postinstall nowait skipifsilent unchecked

[Code]
{ ──────────────────────────────────────────────────────────────────────────── }
{ PATH management                                                              }
{ ──────────────────────────────────────────────────────────────────────────── }

const
  PathKey = 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment';

function GetSystemPath: string;
begin
  if not RegQueryStringValue(HKLM, PathKey, 'Path', Result) then
    Result := '';
end;

procedure SetSystemPath(const NewPath: string);
begin
  RegWriteStringValue(HKLM, PathKey, 'Path', NewPath);
  { Broadcast WM_SETTINGCHANGE so open Explorer windows pick up the new PATH }
  SendBroadcastMessage($001A, 0, 'Environment');
end;

procedure AddToPath(const Dir: string);
var
  OldPath: string;
begin
  OldPath := GetSystemPath;
  if Pos(Lowercase(Dir), Lowercase(OldPath)) = 0 then
    SetSystemPath(OldPath + ';' + Dir);
end;

{ Split a delimited string into a dynamic array }
function SplitPath(const S, Delim: string): TArrayOfString;
var
  Start, P: Integer;
  Count: Integer;
begin
  Count := 0;
  SetArrayLength(Result, 0);
  Start := 1;
  repeat
    P := Pos(Delim, Copy(S, Start, MaxInt));
    if P = 0 then
    begin
      SetArrayLength(Result, Count + 1);
      Result[Count] := Copy(S, Start, MaxInt);
      Count := Count + 1;
      Break;
    end else begin
      SetArrayLength(Result, Count + 1);
      Result[Count] := Copy(S, Start, P - 1);
      Count := Count + 1;
      Start := Start + P;
    end;
  until False;
end;

procedure RemoveFromPath(const Dir: string);
var
  OldPath, NewPath: string;
  Parts: TArrayOfString;
  I: Integer;
begin
  OldPath := GetSystemPath;
  Parts   := SplitPath(OldPath, ';');
  NewPath := '';
  for I := 0 to GetArrayLength(Parts) - 1 do
  begin
    if Lowercase(Trim(Parts[I])) <> Lowercase(Dir) then
    begin
      if NewPath <> '' then NewPath := NewPath + ';';
      NewPath := NewPath + Parts[I];
    end;
  end;
  SetSystemPath(NewPath);
end;

{ ──────────────────────────────────────────────────────────────────────────── }
{ Pre-install: check PowerShell 5.1+                                          }
{ ──────────────────────────────────────────────────────────────────────────── }

function InitializeSetup: Boolean;
var
  ResultCode: Integer;
begin
  Result := True;
  { Verify PowerShell is present and is version 5.1 or later }
  if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    '-NoProfile -Command "if ($PSVersionTable.PSVersion.Major -lt 5) { exit 1 }"',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode) or (ResultCode <> 0) then
  begin
    MsgBox(
      'TIAN requires Windows PowerShell 5.1 or later.' + #13#10 +
      'Please update Windows or install PowerShell 7 from:' + #13#10 +
      'https://aka.ms/powershell',
      mbError, MB_OK);
    Result := False;
  end;
end;

{ ──────────────────────────────────────────────────────────────────────────── }
{ Post-install: add to PATH if requested                                      }
{ ──────────────────────────────────────────────────────────────────────────── }

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    if WizardIsTaskSelected('addtopath') then
      AddToPath(ExpandConstant('{app}'));
  end;
end;

{ ──────────────────────────────────────────────────────────────────────────── }
{ Uninstall: remove from PATH                                                 }
{ ──────────────────────────────────────────────────────────────────────────── }

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
    RemoveFromPath(ExpandConstant('{app}'));
end;
