#define MyAppName "VNTC 2.0 Client"
#define MyAppVersion "1.1.3"
#define MyAppPublisher "luojiang419"
#define MyAppURL "https://github.com/luojiang419/VNTC-2.0-client"
#define MyAppExeName "vntc2_flutter.exe"
#define MySourceDir AddBackslash(SourcePath) + "VNTC-2.0-client-v" + MyAppVersion + "-win-x64"
#define MyOutDir SourcePath

[Setup]
AppId={{9C9F4C77-6E5B-4CBF-8DDB-9D6B6746CE20}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\VNTC 2.0 Client
DefaultGroupName=VNTC 2.0 Client
AllowNoIcons=yes
OutputDir={#MyOutDir}
OutputBaseFilename=VNTC-2.0-client-v1.1.3-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupIconFile={#MySourceDir}\app_icon.ico
UninstallDisplayIcon={app}\app_icon.ico
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin

[Languages]
Name: "default"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"; Flags: unchecked

[Files]
Source: "{#MySourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\VNTC 2.0 Client"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\VNTC 2.0 Client"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch VNTC 2.0 Client"; Flags: nowait postinstall skipifsilent
