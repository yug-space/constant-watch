[Setup]
AppId={{2D4E32AC-7851-4465-AD6D-96E30D1F10B8}
AppName=Constant Watch
AppVersion=0.2.0
AppPublisher=Constant Watch
AppPublisherURL=https://constant-watch.yuggupta.chatgpt.site
DefaultDirName={localappdata}\Programs\Constant Watch
DefaultGroupName=Constant Watch
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.22000
OutputDir=..\dist
OutputBaseFilename=Constant-Watch-0.2.0-Windows-x64-Setup
SetupIconFile=constant-watch.ico
UninstallDisplayIcon={app}\constant-watch.exe
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
[Files]
Source: "..\dist\Constant Watch\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Tasks]
Name: desktopicon; Description: "Create a desktop shortcut"; Flags: unchecked
[Icons]
Name: "{group}\Constant Watch"; Filename: "{app}\constant-watch.exe"
Name: "{autodesktop}\Constant Watch"; Filename: "{app}\constant-watch.exe"; Tasks: desktopicon
[Run]
Filename: "{app}\constant-watch.exe"; Description: "Open Constant Watch"; Flags: nowait postinstall skipifsilent
