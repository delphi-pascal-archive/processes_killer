unit Unit1;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, Menus, ExtCtrls, ImgList, CommCtrl, XPMan, TLHelp32, ComObj,
  ShlObj, ActiveX, ShellAPI, PsAPI, VerInfo;

const
  WM_NOTIFYTRAYICON = WM_USER + 1;

type
 PTOKEN_USER = ^TOKEN_USER;
 _TOKEN_USER = record
 User : TSidAndAttributes;
end;

TOKEN_USER = _TOKEN_USER;

type
  TForm1 = class(TForm)
    XPManifest1: TXPManifest;
    TasksImageList: TImageList;
    Image1: TImage;
    OptionsPopupMenu: TPopupMenu;
    N1: TMenuItem;
    N2: TMenuItem;
    procedure FormCreate(Sender: TObject);
    procedure FormMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure FormDestroy(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure N1Click(Sender: TObject);
    procedure N2Click(Sender: TObject);
  private
    { Private declarations }
    procedure TrayIconNotify(var Msg: TMessage); message WM_NOTIFYTRAYICON;
    procedure WMCommand(var Msg: TWMCommand); message WM_COMMAND;
    procedure WMMeasureItem(var Msg: TWMMeasureItem); message WM_MEASUREITEM;
    procedure WMDrawItem(var Msg: TWMDrawItem); message WM_DRAWITEM;
    procedure ShowToolTipHint(Text: string; XPos: integer; YPos: integer);
    procedure HideToolTipHint;
    procedure GetTasksList;
  public
    { Public declarations }
  end;

var
  Form1: TForm1;
  MyMenu: HMenu;
  ItemsCount: integer;
  TTI: TToolInfo;
  TTHWND: THandle;
  TrayIconData: TNotifyIconData;
  PrHandle: THandle;
  TmpIcon: TIcon;
  TmpBMP: TBitmap;
  PPx: integer;
  PPy: integer;
  Domain, User: array [0..MAX_PATH] of Char;
  chDomain,chUser: Cardinal;
  NamesList: TStringList;
  PathsList: TStringList;
  PIDList: TStringList;
  PIDCheckList: TStringList;
  UserList: TStringList;
  MemoryList: TStringList;
  VersionList: TStringList;
  MayClose: boolean = false;
  
implementation

{$R *.dfm}

procedure TForm1.ShowToolTipHint(Text: string; XPos: integer; YPos: integer);
begin
  if TTHWND <> 0 then
    DestroyWindow(TTHWND);
  TTHWND:= CreateWindow(TOOLTIPS_CLASS, '',
    $30,
    Integer(CW_USEDEFAULT), Integer(CW_USEDEFAULT),
    Integer(CW_USEDEFAULT), Integer(CW_USEDEFAULT),
    0, 0, HInstance,
    nil);
  TTI.cbSize:= SizeOf(TTI);
  TTI.uFlags:= TTF_TRACK + TTF_TRANSPARENT;
  TTI.Rect.Left:= 0;
  TTI.Rect.Top:= 0;
  TTI.Rect.Bottom:= 0;
  TTI.Rect.Right:= 0;
  SetWindowPos(TTHWND, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOACTIVATE);
  TTI.lpszText:= PChar(Text);
  //SendMessage(TTHWND, WM_SETFONT, Form1.Font.Handle, 0);
  SendMessage(TTHWND, TTM_ADDTOOL, 0, Integer(@TTI));
  if YPos + 18 > Screen.Height then
    YPos:= Screen.Height - 18;
  SendMessage(TTHWND, TTM_TRACKPOSITION, 0, MAKELPARAM(XPos, YPos));
  SendMessage(TTHWND, TTM_TRACKACTIVATE, Integer(LongBool(True)), Integer(@TTI));
end;

procedure TForm1.HideToolTipHint;
begin
  SendMessage(TTHWND, TTM_TRACKACTIVATE, Integer(0), Integer(@TTI));
end;

function GetCurrentUserAndDomain (
      szUser : PChar; var chUser: DWORD; szDomain :PChar; var chDomain : DWORD
 ):Boolean;
var
 hToken : THandle;
 cbBuf  : Cardinal;
 ptiUser : PTOKEN_USER;
 snu    : SID_NAME_USE;
begin
 Result:=false;
 if not OpenThreadToken(GetCurrentThread(),TOKEN_QUERY,true,hToken)
  then begin
   if GetLastError()<> ERROR_NO_TOKEN then exit;
   if not OpenProcessToken(PrHandle,TOKEN_QUERY,hToken)
    then exit;
  end;
 if not GetTokenInformation(hToken, TokenUser, nil, 0, cbBuf)
  then if GetLastError()<> ERROR_INSUFFICIENT_BUFFER
   then begin
    CloseHandle(hToken); 
    exit;
   end;
 if cbBuf = 0 then exit;
 GetMem(ptiUser,cbBuf);
 if GetTokenInformation(hToken,TokenUser,ptiUser,cbBuf,cbBuf)
  then begin
   if LookupAccountSid(nil,ptiUser.User.Sid,szUser,chUser,szDomain,chDomain,snu)
    then Result:=true;
  end;
 CloseHandle(hToken);
 FreeMem(ptiUser);
end;

function GetIcon(const FileName: string):
  TIcon;
var
  FileInfo: TShFileInfo;
  ImageList: TImageList;
begin
  Result := TIcon.Create;
  ImageList := TImageList.Create(nil);
  FillChar(FileInfo, Sizeof(FileInfo), #0);
  ImageList.ShareImages := true;
  ImageList.Handle := SHGetFileInfo(
    PChar(FileName),
    SFGAO_SHARE,
    FileInfo,
    SizeOf(FileInfo),
    SHGFI_SMALLICON or SHGFI_SYSICONINDEX
    );
  ImageList.GetIcon(FileInfo.iIcon, Result);
  ImageList.Free;
end;

procedure TForm1.TrayIconNotify(var Msg: TMessage);
begin
  case Msg.LParam of
    WM_LBUTTONDOWN:
    begin
      GetTasksList;
    end;
    WM_LBUTTONUP:
    begin
      SetForegroundWindow(Handle);
      PPx:= Mouse.CursorPos.X;
      PPy:= Mouse.CursorPos.Y;
      TrackPopupMenu(MyMenu, TPM_RIGHTALIGN, Mouse.CursorPos.X, Mouse.CursorPos.Y , 0, Self.Handle, nil);
    end;
    WM_RBUTTONUP:
    begin
      OptionsPopupMenu.Popup(Mouse.CursorPos.X, Mouse.CursorPos.Y);
    end;
  end;
end;

function ProcessTerminate(PID:Cardinal):Boolean;
var
  hProcess: THandle;
begin
   Result:=false;
   hProcess := OpenProcess(PROCESS_TERMINATE, FALSE, PID);
   if hProcess = 0  then
     Exit;
   if TerminateProcess(hProcess, DWORD(-1)) then
     Result:= true;
   CloseHandle( hProcess );
end;

procedure TForm1.WMCommand(var Msg: TWMCommand);
var
  i: integer;
begin
  for i:= 0 to PathsList.Count - 1 do
  if Msg.ItemID = i then
  begin
    {if (NamesList.Strings[Msg.ItemID] = 'spoolsv.exe') or
     (NamesList.Strings[Msg.ItemID] = 'lsass.exe') or
     (NamesList.Strings[Msg.ItemID] = 'svchost.exe') or
     (NamesList.Strings[Msg.ItemID] = 'services.exe') or
     (NamesList.Strings[Msg.ItemID] = 'smss.exe') or
     (NamesList.Strings[Msg.ItemID] = 'winlogon.exe') or
     (NamesList.Strings[Msg.ItemID] = 'csrss.exe') then
  Exit;
  if StrToInt(PIDList.Strings[Msg.ItemID]) = 0 then
    Exit; }
  if not ProcessTerminate(StrToInt(PIDList.Strings[Msg.ItemID])) then
    ShowMessage('Невозможно завершить процесс: ' + PathsList.Strings[Msg.ItemID]);
  end;

end;

procedure TForm1.WMMeasureItem(var Msg:TWMMeasureItem);
begin
  with Msg.MeasureItemStruct^ do
  begin
    ItemWidth:= Canvas.TextWidth(PathsList.Strings[itemID]) + Canvas.TextWidth(MemoryList.Strings[ItemID]) + 50;
    Itemheight:=18;
  end;
end;

procedure TForm1.WMDrawItem(var Msg: TWMDrawItem);
var
  hbr: HBRUSH;
  hbr2: HBRUSH;
  i: integer;
  pRect: TRect;
  mRect: TRect;

begin
  TmpBMP:= TBitmap.Create;
  TmpBMP.Width:= 16;
  TmpBMP.Height:= 16;
  hbr:= CreateSolidBrush(GetSysColor(COLOR_HIGHLIGHT));
  hbr2:= CreateSolidBrush(GetSysColor(COLOR_MENU));
  with Msg.DrawItemStruct^ do
  begin
    rcItem.Left:= 19;
    pRect:= Rect(rcItem.Left + 3, rcItem.Top + 2, rcItem.Right, rcItem.Bottom);
    mRect:= Rect(rcItem.Left, rcItem.Top + 2, rcItem.Right - 2, rcItem.Bottom);
    for i:= 0 to PathsList.Count - 1 do
    begin
      if ItemID = i then
      begin
        if (itemState and ODS_SELECTED) <> 0 then
        begin
          FillRect(hDc, rcItem, hbr);
          SetTextColor(hDC, GetSysColor(COLOR_HIGHLIGHTTEXT));
          SetBkColor(hDC, GetSysColor(COLOR_HIGHLIGHT));
          ShowToolTipHint(PChar(VersionList.Strings[ItemID]), (PPx - rcItem.Right) + rcItem.Right div 4,
            PPy - (PathsList.Count) * 18 + rcItem.Bottom - 2);
        end else
        begin
          FillRect(hDc, rcItem, hbr2);
          if UserList.Strings[ItemID] = 'SYSTEM' then
            SetTextColor(hDC, RGB(233, 0, 0))
          else
            SetTextColor(hDC, GetSysColor(COLOR_MENUTEXT));
          SetBkColor(hDC, GetSysColor(COLOR_MENU));
          HideToolTipHint;
        end;
      end;
    end;
    TasksImageList.Draw(TmpBMP.Canvas, 0, 0, ItemID, true);
    BitBlt(hDC, 1, rcItem.Top + 1, TmpBMP.Width, TmpBMP.Height, TmpBMP.Canvas.Handle, 0, 0, SRCCOPY);
    DrawText(hDC, PChar(PathsList.Strings[ItemID]),
      Length(PathsList.Strings[ItemID]), pRect, DT_LEFT);
    DrawText(hDC, PChar(MemoryList.Strings[ItemID]),
      Length(MemoryList.Strings[ItemID]), mRect, DT_RIGHT);
    ReleaseDC(0, hDC);
    DeleteObject(hbr2);
    DeleteObject(hbr);
  end;
  TmpBMP.Free;

end;

procedure TForm1.GetTasksList;
var
  i: integer;
  hProcSnap: THandle;
  pe32: TProcessEntry32;
  ExePath: array[0..MAX_PATH] of Char;
  SysTemDir: array[0..MAX_PATH] of Char;
  pmc: PPROCESS_MEMORY_COUNTERS;
  cb:  Integer;
  FileInfo: TFileVersionInfo;
begin
  NamesList.Clear;
  PIDList.Clear;
  PathsList.Clear;
  MemoryList.Clear;
  UserList.Clear;

  hProcSnap := CreateToolHelp32SnapShot(TH32CS_SNAPPROCESS, 0);
  if hProcSnap = INVALID_HANDLE_VALUE then
    Exit;
  pe32.dwSize := SizeOf(ProcessEntry32);
  if Process32First(hProcSnap, pe32) then
  while Process32Next(hProcSnap, pe32) do
  begin
    PrHandle:= OpenProcess(PROCESS_QUERY_INFORMATION or PROCESS_VM_READ, False, pe32.th32ProcessID);
    chDomain:= 50;
    chUser:= 50;
    GetCurrentUserAndDomain(User,chuser,Domain,chDomain);
    GetModuleFileNameEx(PrHandle, 0, ExePath, MAX_PATH);
    cb:= SizeOf(_PROCESS_MEMORY_COUNTERS);
    GetMem(pmc, cb);
    pmc^.cb := cb;
    GetProcessMemoryInfo(PrHandle, pmc, cb);
    GetSystemDirectory(SysTemDir, MAX_PATH);
    NamesList.Add(pe32.szExeFile);
    PIDList.Add(IntToStr(pe32.th32ProcessID));
    if pe32.szExeFile = 'winlogon.exe' then
      PathsList.Add(SysTemDir + '\winlogon.exe')
    else
    if pe32.szExeFile = 'smss.exe' then
      PathsList.Add(SysTemDir + '\smss.exe')
    else
    if pe32.szExeFile = 'csrss.exe' then
      PathsList.Add(SysTemDir + '\csrss.exe')
    else
    if pe32.szExeFile = 'System' then
      PathsList.Add('System')
    else
      PathsList.Add(ExePath);
    MemoryList.Add(IntToStr(pmc^.WorkingSetSize div 1024) + ' Kb');
    UserList.Add(User);
  end;
  if PIDList.Text <> PIDCheckList.Text then
  begin
    if MyMenu <> 0 then
    DestroyMenu(MyMenu);
      MyMenu:= CreatePopupMenu;
    TasksImageList.Clear;
    VersionList.Clear;
    for i:= 0  to PIDList.Count - 1 do
    begin
      TmpIcon:= TIcon.Create;
      TmpIcon:= GetIcon(PathsList.Strings[i]);
      if NamesList.Strings[i] = 'System' then
        TasksImageList.AddIcon(Image1.Picture.Icon)
      else
      if TmpIcon.Handle = 0 then
        TasksImageList.AddIcon(Image1.Picture.Icon)
      else
        TasksImageList.AddIcon(TmpIcon);
      TmpIcon.Free;
      FileInfo := TFileVersionInfo.Create(PathsList.Strings[i]);
      try
        if FileInfo.HasInfo then
        begin
         if (FileInfo.GetString(INFO_FileDescription) = '') or (FileInfo.GetString(INFO_FileDescription) = ' ') then
           VersionList.Add('Description Not Available')
         else
           VersionList.Add(FileInfo.GetString(INFO_FileDescription));
        end else
        begin
          if PathsList.Strings[i] = 'System' then
            VersionList.Add('System')
          else
            VersionList.Add('Description Not Available');
        end;
      finally
        FileInfo.Free;
      end;
      AppendMenu(MyMenu, MF_OWNERDRAW, i, PChar(PathsList.Strings[i]));
    end;
    PIDCheckList.Text:= PIDList.Text;
  end;
  CloseHandle(PrHandle);
  CloseHandle(hProcSnap);
end;

function EnableDebugPrivilege(): Boolean;
var
  hToken: THandle;
  tp: TOKEN_PRIVILEGES;
  d: DWORD;
begin
  Result := False;
  if OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES, hToken) then
  begin
    tp.PrivilegeCount:= 1;
    LookupPrivilegeValue(nil, 'SeDebugPrivilege', tp.Privileges[0].Luid);
    tp.Privileges[0].Attributes:= $00000002;
    AdjustTokenPrivileges(hToken, False, tp, SizeOf(TOKEN_PRIVILEGES), nil, d);
    if GetLastError = ERROR_SUCCESS then
    begin
      Result := True;
    end;
    CloseHandle(hToken);
  end;
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  Application.ShowMainForm:= false;
  EnableDebugPrivilege();
  TasksImageList.BkColor:= GetSysColor(COLOR_MENU);
  with TrayIconData do
  begin
    cbSize:= SizeOf(TNotifyIconData);
    Wnd:= Form1.Handle;
    uID:= 0;
    uFlags := NIF_ICON or NIF_MESSAGE or NIF_TIP;
    uCallBackMessage := WM_NOTIFYTRAYICON;
    hIcon:= Application.Icon.Handle;
    szTip:= ('Processes Killer');
  end;
  Shell_NotifyIcon(NIM_ADD, @TrayIconData);
  NamesList:= TStringList.Create;
  PathsList:= TStringList.Create;
  PIDList:= TStringList.Create;
  PIDCheckList:= TStringList.Create;
  UserList:= TStringList.Create;
  MemoryList:= TStringList.Create;
  VersionList:= TStringList.Create;
  GetTasksList;
end;

procedure TForm1.FormMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if Button = mbLeft then
    TrackPopupMenu(MyMenu, TPM_LEFTALIGN, Mouse.CursorPos.X, Mouse.CursorPos.Y + 1, 0, Handle, nil);
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  with TrayIconData do
  begin
    cbSize:= SizeOf(TNotifyIconData);
    Wnd:= Form1.Handle;
    uID:= 0;
  end;
  Shell_NotifyIcon(NIM_DELETE, @TrayIconData);
  NamesList.Free;
  PathsList.Free;
  PIDList.Free;
  PIDCheckList.Free;
  UserList.Free;
  MemoryList.Free;
  VersionList.Free;
end;



procedure TForm1.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if MayClose = false then
  begin
    CanClose:= false;
    MayClose:= true;
    Form1.Hide;
  end else
  begin
    CanClose:= true;
  end;
end;

procedure TForm1.N1Click(Sender: TObject);
begin
  MayClose:= false;
  Form1.Show;
  ShowWindow(Application.Handle, SW_SHOW);
end;

procedure TForm1.N2Click(Sender: TObject);
begin
  MayClose:= true;
  Form1.Close;
end;

end.
