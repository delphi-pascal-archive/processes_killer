unit VerInfo;

interface
uses Windows;

const
 MaxInfoStrings = 7;

 INFO_CompanyName = 'CompanyName';
 INFO_FileDescription = 'FileDescription';
 INFO_FileVersion = 'FileVersion';
 INFO_InternalName = 'InternalName';
 INFO_LegalCopyright = 'LegalCopyright';
 INFO_OriginalFileName = 'OriginalFileName';
 INFO_ProductName = 'ProductName';
 INFO_ProductVersion = 'ProductVersion';

 VersionInfoStrings: array [0..MaxInfoStrings] of string =
 (
   INFO_CompanyName,
   INFO_FileDescription,
   INFO_FileVersion,
   INFO_InternalName,
   INFO_LegalCopyright,
   INFO_OriginalFileName,
   INFO_ProductName,
   INFO_ProductVersion
 );

type
 TFileVersion = record
   Minor,
   Major,
   Build,
   Release: WORD;
 end;

 TFileVersionInfo = class 
 private
   FFileName: string;
   FBuffer: PChar;
   FBuffLen: Cardinal;
   FLocale: string;
   procedure SetFileName(const Value: string);
   procedure LoadFile (AFileName: string);
   procedure UnloadFile;
   function GetHasInfo: Boolean;
 public
   constructor Create (AFileName: string); 
   destructor Destroy; override;

   property HasInfo: Boolean read GetHasInfo;
   property FileName: string read FFileName write SetFileName;
   property Locale: string read FLocale;

   function GetString (AString: string): string;
   function GetVersion: TFileVersion;

 end;

implementation
uses SysUtils;

{ TFileVersionInfo }

type
 TVer1 = record
   Minor: Word;
   Major: Word;
 end;
 TVer2 = record
   Build: Word;
   Release: Word;
 end;

constructor TFileVersionInfo.Create(AFileName: string);
begin
 FFileName := AFileName;
 LoadFile(AFileName);
end;

destructor TFileVersionInfo.Destroy;
begin
 UnloadFile;
 inherited;
end;

function TFileVersionInfo.GetHasInfo: Boolean;
begin
 Result := (FFileName <> '') and (FBuffLen <> 0);
end;

function TFileVersionInfo.GetString(AString: string): string;
var
 InfoLen: Cardinal;
 PInfo: PChar;
begin
 if VerQueryValue(
   FBuffer,
   PChar('\StringFileInfo\' + FLocale + '\'+AString),
   Pointer(PInfo),
   InfoLen
 ) then
 begin
   Result := PInfo;
 end
 else
   Result := ''
end;

function TFileVersionInfo.GetVersion: TFileVersion;
var
 FI: PVSFixedFileInfo;
 VerSize: Cardinal;
 Ver1: TVer1;
 Ver2: TVer2;
begin
 if VerQueryValue(FBuffer,'\',Pointer(FI),VerSize) then
 begin
   Ver1 := TVer1(FI.dwFileVersionMS);
   Ver2 := TVer2(FI.dwFileVersionLS);

   Result.Minor := Ver1.Minor;
   Result.Major := Ver1.Major;
   Result.Build := Ver2.Build;
   Result.Release := Ver2.Release;
 end;
end;

procedure TFileVersionInfo.LoadFile(AFileName: string);
var
 Dummy,LangLen: Cardinal;
 LangBuff: PChar;
begin
 UnloadFile;

 FBuffLen := 0;

 // Buffer size
 FBuffLen := GetFileVersionInfoSize(
   PChar(AFileName),
   Dummy
 );

 if FBuffLen <> 0 then
 begin
   GetMem (FBuffer,FBuffLen);

   // read resource data
   GetFileVersionInfo(
     PChar(FileName),
     0,
     FBuffLen,
     FBuffer
   );

   // check string locale
   VerQueryValue(FBuffer, '\VarFileInfo\Translation', pointer(LangBuff), LangLen);
   if langLen >= 4 then // if specified
   begin
     StrLCopy(@Dummy, LangBuff, 2);
     FLocale:= Format('%4.4x', [Dummy]);
     StrLCopy(@Dummy, LangBuff+2, 2);
     FLocale := FLocale + Format('%4.4x', [Dummy]);
   end
   else
     // use Amer. Engl, ANSI
     FLocale := '040904E4';
 end;
end;

procedure TFileVersionInfo.SetFileName(const Value: string);
begin
 FFileName := Value;
 LoadFile(Value);
end;

procedure TFileVersionInfo.UnloadFile;
begin
 FreeMem (FBuffer);
end;

end.

 