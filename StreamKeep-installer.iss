; ============================================================
;  StreamKeep — Inno Setup Installer Script
;  Created by Nirlicnick
;
;  To build: Open this file in Inno Setup Compiler
;  Download Inno Setup: https://jrsoftware.org/isinfo.php
; ============================================================

#define AppName "StreamKeep"
#define AppVersion "1.0.0"
#define AppPublisher "Nirlicnick"
#define AppURL "https://github.com/Nirlicnick/StreamKeep"
#define AppExeName "StreamKeep.py"

[Setup]
AppId={{8F3A2C1D-4E5B-6F7A-8B9C-0D1E2F3A4B5C}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
AllowNoIcons=yes
OutputDir=dist
OutputBaseFilename=StreamKeep-{#AppVersion}-Setup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
SetupIconFile=
UninstallDisplayName={#AppName} by {#AppPublisher}
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "startupentry"; Description: "Start StreamKeep automatically when Windows starts (recommended)"; GroupDescription: "Startup:"

[Files]
Source: "StreamKeep.py";        DestDir: "{app}"; Flags: ignoreversion
Source: "StreamKeep-Watcher.ps1";   DestDir: "{app}"; Flags: ignoreversion
Source: "StreamKeep-Watchdog.ps1";         DestDir: "{app}"; Flags: ignoreversion
Source: "setup.ps1";            DestDir: "{app}"; Flags: ignoreversion
Source: "channels.txt";         DestDir: "{app}"; Flags: ignoreversion onlyifdoesntexist
Source: "chat-viewer.html";     DestDir: "{app}"; Flags: ignoreversion
Source: "README.md";            DestDir: "{app}"; Flags: ignoreversion
Source: "START HERE.bat";       DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\StreamKeep";              Filename: "{app}\START HERE.bat"; Comment: "Launch StreamKeep"
Name: "{group}\Chat Viewer";             Filename: "{app}\chat-viewer.html"; Comment: "Open Chat Viewer"
Name: "{group}\channels.txt";            Filename: "{app}\channels.txt"; Comment: "Edit watched channels"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\StreamKeep";        Filename: "{app}\START HERE.bat"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "StreamKeep"; ValueData: "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\StreamKeep-Watchdog.ps1"""; Flags: uninsdeletevalue; Tasks: startupentry

[Run]
Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -File ""{app}\setup.ps1"""; Description: "Run first-time setup (installs yt-dlp, ffmpeg, Python packages)"; Flags: postinstall shellexec skipifsilent; StatusMsg: "Running setup..."
Filename: "{app}\START HERE.bat"; Description: "Launch StreamKeep now"; Flags: postinstall shellexec skipifsilent nowait

[UninstallRun]
Filename: "powershell.exe"; RunOnceId: "StopProcesses"; Parameters: "-Command ""Stop-Process -Name yt-dlp -Force -ErrorAction SilentlyContinue; Stop-Process -Name python -Force -ErrorAction SilentlyContinue"""

[Code]
function InitializeSetup(): Boolean;
begin
  Result := True;
end;
