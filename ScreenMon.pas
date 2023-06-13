unit ScreenMon;

interface

uses
   Windows, Classes, SysUtils, Graphics, Math,ZLibEx,AtermisClient,ServerThread,atermisWorker,AICEncoder,syncobjs;
const
  FrameCountAfterFullShot=20;

  DEF_STEP = 19;
  OFF_SET  = 32;
type
  TScreenMon = class(TThread)
  private
    
    FBmp1, FBmp2, FBmp3: Graphics.TBitmap;
		cBMP1, cBMP2, cBMP3: HBITMAP;
    FWidth, FHeight, FLine, FInc, debugcount: Integer;
    FRects: array[0..8] of TRect;
		FRect:TRect;
    FDC: HDC;
		isWaiting:boolean;
    FCursor: HCURSOR;
    FCurPos: TPoint;
    //
    mEvent:TEventObject;
    FPixelFormat: TPixelFormat;
    procedure SetPixelFormat(Value: TPixelFormat);
    function getColorDepth():integer;
    procedure SaveRect(rt: TRect);
    procedure SendRect;
    procedure CopyRect(rt: TRect);
  protected
	  aFullFrame:integer;
		function compress(nCmd: Byte):integer;
		procedure Execute; override;
  public
	  Fms1, FmsOut: TMemoryStream;
		idataType:integer;
    atermisserver:TCPServerThread;
    aclient:TAtermisClient;
    constructor Create(xw,yh:integer); reintroduce;
    destructor Destroy; override;
    procedure GetFullshot;
    procedure GetPartshot;
    function GetNext:integer;
    function CheckScr: Boolean;
		procedure sendFullShot(idx:integer);
		function setScreen(nW, nH: Integer): Boolean;
  end;

implementation

function TScreenMon.getColorDepth():integer;
var
	h: HDC;
	//Bits: integer ;
begin
	h := GetDC(0);
	result := GetDeviceCaps(h, BITSPIXEL);
	{case Bits of
	1: ShowMessage('Monochrome');
	4: ShowMessage('16 color');
	8: ShowMessage('256 color');
	16: ShowMessage('16-bit color');
	24: ShowMessage('24-bit color');
	end ;}
	ReleaseDC(0, h);
end;
procedure TScreenMon.SetPixelFormat(Value: TPixelFormat);
begin
  FPixelFormat := Value;
  case FPixelFormat of
    pf1bit:  FInc := 32;
    pf4bit:  FInc := 8;
    pf8bit:  FInc := 4;
    pf16bit: FInc := 2;
    pf32bit: FInc := 1;
    else
      FPixelFormat := pf8bit;
      FInc := 4;
  end;
end;
constructor TScreenMon.Create(xw,yh:integer);
begin
  inherited Create(true);
  Fms1  := TMemoryStream.Create;
  FmsOut  := TMemoryStream.Create;
	SetPixelFormat(TPixelFormat(getColorDepth()));//set FInc and FPixelFormat
  FBmp1 := Graphics.TBitmap.Create;
  FBmp2 := Graphics.TBitmap.Create;
  FBmp3 := Graphics.TBitmap.Create;
	FBmp1.PixelFormat := pf32bit;
	FBmp2.PixelFormat := pf32bit;
	FBmp3.PixelFormat := pf32bit;
  FInc := 1;
  FWidth  := 0;
  FHeight := 0;
	aFullFrame:=0;
  FCursor := LoadCursor(0, IDC_ARROW);
	setScreen(xw,yh);
	debugcount:=0;
	mEvent := TEventObject.Create(nil,true,false,'');
end;
procedure TScreenMon.sendFullShot(idx:integer);
begin
  GetFullshot;
	if isWaiting then
    mEvent.SetEvent;
  if idx=-1 then
  begin
    aclient.sendScreen(idataType,FmsOut.Memory, FmsOut.Size );
  end
  else
  begin
    atermisserver.workers[idx].sendScreen(idataType,FmsOut.Memory, FmsOut.Size );
  end;
end;
procedure TScreenMon.Execute;
var
  i,j:integer;
begin
  while (not Terminated) do
  begin
    if {(aFullFrame=0) or} (CheckScr) then
  	begin
  	  aFullFrame:=FrameCountAfterFullShot;
  		GetFullshot;
  	end
  	else
  	begin
  	  dec(aFullFrame);
  		//GetPartshot;
      j:=getNext;
    	if j=0 then
    	begin
    	  isWaiting:=true;
        mEvent.WaitFor(INFINITE);
        mEvent.ResetEvent;
    	end;
  	end;
    Sleep(30);
		//break;
  end;
end;
destructor TScreenMon.Destroy;
begin
  mEvent.SetEvent;
  Fms1.Free;
  FmsOut.Free;
  //FBmp3.Free;
  FBmp1.Free;
  FBmp2.Free;
	//mEvent.free;
  inherited;
end;

function TScreenMon.setScreen(nW, nH: Integer): Boolean;

begin
  Result := False;
  //nW := GetSystemMetrics(SM_CXSCREEN);
  //nH := GetSystemMetrics(SM_CYSCREEN);
  if (nW <> FWidth) or (nH <> FHeight) then
  begin
    FLine   := 0;
    FWidth  := nW;
    FHeight := nH;
    FBmp1.Width  := FWidth;
    FBmp1.Height := FHeight;
    FBmp2.Width  := FWidth;
    FBmp2.Height := 1;
    Result := True;
  end;
end;
function TScreenMon.CheckScr: Boolean;
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
    FBmp1.Width  := FWidth;
    FBmp1.Height := FHeight;
    FBmp2.Width  := FWidth;
    FBmp2.Height := 1;
    FBmp1.PixelFormat := FPixelFormat;
    FBmp2.PixelFormat := FPixelFormat;
    FBmp3.PixelFormat := FPixelFormat;
    FLine  := 0;
    Result := True;
  end;
end;

//https://forum.lazarus.freepascal.org/index.php?topic=24350.0
//https://stackoverflow.com/questions/23165308/how-to-use-bitblt-in-linux
//https://forum.lazarus.freepascal.org/index.php/topic,37034.0.html
//https://wiki.lazarus.freepascal.org/Developing_with_Graphics#Taking_a_screenshot_of_the_screen
procedure TScreenMon.GetFullshot;
begin
  //GetCursorPos(FCurPos);
  FDC := GetDC(0);//GetDC(0);
	try
  	//FBmp1.SetSize(FWidth, FHeight);
		//cBMP1 := CreateCompatibleBitmap(FDC, FWidth, FHeight);
  	//FBmp1.Handle:=cBMP1;
    //BitBlt(FBmp1.Canvas.Handle, 0, 0, FWidth, FHeight, FDC, 0, 0, SRCCOPY or $40000000);
    FLine:=0;
		FBmp1.LoadFromDevice(FDC);
    //DrawIcon(FBmp1.Canvas.Handle, FCurPos.X - 10, FCurPos.Y - 10, FCursor);

	finally
    ReleaseDC(0, FDC);
		//DeleteObject(cBMP1);
	end;
  Fms1.Clear;
	//FBmp1.SaveToFile('cap1.bmp');
  //debugcount:=debugcount+1;
  compress(21);
end;
//這個才是對的
//https://forum.lazarus.freepascal.org/index.php?topic=44714.0
//A Lazarus Keylogger- PSLogger
//https://norfolkinfosec.com/a-lazarus-keylogger-pslogger/
//https://forum.lazarus.freepascal.org/index.php?topic=37034.0    --Topic: Capturing a specific part of the screen
//https://forum.lazarus.freepascal.org/index.php?topic=27896.0
//https://stackoverflow.com/questions/13583451/how-to-use-scanline-property-for-24-bit-bitmaps

//以 Lazarus 實作取代 TBitmap.ScanLine 處理方式
//https://blog.xuite.net/james.chou408/twblog/135743141-%E4%BB%A5+Lazarus+%E5%AF%A6%E4%BD%9C%E5%8F%96%E4%BB%A3+TBitmap.ScanLine+%E8%99%95%E7%90%86%E6%96%B9%E5%BC%8F
//https://wiki.lazarus.freepascal.org/Developing_with_Graphics
{procedure TScreenMon.GetPartshot;
var
  p1, p2: PDWORD;
  i, j: Integer;
  rt: TRect;
begin
  for i := 0 to 8 do SetRectEmpty(FRects[i]);
  FDC := GetDC(GetDesktopWindow);//GetDC(0);
  i := FLine;
  while (i < FHeight) do
  begin
    //FBmp2.Canvas.Lock;
    BitBlt(FBmp2.Canvas.Handle, 0, 0, FWidth, 1, FDC, 0, i, SRCCOPY);
    //FBmp2.Canvas.Unlock;
    p1 := FBmp1.ScanLine[i];
    p2 := FBmp2.ScanLine[0];
    rt.Right := 0;
    j := 0;
    while (j < FWidth) do
    begin
      if (p1^ = p2^) then
      begin
        Inc(p1);
        Inc(p2);
        Inc(j, FInc);
        Continue;
      end;
      with rt do
      begin
        Left   := Max(j - 32, 0);
        Top    := Max(i - 19, 0);
        Right  := Min(j + 32, FWidth);
        Bottom := Min(i + 19, FHeight);
      end;
      SaveRect(rt);
      Inc(p1, 32 div FInc);
      Inc(p2, 32 div FInc);
      Inc(j, 32);
    end;
    Inc(i, 19);
  end;
  FLine := (FLine + 3) mod 19;
  SendRect;
  ReleaseDC(0, FDC);
end;}

{


To convert 8bit [0 - 255] value into 3bit [0, 7], the 0 is not a problem, but remember 255 should be converted to 7, so the formula should be Red3 = Red8 * 7 / 255.

To convert 24bit color into 8bit,

8bit Color = (Red * 7 / 255) << 5 + (Green * 7 / 255) << 2 + (Blue * 3 / 255)

To reverse,

Red   = (Color >> 5) * 255 / 7
Green = ((Color >> 2) & 0x07) * 255 / 7
Blue  = (Color & 0x03) * 255 / 3

https://www.codeproject.com/Questions/1077234/How-to-convert-a-bit-rgb-to-bit-rgb
bit number 23 22 21 20 19 18 17 16 15 14 13 12 11 10  9  8  7  6  5  4  3  2  1  0
           b7 b6 b5 b4 b3 b2 b1 b0 g7 g6 g5 g4 g3 g2 g1 g0 r7 r6 r5 r4 r3 r2 r1 r0

bit number  7  6  5  4  3  2  1  0
           B1 B0 G2 G1 G0 R2 R1 R0


Then
     B1 = b7, B0 = b6
     G2 = g7, G1 = g6, G0 = g5
     R2 = r7, r1 = r6, r0 = r5

that is

     b = (rgb >> 16) & 0xFF;
     g = (rgb >> 8) & 0xFF;
     r = rgb & 0xFF;

     B = b >> 6;
     G = g >> 5;
     R = r >> 5;

     RGB = (B << 6) | ( G << 3 ) | R;
}
//cpu 13%
procedure TScreenMon.GetPartshot;
var
  i,j,k,hasleftpoint,lastpoint,incsize,pixelpos,ppos,bottomline:integer;
  p1,p2,p3:pbyte;
  pixel1,pixel2:uint32;
begin
  FDC := GetDC(GetDesktopWindow);
  i := 0;

  //FBmp2.SetSize(FWidth, FHeight);
  //BitBlt(FBmp2.Canvas.Handle, 0, 0, FWidth, FHeight, FDC, 0, 0, SRCCOPY or $40000000);
  //FBmp2.Canvas.Changed;
  FBmp2.LoadFromDevice(FDC);
  ReleaseDC(GetDesktopWindow, FDC);
  incsize:=PIXELFORMAT_BPP[FBmp2.PixelFormat] div 8;
  while i < FBmp1.Height do
  begin
    p1:=FBmp1.ScanLine[i];
    p2:=FBmp2.ScanLine[i];
    j:=0;
    pixelpos:=0;
    hasleftpoint:=0;
    pixel1:=0;
    pixel2:=0;
    while j<FBmp1.Width*incsize do
    begin
      move(p1[j],pixel1,3);
      move(p2[j],pixel2,3);
      if (pixel1<>pixel2) then
      begin
        if (hasleftpoint=0) then
        begin
          FRect.Left:=pixelpos;
          FRect.top:=i;
          hasleftpoint:=1;
        end
        else
        begin
          FRect.Right:=pixelpos+1;
          ppos:=j;
          FRect.Bottom:=i;
          hasleftpoint:=2;
        end;
      end;
      inc(j,incsize);
      inc(pixelpos);
    end;
    lastpoint:=0;
    //孤點,
    //1. X 軸 可能為實三角形的下一行的點，需要extend 上一個 PRECT ? ，也有可能真的只有一個點啊，也可能是一條直線
    //   出現孤點前，一定有一個窄長方型的RECT?
    //2. Y 軸，空三角形的點，往下可以找得到的，因為三角形一定有底，但用現在檢測方式則會出事，但也有只有兩點變的情況，例如在畫畫
    if hasleftpoint=1 then
    begin
      FRect.Right:=FRect.Left+32;
      FRect.Bottom:=i;
      hasleftpoint:=2;
    end;
    if hasleftpoint=2 then
    begin
      bottomline:=i;
      while bottomline>FBmp1.Height do
      begin
         inc(bottomline,1);
         p1:=FBmp1.ScanLine[bottomline];
         p2:=FBmp2.ScanLine[bottomline];
         move(p1[ppos],pixel1,3);
         move(p2[ppos],pixel2,3);
         if pixel1=pixel2 then
         begin
            //move(p1[result.Left+1],pixel1,3);
            //move(p2[result.Left+1],pixel2,3);
            //if pixel1=pixel2 then
            //begin
              FRect.Bottom:=bottomline;
              lastpoint:=bottomline;
              break;
            //end;
         end;
        
      end;
      //if (lastpoint=0) or (FRect.Height<4) then
      //begin
      //   FRect.Bottom:=FRect.top+8;
      //end;
      //調整大小
      if FRect.Left>32 then
          FRect.Left  :=FRect.Left-32;
      if FRect.Right<FWidth-32 then
          FRect.Right :=FRect.Right+32;
      if FRect.Bottom<FHeight-19 then
          FRect.Bottom:=FRect.Bottom+19;
      //start copy rect to send out FBmp3
      FBmp3 := Graphics.TBitmap.Create;
      FBmp3.SetSize(FRect.Width,FRect.Height);
      FBmp3.PixelFormat:=FBmp2.PixelFormat;
      //手動法 work 不用80MS
      try
        FBmp3.BeginUpdate(false);
        FBmp1.BeginUpdate(false);
        j:=0;
        for k:=FRect.top to FRect.Bottom-1 do
        begin
          p1:=FBmp2.ScanLine[k];
          p2:=FBmp3.ScanLine[j];
          p3:=FBmp1.ScanLine[k];
          move(p1[FRect.Left*3],p2^,FRect.Width*3);
          move(p1[FRect.Left*3],p3[FRect.Left*3],FRect.Width*3);
          inc(j);
        end;
      
      except
         on e: Exception do
         begin
           bottomline:=j;
           bottomline:=FBmp3.Width;
           bottomline:=FBmp3.Height;
         end;
      end;
      FBmp3.EndUpdate(false);
      FBmp1.EndUpdate(false);
      //stat send out to network
      {//zlib version
      Fms1.clear;
      Fms1.WriteBuffer(FRect, SizeOf(TRect));
      FBmp3.SaveToStream(Fms1);
      }
      compress(22);
      FBmp3.free;
      //break;
    end;
    inc(i);
  end;
end;
//CPU 6%
{
procedure TScreenMon.GetNext;
var
  p1, p2: PDWORD;
  i, j, k: Integer;
begin
  FDC := GetDC(GetDesktopWindow);
  i := FLine;
  k := -1;
  FBmp2.SetSize(FWidth, 1);
  while (i < FHeight) do
  begin
    BitBlt(FBmp2.Canvas.Handle, 0, 0, FWidth, 1, FDC, 0, i, SRCCOPY);
    FBmp2.Canvas.Changed;
    p1 := FBmp1.ScanLine[i];
    p2 := FBmp2.ScanLine[0];
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
      Inc(j, FInc);
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
  ReleaseDC(GetDesktopWindow, FDC);
  FLine := (FLine + 3) mod DEF_STEP;
end;
终于找到BMP的原始像素的储存地址了，相对于scanline，我更愿意用一层循环去完成像素的转换...

procedure fpGrayscale2(const Bitmap: TBitmap; YuvConvert: boolean);
var
  PRGB: pRGBTriple;
  size, y, x, gray: integer;
begin
  Bitmap.BeginUpdate(); //beginupdate和endupdate必须要加在lazarus上才会生效，在delphi下则不需要，奇了个怪 ^_^
  try
    PRGB := pRGBTriple(Bitmap.RawImage.Data);
    size := Bitmap.RawImage.DataSize div 3;
    if (YuvConvert) then
    begin
      for y := 0 to size - 1 do
      begin
        gray := (77 * PRGB^.rgbtRed + 151 * PRGB^.rgbtGreen + 28 *
          PRGB^.rgbtBlue) shr 8;
        PRGB^.rgbtRed := Gray;
        PRGB^.rgbtGreen := Gray;
        PRGB^.rgbtBlue := Gray;
        Inc(PRGB);
      end;
    end
    else
    begin
      for y := 0 to size - 1 do
      begin
        gray := (PRGB^.rgbtRed + PRGB^.rgbtGreen + PRGB^.rgbtBlue) div 3;
        PRGB^.rgbtRed := Gray;
        PRGB^.rgbtGreen := Gray;
        PRGB^.rgbtBlue := Gray;
        Inc(PRGB);
      end;
    end;
  finally
      Bitmap.EndUpdate();
  end;
end;
因为直接对内存中的像素操作，所以转换速度非常快。
由于pRGBTriple只针对24bit的BMP，所以调用前记得先检测下 bitamp的对象是否24bit位图。。。
}
function bintoHex(bin:pbyte;lens:integer): String;
const HexSymbols = '0123456789ABCDEF';
var i: integer;
begin
  SetLength(Result, 2*lens);
  for i :=  0 to lens-1 do 
	begin
    Result[1 + 2*i + 0] := HexSymbols[1 + bin[i] shr 4];
    Result[1 + 2*i + 1] := HexSymbols[1 + bin[i] and $0F];
  end;
end;
//https://wiki.freepascal.org/Fast_direct_pixel_access
//-- ScanLine 加了 BeginUpdate,EndUpdate 也不保證一定會對，依然空白的情況
//-- FBmp3 始終有對有不對
//https://wiki.freepascal.org/Developing_with_Graphics
//https://wiki.freepascal.org/Accessing_the_Interfaces_directly
function TScreenMon.GetNext:integer;
var
  p1, p2,p3: PDWORD;
  i, j, k, incX, bottomline: Integer;
	irow:integer;
	f:textfile;
begin
  FDC := GetDC(0);
  i := FLine;
  k := -1;
	result:=-1;
  FBmp2.LoadFromDevice(FDC);
  ReleaseDC(0, FDC);
	//FBmp2.savetoFile('cap2.bmp');
	FInc:=PIXELFORMAT_BPP[FBmp2.PixelFormat] div 8;
	incX:= FInc div 4;
	bottomline:=0;
	FBmp1.BeginUpdate();
  FBmp2.BeginUpdate();
	p1:=PDWORD(FBmp1.RawImage.Data);
	p2:=PDWORD(FBmp2.RawImage.Data);
  while (i < FHeight) do
  begin
    FRect.Right := 0;
    j := 0;
		irow:=i*FWidth;
    while (j < FWidth) do
    begin
      if (p1[irow+j] <> p2[irow+j]) then
      begin
        if (FRect.Right < 1) then
        begin
          FRect.Left := j - OFF_SET;
					//AssignFile(f,'imgdump.txt');
					//rewrite(f);
					//Writeln(f,bintoHex(@p1[irow],FWidth*FInc)); 
					//Writeln(f,bintoHex(@p2[irow],FWidth*FInc));
					//CloseFile(f); 
        end;
        FRect.Right := j + OFF_SET;
      end;
      Inc(j, incX);
    end;
    if (FRect.Right > 0) then
    begin
		  inc(bottomline);
      if (k = i) then
        FRect.Top := i
      else
        FRect.Top := i - DEF_STEP;
      k := i + DEF_STEP;
      FRect.Bottom := k;
      with FRect do
      begin
        Left   := Max(Left, 0);
        Top    := Max(Top, 0);
        Right  := Min(Right, FWidth);
        Bottom := Min(Bottom, FHeight);
      end;
      //start copy rect to send out FBmp3
      FBmp3 := Graphics.TBitmap.Create;
      FBmp3.SetSize(FRect.Width,FRect.Height);
      FBmp3.PixelFormat:=FBmp2.PixelFormat;
      //CPU 壓在4%了
      try
        j:=0;
				FBmp3.BeginUpdate();
				p3:=PDWORD(FBmp3.RawImage.Data);
        for k:=FRect.top to FRect.Bottom-1 do
        begin
          move(p2[k*FWidth+FRect.Left],p3[j*FRect.Width],FRect.Width*FInc);
					move(p2[k*FWidth+FRect.Left],p1[k*FWidth+FRect.Left],FRect.Width*FInc);
          inc(j);
        end;
      
      except
         on e: Exception do
         begin
           bottomline:=j;
           bottomline:=FBmp3.Width;
           bottomline:=FBmp3.Height;
         end;
      end;
      FBmp3.EndUpdate();
      result:=compress(22);
			//FBmp3.savetoFile('cap3'+IntToStr(bottomline)+'-'+IntToStr(FRect.Left)+','+IntToStr(FRect.Top)+'-'+IntToStr(FRect.Width)+','+IntToStr(FRect.Height)+'.bmp');
      FBmp3.free;
    end;
    Inc(i, DEF_STEP);
  end;
  FBmp2.EndUpdate();
	FBmp1.EndUpdate();
  FLine := (FLine + 3) mod DEF_STEP;
	//FBmp1.savetoFile('cap3.bmp');
	//FBmp1.assign(FBmp2);//奇怪, 用MOVE 的方式無效?? 用這個會好些，但也是怪怪的
end;
{
procedure TScreenMon.GetNext;
var
  p1, p2,p3, p11,p12: PDWORD;
  i, j, k, incX, bottomline: Integer;
	f:textfile;
begin
  FDC := GetDC(GetDesktopWindow);
  i := FLine;
  k := -1;
  FBmp2.LoadFromDevice(FDC);
  ReleaseDC(GetDesktopWindow, FDC);
	FBmp2.savetoFile('cap2.bmp');
	FInc:=PIXELFORMAT_BPP[FBmp2.PixelFormat] div 8;
	incX:= FInc div 4;
	bottomline:=0;
	FBmp1.BeginUpdate();
  FBmp2.BeginUpdate();
  while (i < FHeight) do
  begin
    p1 := FBmp1.ScanLine[i];
    p2 := FBmp2.ScanLine[i];
    FRect.Right := 0;
    j := 0;
    while (j < FWidth) do
    begin
      if (p1[j] <> p2[j]) then
      begin
        if (FRect.Right < 1) then
        begin
          FRect.Left := j - OFF_SET;
					AssignFile(f,'imgdump.txt');
					rewrite(f);
					Write(f,bintoHex(@p1[0],FWidth)); 
					Write(f,bintoHex(@p2[0],FWidth));
					CloseFile(f); 
        end;
        FRect.Right := j + OFF_SET;
      end;
      Inc(j, incX);
    end;
    if (FRect.Right > 0) then
    begin
		  inc(bottomline);
      if (k = i) then
        FRect.Top := i
      else
        FRect.Top := i - DEF_STEP;
      k := i + DEF_STEP;
      FRect.Bottom := k;
      with FRect do
      begin
        Left   := Max(Left, 0);
        Top    := Max(Top, 0);
        Right  := Min(Right, FWidth);
        Bottom := Min(Bottom, FHeight);
      end;
      //start copy rect to send out FBmp3
      FBmp3 := Graphics.TBitmap.Create;
      FBmp3.SetSize(FRect.Width,FRect.Height);
      FBmp3.PixelFormat:=FBmp2.PixelFormat;
      //CPU 壓在4%了
      try
        j:=0;
				FBmp3.BeginUpdate();
        for k:=FRect.top to FRect.Bottom-1 do
        begin
          p11:=FBmp2.ScanLine[k];
          p12:=FBmp3.ScanLine[j];
					p3:=FBmp1.ScanLine[k];
          move(p11[FRect.Left*FInc],p12^,FRect.Width*FInc);
					move(p11[FRect.Left*FInc],p3[FRect.Left*FInc],FRect.Width*FInc);
          inc(j);
        end;
      
      except
         on e: Exception do
         begin
           bottomline:=j;
           bottomline:=FBmp3.Width;
           bottomline:=FBmp3.Height;
         end;
      end;
      FBmp3.EndUpdate();
      compress(22);
			FBmp3.savetoFile('cap3'+IntToStr(bottomline)+'-'+IntToStr(FRect.Left)+','+IntToStr(FRect.Top)+'-'+IntToStr(FRect.Width)+','+IntToStr(FRect.Height)+'.bmp');
      FBmp3.free;
    end;
    Inc(i, DEF_STEP);
  end;
  FBmp2.EndUpdate();
	FBmp1.EndUpdate();
  FLine := (FLine + 3) mod DEF_STEP;
	FBmp1.savetoFile('cap3.bmp');
	//FBmp1.assign(FBmp2);//奇怪, 用MOVE 的方式無效?? 用這個會好些，但也是怪怪的
end;
}
{procedure TScreenMon.GetPartshot;
var
  p1, p2: PDWORD;
  i, j, k: Integer;
begin
  FDC := GetDC(GetDesktopWindow);
  i := FLine;
  k := -1;
  FBmp2.SetSize(FWidth, 1);
	cBMP2 := CreateCompatibleBitmap(FDC, FWidth, 1);
	FBmp2.Handle:=cBMP2;

  while (i < FHeight) do
  begin
    FBmp2.Canvas.Lock;
    BitBlt(FBmp2.Canvas.Handle, 0, 0, FWidth, 1, FDC, 0, i, SRCCOPY or $40000000);
    FBmp2.Canvas.Unlock;
    p1 := FBmp1.ScanLine[i];
    p2 := FBmp2.ScanLine[0];
    FRect.Right := 0;
    j := 0;
    while (j < FWidth) do
    begin
      if (p1^ <> p2^) then
      begin
        if (FRect.Right < 1) then 
				  FRect.Left := j - OFF_SET;
        FRect.Right := j + OFF_SET;
      end;
      Inc(p1);
      Inc(p2);
      Inc(j, FInc);
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
  ReleaseDC(GetDesktopWindow, FDC);
	DeleteObject(cBMP2);
  FLine := (FLine + 3) mod DEF_STEP;
end;
}
{
procedure TScreenMon.SendRect;
var
  i: Integer;
  pt: TPoint;
  rt: TRect;
begin
  FmsOut.Clear;
  for i := 0 to 8 do
  begin
    if (FRects[i].Right = 0) then Continue;
    with FRects[i] do
    begin
      Left   := Max(Left, 0);
      Top    := Max(Top,  0);
      Right  := Min(Right,  FWidth);
      Bottom := Min(Bottom, FHeight);
    end;
    //FBmp1.Canvas.Lock;
    //FBmp3.Canvas.Lock;
    try
      FBmp3.Width  := FRects[i].Right  - FRects[i].Left;
      FBmp3.Height := FRects[i].Bottom - FRects[i].Top;
      BitBlt(FBmp3.Canvas.Handle, 0, 0, FBmp3.Width, FBmp3.Height, FDC, FRects[i].Left, FRects[i].Top, SRCCOPY);
			FBmp3.Canvas.Changed;
      BitBlt(FBmp1.Canvas.Handle, FRects[i].Left, FRects[i].Top, FBmp3.Width, FBmp3.Height, FBmp3.Canvas.Handle, 0, 0, SRCCOPY);
			FBmp1.Canvas.Changed;
      Fms1.WriteBuffer(FRects[i], SizeOf(TRect));
      FBmp3.SaveToStream(Fms1);
    finally
      //FBmp1.Canvas.Unlock;
      //FBmp3.Canvas.Unlock;
    end;
  end;
  GetCursorPos(pt);
  if (not PointsEqual(pt, FCurPos)) or (Fms1.Size > 0) then
  begin
    FBmp3.Width  := 32;
    FBmp3.Height := 32;
    SetRect(rt, FCurPos.X - 10, FCurPos.Y - 10, FCurPos.X + 22 , FCurPos.Y + 22);
    BitBlt(FBmp3.Canvas.Handle, 0, 0, FBmp3.Width, FBmp3.Height, FBmp1.Canvas.Handle, rt.Left, rt.Top, SRCCOPY);
		FBmp3.Canvas.Changed;
    Fms1.WriteBuffer(rt, SizeOf(rt));
    FBmp3.SaveToStream(Fms1);
    FCurPos := pt;
    SetRect(rt, FCurPos.X - 10, FCurPos.Y - 10, FCurPos.X + 22 , FCurPos.Y + 22);
    BitBlt(FBmp3.Canvas.Handle, 0, 0, FBmp3.Width, FBmp3.Height, FBmp1.Canvas.Handle, rt.Left, rt.Top, SRCCOPY);
		FBmp3.Canvas.Changed;
    DrawIcon(FBmp3.Canvas.Handle, 0, 0, FCursor);
    Fms1.WriteBuffer(rt, SizeOf(rt));
    FBmp3.SaveToStream(Fms1);
  end;
  if (Fms1.Size > 0) then 
	 compress(22);
end;
}
procedure TScreenMon.SaveRect(rt: TRect);
var
  i, j: Integer;
  rt3: TRect;
  nt: array[0..8] of Integer;
begin
  for i := 0 to 8 do
  begin
    if (FRects[i].Right <> 0) then
    begin
      if (FRects[i].Left - rt.Right > 32) or (rt.Left - FRects[i].Right > 32) or (FRects[i].Top - rt.Bottom > 38) or (rt.Top - FRects[i].Bottom > 38) then
        Continue
      else
      begin
        SetRect(FRects[i], Min(FRects[i].Left, rt.Left), Min(FRects[i].Top, rt.Top), Max(FRects[i].Right, rt.Right), Max(FRects[i].Bottom, rt.Bottom));
        Exit;
      end;
    end;
  end;
  for i := 0 to 8 do
  begin
    if (FRects[i].Right <> 0) then
    begin
      SetRect(rt3, Min(FRects[i].Left, rt.Left), Min(FRects[i].Top, rt.Top), Max(FRects[i].Right, rt.Right), Max(FRects[i].Bottom, rt.Bottom));
      j := ((rt3.Right - rt3.Left) * (rt3.Bottom - rt3.Top) - (FRects[i].Right - FRects[i].Left) * (FRects[i].Bottom - FRects[i].Top) - (rt.Right - rt.Left) * (rt.Bottom - rt.Top)) * 4 div FInc;
      if (j < 8000) then
      begin
        FRects[i] := rt;
        Exit;
      end;
      nt[i] := j;
    end;
  end;
  for i := 0 to 8 do
  begin
    if (FRects[i].Right = 0) then
    begin
      FRects[i] := rt;
      Exit;
    end;
  end;  
  i := 0;
  for j := 1 to 8 do
  begin
    if (nt[j] < nt[i]) then i := j;
  end;
  SetRect(FRects[i], Min(FRects[i].Left, rt.Left), Min(FRects[i].Top, rt.Top), Max(FRects[i].Right, rt.Right), Max(FRects[i].Bottom, rt.Bottom));
end;
procedure TScreenMon.SendRect;
begin
  with FRect do
  begin
    Left   := Max(Left, 0);
    Top    := Max(Top, 0);
    Right  := Min(Right, FWidth);
    Bottom := Min(Bottom, FHeight);
  end;
  CopyRect(FRect);
end;
procedure TScreenMon.CopyRect(rt: TRect);
begin
  
  try
    FBmp3.Width  := rt.Right  - rt.Left;
    FBmp3.Height := rt.Bottom - rt.Top;
		BitBlt(FBmp1.Canvas.Handle, rt.Left, rt.Top, FBmp3.Width, FBmp3.Height, FDC, rt.Left, rt.Top, SRCCOPY);
		FBmp1.Canvas.changed;
    BitBlt(FBmp3.Canvas.Handle, 0, 0, FBmp3.Width, FBmp3.Height, FDC, rt.Left, rt.Top, SRCCOPY);
		FBmp3.Canvas.changed;
    Fms1.clear;
		Fms1.WriteBuffer(rt, SizeOf(TRect));
    FBmp3.SaveToStream(Fms1);
    compress(22);
  finally

  end;
end;


function TScreenMon.compress(nCmd: Byte):integer;
var
  jpg:TJpegImage;
	enc:TAICEncoder;
	i,j:integer;
begin
  try
    FmsOut.Clear;
    Fms1.Position := 0;
		
    jpg:=TJpegImage.Create;
    jpg.CompressionQuality:=90;
    if nCmd=21 then
    begin
      jpg.Assign(FBmp1);
			//enc:=TAICEncoder.Create(FBmp1,FmsOut,90);//全黑，加了BEGINUPDATE 也一樣，且CPU使用率比JPG 高2%
    end
    else
    begin
		  FmsOut.WriteBuffer(FRect, SizeOf(TRect));
      jpg.Assign(FBmp3);
			//enc:=TAICEncoder.Create(FBmp3,FmsOut,90);
    end;
    jpg.SaveToStream(FmsOut);
    
    //enc.free;
    //ZCompressStream(Fms1, FmsOut);
		//FmsOut.SaveToFile('out.bin');
    FmsOut.Position := 0;
		idataType:=nCmd;
    j:=0;
    for i:=0 to length(atermisserver.workers)-1 do
    begin
      if atermisserver.workers[i].needScreen then
      begin
        if atermisserver.workers[i].sendScreen(idataType,FmsOut.Memory, FmsOut.Size )>0 then
        begin
           inc(j);
				end;
      end;
    end;

    if (aclient<>nil) then
    begin
      if aclient.sendScreen(idataType,FmsOut.Memory, FmsOut.Size )>0 then
      begin
        inc(j);
			end;
    end;
  except
  end;
	result:=j;

  Fms1.Clear;
  jpg.Free;

end;

end.
