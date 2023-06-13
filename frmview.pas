unit frmView;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, Types, LCLType, AtermisClient, fileutil ;

type

  { TViewForm }

  TViewForm = class(TForm)
    PaintBox1: TPaintBox;
    sbA: TScrollBox;
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCreate(Sender: TObject);
    procedure FormDropFiles(Sender: TObject; const FileNames: array of String);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormPaint(Sender: TObject);
    procedure FormUTF8KeyPress(Sender: TObject; var UTF8Key: TUTF8Char);
    procedure Image1MouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure Image1MouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer
      );
    procedure Image1MouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure Image1MouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    procedure PaintBox1Paint(Sender: TObject);
  private
     gx,gy:integer;
  public
     FBmp1:TBitmap;
     FRect:TRect;
     paintaction:integer;
     aclient:TAtermisClient;
  end;

var
  ViewForm: TViewForm;

implementation

{$R *.lfm}

{ TViewForm }


procedure TViewForm.FormCreate(Sender: TObject);
begin
   aclient:=nil;
   FBmp1:=TBitmap.Create;
end;

procedure TViewForm.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
   if aclient<>nil then
   begin
        aclient.doterminate();
   end;
end;

procedure TViewForm.FormDropFiles(Sender: TObject;
  const FileNames: array of String);
begin
  if DirectoryExists(FileNames[0]) then
     exit;
  aclient.sendFile(FileNames[0]);
end;

procedure TViewForm.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
    if aclient=nil then
     exit;
    //if key in [65..90] then
    //   aclient.sendKey(key-64,shift,2)
    //else
        aclient.sendKey(key,shift,2);
    Key := 0;
end;

procedure TViewForm.FormKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState
  );
begin
    if aclient=nil then
     exit;
    //if key in [65..90] then
    //   aclient.sendKey(key-64,shift,1)
    //else
        aclient.sendKey(key,shift,1);
    Key := 0;
end;

procedure TViewForm.FormPaint(Sender: TObject);
begin

end;

{
FPC 的 keydown 及 UTF8KeyPress, 在WINDOWS 上測試如下
順序: 先觸發 keydown 再 UTF8KeyPress
英數: 兩個都會收到, 但KEYDOWN 的英文字的KEY 值固定為大寫英文的
中文: UTF8KeyPress，keydown 不會收到任何東西。
CTRL: keydown 會收到，且KEY 會有值, SHIFT = 16, CTRL=17, ALT=18,CAPSLOCK=20,HOME=36,PAGEUP=33,
      PAGEDOWN=34,END=35 F1=112...F11=122, F12=123,
      BACKSPACE=8(UTF8KeyPress 也會收到),DEL=46,左=37,上=38,右=39,下=40
CTRL+英文: keydown 的KEY 會收到對應的ASCII 值及CTRL/ALT/SHIFT 的狀態，
           UTF8KeyPress會收到長度為1 的KEY，內容CTRL+a/A=1..CTRL+z/Z=26。

KeyDown: 只處理方向鍵，HOME鍵等特殊鍵，CTRL?
UTF8KeyPress: 處理英數，空白，中文等
}
procedure TViewForm.FormUTF8KeyPress(Sender: TObject; var UTF8Key: TUTF8Char);
begin
    if aclient=nil then
     exit;
end;

procedure TViewForm.Image1MouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
    if aclient=nil then
     exit;
    gx:=x;
    gy:=y;
    aclient.sendMouseClick(gx,gy,0,2,Button,Shift);
end;

procedure TViewForm.Image1MouseMove(Sender: TObject; Shift: TShiftState; X,
  Y: Integer);
begin
    if aclient=nil then
     exit;
    gx:=x;
    gy:=y;
    aclient.sendMouseMove(gx,gy);
end;

procedure TViewForm.Image1MouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
    if aclient=nil then
     exit;
    gx:=x;
    gy:=y;
    aclient.sendMouseClick(gx,gy,0,1,Button,Shift);
end;

procedure TViewForm.Image1MouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
begin
    Handled:=true;
    if aclient=nil then
     exit;
    aclient.sendMouseClick(gx,gy,WheelDelta,1,mbMiddle,Shift);
end;


procedure TViewForm.PaintBox1Paint(Sender: TObject);
begin
  PaintBox1.Canvas.Lock;
  PaintBox1.Canvas.Draw(FRect.Left, FRect.Top, FBmp1);
  PaintBox1.Canvas.Unlock;
end;

end.

