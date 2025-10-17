; Selene Windows Installer Script
; 使用 Inno Setup 编译此脚本以创建安装程序

#define MyAppName "Selene"
#define MyAppPublisher "MoonTachLab"
#define MyAppURL "https://github.com/MoonTechLab/selene"
#define MyAppExeName "selene.exe"

; 版本号将在构建时通过命令行参数传入
; 例如: iscc /DMyAppVersion=1.4.3 installer.iss
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif

[Setup]
; 应用基本信息
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}

; 安装路径
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes

; 输出设置
OutputDir=..\dist
OutputBaseFilename=selene-{#MyAppVersion}-windows-x64-setup
SetupIconFile=..\logo.ico
UninstallDisplayIcon={app}\{#MyAppExeName}

; 压缩设置
Compression=lzma2/ultra64
SolidCompression=yes
LZMAUseSeparateProcess=yes
LZMANumBlockThreads=2

; 安装界面
WizardStyle=modern
DisableWelcomePage=no

; 权限和兼容性
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64

; 许可协议（如果有的话）
; LicenseFile=..\LICENSE

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; 复制所有构建产物
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; 注意：如果有额外的运行时依赖，在这里添加

[Icons]
; 开始菜单快捷方式
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"

; 桌面快捷方式
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; 安装完成后运行应用
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
// 检查是否已安装旧版本
function InitializeSetup(): Boolean;
begin
  Result := True;
end;

// 卸载时清理用户数据（可选）
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    if MsgBox('是否删除应用数据和设置？', mbConfirmation, MB_YESNO) = IDYES then
    begin
      // 删除用户数据目录
      DelTree(ExpandConstant('{localappdata}\selene'), True, True, True);
    end;
  end;
end;
