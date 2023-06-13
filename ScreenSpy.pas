unit ScreenSpy;

{$MODE Delphi}

interface

uses
  windows,LCLIntf, LCLType, LMessages, Sysutils, Classes, Graphics, winsock,  header, SyncObjs;

const
  DEF_STEP = 19;
  OFF_SET  = 32;

type
  TScreenSpy = class(TThread)
  private
    FmsScr, FmsSend: TMemoryStream;
    FFullBmp, FLineBmp, FRectBmp: TBitmap;
    FWidth, FHeight, FLine: Integer;
    FRect: TRect;
    FDC: HDC;
    FCmd: TCtlCmd;
    FIncSize: Byte;
    isSuspend:Boolean;
		FPixelFormat: TPixelFormat;
    //
    function CheckScr: Boolean;
    function SendData(nCmd: Byte): Boolean;
    procedure GetFirst;
    procedure GetNext;
    procedure SendRect;
    procedure CopyRect(rt: TRect);
		function 	getColorDepth():integer;
  protected
    procedure Execute; override;
  public
  	FSocket:Tsocket;
  	isConnected:boolean;
    locker:TCriticalSection;
		mainfrmHandle:integer;
		ExptMsg:String;
    //    
    constructor Create; reintroduce;
    destructor Destroy; override;
    procedure doSuspend;
    procedure doResume;
		procedure SetPixelFormat(Value: TPixelFormat);
  end;

implementation

constructor TScreenSpy.Create;
begin
  FreeOnTerminate := True;
  FmsScr   := TMemoryStream.Create;
  FmsSend  := TMemoryStream.Create;
  FFullBmp := TBitmap.Create;
  FLineBmp := TBitmap.Create;
  FRectBmp := TBitmap.Create;
  FWidth   := 0;
  FHeight  := 0;
  FIncSize := 4;
	ExptMsg  :='';
  isSuspend:=false;
  FPixelFormat := pf8bit;
  locker:=TCriticalSection.Create;
  inherited Create(True);
end;
procedure TScreenSpy.SetPixelFormat(Value: TPixelFormat);
begin
  FPixelFormat := Value;
  case FPixelFormat of
    pf1bit:  FIncSize := 32;
    pf4bit:  FIncSize := 8;
    pf8bit:  FIncSize := 4;
    pf16bit: FIncSize := 2;
    pf32bit: FIncSize := 1;
    else
      FPixelFormat := pf8bit;
      FIncSize := 4;
  end;
end;
destructor TScreenSpy.Destroy;
begin
  FmsScr.Free;
  FmsSend.Free;
  FRectBmp.Free;
  FFullBmp.Free;
  FLineBmp.Free;
  locker.Free;
  inherited;
end;

procedure TScreenSpy.Execute;
begin
  try
    while (not Terminated) and (isConnected) do
    begin
      if isSuspend then
        suspend;
      locker.Acquire;
      if CheckScr then
        GetFirst
      else
        GetNext;
      locker.Release;
      Sleep(30);
    end;
  except
		on E: Exception do
		begin
			ExptMsg:=E.Message;
			postmessage(mainfrmHandle,WM_STATEMESSAGE,errSpyExpt,0);
		end;
  end;
end;
procedure TScreenSpy.doResume;
begin
  isSuspend:=false;
  resume;
end;
procedure TScreenSpy.doSuspend;
begin
  isSuspend:=true;
end;

function TScreenSpy.CheckScr: Boolean;
var
  nWidth, nHeight: Integer;
begin
  Result  := False;
  nWidth  := GetSystemMetrics(SM_CXSCREEN);
  nHeight := GetSystemMetrics(SM_CYSCREEN);
  if (nWidth <> FWidth) or (nHeight <> FHeight) then
  begin
    FWidth  := nWidth;
    FHeight := nHeight;
    FFullBmp.Canvas.Lock;
    FLineBmp.Canvas.Lock;
    FRectBmp.Canvas.Lock;
    FFullBmp.Width  := FWidth;
    FFullBmp.Height := FHeight;
    FLineBmp.Width  := FWidth;
    FLineBmp.Height := 1;
    FFullBmp.PixelFormat := FPixelFormat;
    FLineBmp.PixelFormat := FPixelFormat;
    FRectBmp.PixelFormat := FPixelFormat;
    FFullBmp.Canvas.Unlock;
    FLineBmp.Canvas.Unlock;
    FRectBmp.Canvas.Unlock;
    FLine  := 0;
    Result := True;
  end;
end;
procedure TScreenSpy.GetFirst;

{
POINT pt;
HCURSOR hCur=GetCursor();
GetCursorPos(&pt);
DrawIcon(bmp1->Canvas->Handle, pt.x, pt.y, hCur);
}
begin
  FDC := GetDC(0);
  if FDC=0 then
  begin
    postmessage(mainfrmHandle,WM_STATEMESSAGE,errSpyGetScreen,getLastError());
    exit;
  end;
  FFullBmp.Canvas.Lock;
        ///* Ternary raster operations */
				
        //SRCCOPY             = 0x00CC0020 ;  /* dest = source                   */
        //SRCPAINT            = 0x00EE0086 ;  /* dest = source OR dest           */
        //SRCAND              = 0x008800C6 ;  /* dest = source AND dest          */
        //SRCINVERT           = 0x00660046 ;  /* dest = source XOR dest          */
        //SRCERASE            = 0x00440328 ;  /* dest = source AND (NOT dest )   */
        //NOTSRCCOPY          = 0x00330008 ;  /* dest = (NOT source)             */
        //NOTSRCERASE         = 0x001100A6 ;  /* dest = (NOT src) AND (NOT dest) */
        //MERGECOPY           = 0x00C000CA ;  /* dest = (source AND pattern)     */
        //MERGEPAINT          = 0x00BB0226 ;  /* dest = (NOT source) OR dest     */
        //PATCOPY             = 0x00F00021 ;  /* dest = pattern                  */
        //PATPAINT            = 0x00FB0A09 ;  /* dest = DPSnoo                   */
        //PATINVERT           = 0x005A0049 ;  /* dest = pattern XOR dest         */
        //DSTINVERT           = 0x00550009 ;  /* dest = (NOT dest)               */
        //BLACKNESS           = 0x00000042 ;  /* dest = BLACK                    */
        //WHITENESS           = 0x00FF0062 ;  /* dest = WHITE                    */
{
  If you will try to capture the screen to bitmap using BitBlt function
  and have a layered (transparent)  window visible,
  you will get only a picture of the screen without this window.
  To fix it we have to use the new raster-operation code for BitBlt
  function CAPTUREBLT = $40000000; that introduced in Windows 2000 for including
  any windows that are layered on top of your window in the resulting image.
	就可以截取layered窗口(包括透明窗口)
	
}
  BitBlt(FFullBmp.Canvas.Handle, 0, 0, FWidth, FHeight, FDC, 0, 0, SRCCOPY or $40000000);
  FFullBmp.Canvas.Unlock;
  ReleaseDC(0, FDC);
  SetRect(FRect, 0, 0, FWidth, FHeight);
  FmsSend.Clear;
  FmsSend.WriteBuffer(FRect, SizeOf(TRect));
  FmsScr.clear;
  FFullBmp.SaveToStream(FmsScr);

  //LZ4CompressStream(FmsScr,FmsSend,90);
  if not SendData(FIRSTSCREEN) then
  begin
		postmessage(mainfrmHandle,WM_STATEMESSAGE,errSpySend,getLastError());
  end;
end;


procedure TScreenSpy.GetNext;
var
  p1, p2: PDWORD;
  i, j, k: Integer;
begin
  FDC := GetDC(0);
  i := FLine;
  k := -1;
  while (i < FHeight) do
  begin
    FLineBmp.Canvas.Lock;
    BitBlt(FLineBmp.Canvas.Handle, 0, 0, FWidth, 1, FDC, 0, i, SRCCOPY or $40000000);
    FLineBmp.Canvas.Unlock;
    p1 := FFullBmp.ScanLine[i];
    p2 := FLineBmp.ScanLine[0];
    FRect.Right := 0;
    j := 0;
    while (j < FWidth) do
    begin
      if (p1^ <> p2^) then
      begin
        if (FRect.Right < 1) then FRect.Left := j - OFF_SET;
        FRect.Right := j + OFF_SET;
      end;
      Inc(p1);
      Inc(p2);
      Inc(j, FIncSize);
    end;
    if (FRect.Right > 0) then 
    begin
      if (k = i) then
        FRect.Top := i
      else
        FRect.Top := i - DEF_STEP;
      k := i + DEF_STEP;
      FRect.Bottom := k;
      SendRect;
    end;
    Inc(i, DEF_STEP);
  end;
  ReleaseDC(0, FDC);
  FLine := (FLine + 3) mod DEF_STEP;
end;
function Max(A, B: Integer): Integer;
begin
  if A > B then
    Result := A
  else
    Result := B;
end;

function Min(A, B: Integer): Integer;
begin
  if A < B then
    Result := A
  else
    Result := B;
end;
procedure TScreenSpy.SendRect;
begin
  with FRect do
  begin
    Left   := Max(Left, 0);
    Top    := Max(Top, 0);
    Right  := Min(Right, FWidth);
    Bottom := Min(Bottom, FHeight);
  end;
  CopyRect(FRect);
  if not SendData(NEXTSCREEN) then
  begin
    postmessage(mainfrmHandle,WM_STATEMESSAGE,errSpySend,getLastError());
  end;
end;

procedure TScreenSpy.CopyRect(rt: TRect);
begin
  //FFullBmp.Canvas.Lock;
  FRectBmp.Canvas.Lock;
  try
    FRectBmp.Width  := rt.Right  - rt.Left;
    FRectBmp.Height := rt.Bottom - rt.Top;
    //BitBlt(FFullBmp.Canvas.Handle, rt.Left, rt.Top, FRectBmp.Width, FRectBmp.Height, FDC, rt.Left, rt.Top, SRCCOPY or $40000000);
    BitBlt(FRectBmp.Canvas.Handle, 0, 0, FRectBmp.Width, FRectBmp.Height, FFullBmp.Canvas.Handle, rt.Left, rt.Top, SRCCOPY or $40000000);
    FmsSend.clear;
    FmsScr.clear;
    FRectBmp.SaveToStream(FmsScr);
    FmsSend.WriteBuffer(FRect, SizeOf(TRect));
    //LZ4CompressStream(FmsScr,FmsSend,90);
  finally
    //FFullBmp.Canvas.Unlock;
    FRectBmp.Canvas.Unlock;
  end;
end;

function TScreenSpy.SendData(nCmd: Byte): Boolean;
var
	i,j:integer;
begin
  try
    FCmd.Cmd := nCmd;
    FCmd.X := FmsSend.Size;
		if nCmd=FIRSTSCREEN then
		begin
			FCmd.Y := getColorDepth;
		end;
    i:=send(FSocket,FCmd, SizeOf(TCtlCmd),0);
    if (i<1) then
    begin
    	closesocket(FSocket);
    	FSocket:=-1;
    	isConnected:=false;
    	result:=false;
    	exit;
    end;
    FmsSend.Position := 0;
    i:=send(FSocket,FmsSend.Memory^, FmsSend.Size,0);
    if i<1 then
    begin
    	closesocket(FSocket);
    	FSocket:=-1;
    	isConnected:=false;
    	result:=false;
    	exit;
    end
    else
    begin
    	j:=i;
    	while (j<FmsSend.Size) do
    	begin
    		//FmsSend.position:=j-1;換成以下
    		FmsSend.position:=j;
		    i:=send(FSocket,FmsSend.Memory^, FmsSend.Size-j,0);
		    if i<1 then
		    begin
		    	closesocket(FSocket);
		    	FSocket:=-1;
		    	isConnected:=false;
		    	result:=false;
		    	exit;
		    end;
		    j:=j+i;
	  	end;
  	end;
    Result := True;
  except
    Result := False;
  end;
end;
function TScreenSpy.getColorDepth():integer;
var
	h: HDC;
	//Bits: integer ;
begin
	h := GetDC(0);
	result := GetDeviceCaps(h, BITSPIXEL);
	ReleaseDC(0, h);
end;
//另外用directX 的方法:
//procedure CaptureScreen(AFileName: string);
//const
//  CAPTUREBLT = $40000000;
//var
//  hdcScreen: HDC;
//  hdcCompatible: HDC;
//  bmp: TBitmap;
//  hbmScreen: HBITMAP;
//begin
//  hdcScreen := CreateDC('DISPLAY', nil, nil, nil);
//  hdcCompatible := CreateCompatibleDC(hdcScreen);
//  hbmScreen := CreateCompatibleBitmap(hdcScreen,
//    GetDeviceCaps(hdcScreen, HORZRES),
//    GetDeviceCaps(hdcScreen, VERTRES));
//  SelectObject(hdcCompatible, hbmScreen);
//  bmp := TBitmap.Create;
//  bmp.Handle := hbmScreen;
//  BitBlt(hdcCompatible,
//    0, 0,
//    bmp.Width, bmp.Height,
//    hdcScreen,
//    0, 0,
//    SRCCOPY or CAPTUREBLT);
//
//  bmp.SaveToFile(AFileName);
//  bmp.Free;
//  DeleteDC(hdcScreen);
//  DeleteDC(hdcCompatible);
//end;
//
//DX Primary Surface截圖代碼!包含DX8與DX9兩個版本
//
//...
//interface
//
//{$DEFINE D3D9}
//
//uses
//  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
//  Dialogs, StdCtrls, Buttons,
//{$IFDEF D3D9}
//  // D3DX9, // use D3D to save surface
//  Direct3D9
//{$ELSE}
//  // D3DX8, // use D3D to save surface
//  Direct3D8
//{$ENDIF};
//...
//procedure TForm1.BitBtn1Click(Sender: TObject);
//// Capture screen through D3D.
//var
//  BitsPerPixel: Byte;
//  {$IFDEF D3D9}
//  pD3D: IDirect3D9;
//  pSurface: IDirect3DSurface9;
//  g_pD3DDevice: IDirect3DDevice9;
//  {$ELSE}
//  pD3D: IDirect3D8;
//  pSurface: IDirect3DSurface8;
//  g_pD3DDevice: IDirect3DDevice8;
//  {$ENDIF}
//  D3DPP: TD3DPresentParameters;
//  ARect: TRect;
//  LockedRect: TD3DLockedRect;
//  BMP: TBitmap;
//  i, p: Integer;
//begin
//  BitsPerPixel := GetDeviceCaps(Canvas.Handle, BITSPIXEL);
//  FillChar(d3dpp, SizeOf(d3dpp), 0);
//  D3DPP.Windowed := True;
//  D3DPP.Flags := D3DPRESENTFLAG_LOCKABLE_BACKBUFFER;
//  D3DPP.SwapEffect := D3DSWAPEFFECT_DISCARD;
//  D3DPP.BackBufferWidth := Screen.Width;
//  D3DPP.BackBufferHeight := Screen.Height;
//  D3DPP.BackBufferFormat := D3DFMT_X8R8G8B8;
//  {$IFDEF D3D9}
//  pD3D := Direct3DCreate9(D3D_SDK_VERSION);
//  pD3D.CreateDevice(D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, GetDesktopWindow,
//    D3DCREATE_SOFTWARE_VERTEXPROCESSING, @D3DPP, g_pD3DDevice);
//  g_pD3DDevice.CreateOffscreenPlainSurface(Screen.Width, Screen.Height, D3DFMT_A8R8G8B8, D3DPOOL_SCRATCH, pSurface, nil);
//  g_pD3DDevice.GetFrontBufferData(0, pSurface);
//  {$ELSE}
//  pD3D := Direct3DCreate8(D3D_SDK_VERSION);
//  pD3D.CreateDevice(D3DADAPTER_DEFAULT, D3DDEVTYPE_REF, GetDesktopWindow,
//    D3DCREATE_SOFTWARE_VERTEXPROCESSING, D3DPP, g_pD3DDevice);
//  g_pD3DDevice.CreateImageSurface(Screen.Width, Screen.Height, D3DFMT_A8R8G8B8, pSurface);
//  g_pD3DDevice.GetFrontBuffer(pSurface);
//  {$ENDIF}
//  // use D3D to save surface. Notes: D3DX%ab.dll is required!
////  D3DXSaveSurfaceToFile('Desktop.bmp', D3DXIFF_BMP, pSurface, nil,  nil);
//  // use Bitmap to save surface
//  ARect := Screen.DesktopRect;
//  pSurface.LockRect(LockedRect, @ARect, D3DLOCK_NO_DIRTY_UPDATE or D3DLOCK_NOSYSLOCK or D3DLOCK_READONLY);
//  BMP := TBitmap.Create;
//  BMP.Width := Screen.Width;
//  BMP.Height := Screen.Height;
//  case BitsPerPixel of
//    8:  BMP.PixelFormat := pf8bit;
//    16: BMP.PixelFormat := pf16bit;
//    24: BMP.PixelFormat := pf24bit;
//    32: BMP.PixelFormat := pf32bit;
//  end;
//  p := Cardinal(LockedRect.pBits);
//  for i := 0 to Screen.Height - 1 do
//    begin
//      CopyMemory(BMP.ScanLine[i], Ptr(p), Screen.Width * BitsPerPixel div 8);
//      p := p + LockedRect.Pitch;
//    end;
//  BMP.SaveToFile('Desktop.bmp');
//  BMP.Free;
//  pSurface.UnlockRect;
//end;
end.
