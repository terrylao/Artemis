unit mainform;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  MouseAndKeyInput, ScreenMon, ZLibEx,  Grids, Buttons,
  Windows, iphlpapi, AtermisClient, ServerThread, atermisWorker, Messages,
  Clipbrd, ComCtrls, frmView;
const
   BOOKNAME='artemisv2.book';
{
點GRID,點GETVIEW-->起一個VIEW WINDOWS-->起一個CLIENT THREAD-->CALL MAINTHREAD DRAW 圖片 <--> 起SERVER THREAD -->MAINTHREAD --> SEND 桌面
點GRID,點SENDVIEW <--> 起SERVER THREAD -->MAINTHREAD -->起一個VIEW WINDOWS --> SERVER THREAD RECV 桌面 -->MAINTHREADDRAW 圖片
}
type

  { TfrmMain }
  TfrmMain = class(TForm)
    btnGetView: TButton;
    btnSendView: TButton;
    btnStartServer: TButton;
    btnStopServer: TButton;
    btnVoice: TSpeedButton;
    btnVoice1: TSpeedButton;
    cmbbind: TComboBox;
    edtport: TEdit;
    edtserverpasswd: TEdit;
    Memo1: TMemo;
    PageControl1: TPageControl;
    Panel2: TPanel;
    stgHost: TStringGrid;
    stgServer: TStringGrid;
    TabSheet1: TTabSheet;
    TabSheet2: TTabSheet;
    procedure btnGetViewClick(Sender: TObject);
    procedure btnSendViewClick(Sender: TObject);
    procedure btnStartServerClick(Sender: TObject);
    procedure btnStopServerClick(Sender: TObject);
    procedure btnVoiceClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure stgHostClick(Sender: TObject);

  private
    screenAtermisIndex,count,curhostrow,clientcount:integer;
    mms:TMemoryStream;
    screenshot,FBmp1:Graphics.TBitmap;
    FRect:TRECT;
    atermisserver:TCPServerThread;

    clientSendScreen,Closing:boolean;
    view:TViewForm;
    scr:TScreenMon;
    FNextClipboardOwner: HWnd;   // handle to the next viewer
    // Here are the clipboard event handlers
    function WMChangeCBChain(AwParam: WParam; AlParam: LParam):LRESULT;
    function WMDrawClipboard(AwParam: WParam; AlParam: LParam):LRESULT;
    procedure OnEndSession(Sender: TObject);
    procedure OnQueryendSession(var Cancel: Boolean);
    procedure RetrieveLocalAdapterInformation;
    procedure ShowScreen(eventid,idx: integer);
    procedure RemoveScreen(idx: integer);
    procedure GetScreenshot;
    procedure removeClient(idx:integer);
    procedure removeServer(idx:integer);
    procedure ServerNewConnect(sip,sport:string;idx:integer);
  public

  end;

var
  frmMain: TfrmMain;
  PrevWndProc:windows.WNDPROC;
implementation
uses Process ;
function WndCallback(Ahwnd: HWND; uMsg: UINT; wParam: WParam;
  lParam: LParam): LRESULT; stdcall;
begin
  if uMsg = WM_CHANGECBCHAIN then begin
    Result := frmMain.WMChangeCBChain(wParam, lParam);
    Exit;
  end
  else if uMsg=WM_DRAWCLIPBOARD then begin
    Result := frmMain.WMDrawClipboard(wParam, lParam);
    Exit;
  end;
  Result := CallWindowProc(PrevWndProc, Ahwnd, uMsg, WParam, LParam);
end;
{$R *.lfm}

{ TfrmMain }
procedure TfrmMain.GetScreenshot;
{$IFDEF LINUX}
var
  ScreenDC: HDC;
begin
  ScreenDC := GetDC(0);
  Mypic.LoadFromDevice(ScreenDC);
  ReleaseDC(0,ScreenDC);
end;
{$ENDIF}
{$IFDEF WINDOWS}
var
  screenDC: HDC;
  shiftLeft,shiftTop,i:integer;
begin
  screenDC:=GetDC(GetDesktopWindow);//和原本不同，奇怪
  try
         screenshot.SetSize(Screen.DesktopWidth, Screen.DesktopHeight);
         screenshot.LoadFromDevice(screenDC);

  finally
    ReleaseDC(0, screenDC);
  end;
end;
{$ENDIF}
procedure TfrmMain.OnEndSession(Sender: TObject);
begin
  //do something
  close;
end;

procedure TfrmMain.OnQueryendSession(var Cancel: Boolean);
begin
  //do something
  close;
end;
procedure TfrmMain.RemoveScreen(idx: integer);
begin
     stgHost.Objects[5,idx]:=nil;
end;

//將VIEW 的控制丟回去VIEW FROM 中
procedure TfrmMain.ShowScreen(eventid,idx: integer);
var
  i,upanddown,mousescroll,mousex,mousey:integer;
  akey:word;
  sstate:TShiftState;
  mouseclicked:TMouseButton;
  mymms:TmemoryStream;
  jpg:TJpegImage;
begin
  if Closing then
     exit;
  case eventid of
    -1:
    begin
      if idx<0 then
      begin
        stgHost.Cells[4,stgHost.Row]:='L:disconnected';
      end
      else
      begin
        stgServer.Cells[4,idx+1]:='End';
        stgServer.Cells[1,idx+1]:='';
        stgServer.Cells[2,idx+1]:='';
        stgServer.Cells[3,idx+1]:='';
      end;

    end;
    10:
    begin
      if  atermisserver.workers[idx].islogined then
      begin
        if atermisserver.workers[idx].passwd<>edtserverpasswd.Text then
        begin
           atermisserver.workers[idx].islogined:=false;
        end
        else
        begin
          memo1.Lines.Append('a logined');
          stgServer.Cells[4,idx+1]:='Login';
          stgServer.Cells[1,idx+1]:=atermisserver.workers[idx].remoteip;
          stgServer.Cells[2,idx+1]:=atermisserver.workers[idx].remoteport;
          count:=0;
        end;
      end;
    end;
    20:
    begin
      screenAtermisIndex:=idx;
      //timer1.Enabled:=true;
      if scr=nil then
      begin
         scr:=TScreenMon.Create(Screen.DesktopWidth,Screen.DesktopHeight);
         scr.atermisserver:=atermisserver;
         scr.sendFullShot(idx);
         scr.Start;
      end
      else
      begin
        //if stop, restart it
        scr.sendFullShot(idx);
      end;
      {scr.GetFullshot;
      if atermisserver.workers[idx].sendScreen(scr.idataType,scr.FmsOut.Memory, scr.FmsOut.Size )<=0 then
      begin
           atermisserver.workers[idx].disconnect();
           exit;
      end;}
      atermisserver.workers[idx].needScreen:=true;

    end;
    21:
    begin
      //show image
      if view=nil then
      begin
         view:=TViewForm.Create(self);
         view.DoubleBuffered:=true;
         view.aclient:=TAtermisClient(stgHost.Objects[5,curhostrow]);
         view.Show;
      end;
      jpg:=TJpegImage.Create;
      if idx<0 then //1. 讀取對的來源，並判定是否要SHOW, 2. WORKER 們如何FREE和NIL
      begin
         //mymms:=aclient.mmsout;
         jpg.LoadFromStream(TAtermisClient(stgHost.Objects[5,curhostrow]).mmsin);
        //mymms:=aclient.mmsin;
      end
      else
      begin
         //mymms:=atermisserver.workers[idx].mmsout;
         jpg.LoadFromStream(atermisserver.workers[idx].mmsin);
        //mymms:=atermisserver.workers[idx].mmsin;
      end;

      //FBmp1.LoadFromStream(mymms);
      FBmp1.Assign(jpg);
      jpg.free;

      view.PaintBox1.Height :=FBmp1.Height;
      view.PaintBox1.Width:=FBmp1.Width;
      view.FBmp1.SetSize(FBmp1.Width,FBmp1.Height);;
      view.FBmp1.Canvas.Draw(0,0,FBmp1);
      FRect.Left:=0;
      FRect.top:=0;
      FRect.Width:=FBmp1.Width;
      FRect.Height:=FBmp1.Height;
      view.FRect:=FRect;
      view.paintaction:=21;
      view.Caption:='21';
      view.PaintBox1.Invalidate;
    end;
    22:
    begin
      if idx<0 then
         mymms:=TAtermisClient(stgHost.Objects[5,curhostrow]).mmsin//mmsouy
      else
         mymms:=atermisserver.workers[idx].mmsin;//mmsout

      while (mymms.Position < mymms.Size) do
      begin
        mymms.Read(FRect, SizeOf(TRect));
        {with FBmp1 do
        begin
          Width  := FRect.Right  - FRect.Left;
          Height := FRect.Bottom - FRect.Top;
          LoadFromStream(mymms);
        end;}
        jpg:=TJpegImage.Create;
        jpg.LoadFromStream(mymms);
        FBmp1.Assign(jpg);
        jpg.free;

        {dec.Expand(mymms,FBmp1);}
        if view=nil then
           exit;
        inc(count);
        view.FBmp1.Canvas.Draw(FRect.Left,FRect.Top,FBmp1);
        //view.FBmp1.Canvas.Changed;
        view.paintaction:=22;
        view.Caption:='22:left='+inttostr(FRect.Left)+',top='+inttostr(FRect.Top)+',width='+inttostr(FRect.Width)+',height='+inttostr(FRect.Height);
        //FBmp1.savetoFile('Clientcap3'+IntToStr(count)+'-'+IntToStr(FRect.Left)+','+IntToStr(FRect.Top)+'-'+IntToStr(FRect.Width)+','+IntToStr(FRect.Height)+'.bmp');
        //view.FBmp1.savetoFile('view'+IntToStr(count)+'-'+IntToStr(FRect.Left)+','+IntToStr(FRect.Top)+'-'+IntToStr(FRect.Width)+','+IntToStr(FRect.Height)+'.bmp');
        view.PaintBox1.Invalidate;
      end;
    end;
    50:
    begin
      if idx<0 then
      begin

      end
      else
      begin
          stgHost.Cells[3,idx+1]:=atermisserver.workers[idx].sDownloadFileName;
      end;
    end;
    51,53:
    begin
      //draw file processing too ?
       if idx<0 then
       begin
          i:=TAtermisClient(stgHost.Objects[5,curhostrow]).filepercent;
          stgHost.Cells[4,stgHost.Row]:='F:'+IntToStr(i);
       end
       else
       begin
           i:=atermisserver.workers[idx].filepercent;
           stgHost.Cells[4,idx+1]:='F:'+IntToStr(i);
       end;

    end;
    54:
    begin
       if idx<0 then
          i:=TAtermisClient(stgHost.Objects[5,curhostrow]).remoteErrCode
       else
           i:=atermisserver.workers[idx].remoteErrCode;
       case i of
         -101:
         begin

         end;
         -102:
         begin

         end;
       end;
    end;
    70:
    begin
      if idx<0 then
      begin
        mousex:=TAtermisClient(stgHost.Objects[5,curhostrow]).mousex;
        mousey:=TAtermisClient(stgHost.Objects[5,curhostrow]).mousey;
      end
      else
      begin
        mousex:=atermisserver.workers[idx].mousex;
        mousey:=atermisserver.workers[idx].mousey;
      end;
      MouseAndKeyInput.MouseInput.Move([],mousex,mousey);
    end;
    71:
    begin
      //memo1.Lines.Append('mouse click:'+inttostr(idx));
      if idx<0 then
      begin
        mousescroll:=TAtermisClient(stgHost.Objects[5,curhostrow]).mousescroll;
        mousex:=TAtermisClient(stgHost.Objects[5,curhostrow]).mousex;
        mousey:=TAtermisClient(stgHost.Objects[5,curhostrow]).mousey;
        sstate:=TAtermisClient(stgHost.Objects[5,curhostrow]).sstate;
        upanddown:=TAtermisClient(stgHost.Objects[5,curhostrow]).upanddown;
        mouseclicked:=TAtermisClient(stgHost.Objects[5,curhostrow]).mouseclicked;
      end
      else
      begin
        mousescroll:=atermisserver.workers[idx].mousescroll;
        mousex:=atermisserver.workers[idx].mousex;
        mousey:=atermisserver.workers[idx].mousey;
        sstate:=atermisserver.workers[idx].sstate;
        upanddown:=atermisserver.workers[idx].upanddown;
        mouseclicked:=atermisserver.workers[idx].mouseclicked;
      end;

      if mousescroll=2 then
      begin
        MouseAndKeyInput.MouseInput.ScrollDown(sstate);
      end
      else
      begin
        MouseAndKeyInput.MouseInput.ScrollUp(sstate);
      end;
      if upanddown=2 then
      begin
        MouseAndKeyInput.MouseInput.Down(mouseclicked,sstate,mousex,mousey);
        //memo1.Lines.Append('mouse down');
      end
      else
      begin
        MouseAndKeyInput.MouseInput.up(mouseclicked,sstate,mousex,mousey);
        //memo1.Lines.Append('mouse up');
      end;
    end;
    80:
    begin
      if idx<0 then
      begin
        sstate:=TAtermisClient(stgHost.Objects[5,curhostrow]).sstate;
        akey:=TAtermisClient(stgHost.Objects[5,curhostrow]).akey;
        upanddown:=TAtermisClient(stgHost.Objects[5,curhostrow]).upanddown;
      end
      else
      begin
        sstate:=atermisserver.workers[idx].sstate;
        akey:=atermisserver.workers[idx].akey;
        upanddown:=atermisserver.workers[idx].upanddown;
      end;

      if upanddown=2 then
      begin
        MouseAndKeyInput.KeyInput.Apply(sstate);
        MouseAndKeyInput.KeyInput.Down(akey);
      end
      else
      begin
        MouseAndKeyInput.KeyInput.Up(akey);
	MouseAndKeyInput.KeyInput.Unapply(sstate);
      end;
    end;
  end;
end;
procedure TfrmMain.RetrieveLocalAdapterInformation;
var
  pAdapterInfo: PIP_ADAPTER_INFO;
  AdapterInfo: IP_ADAPTER_INFO ;
  BufLen: DWORD;
  Status: DWORD;
  strMAC: String;
  i: Integer;
  anyaddressed:boolean;
  strings: TStrings;
begin
  strings:= Tstringlist.create;
  strings.Clear;

  BufLen:= sizeof(AdapterInfo);
  pAdapterInfo:= @AdapterInfo;

  Status:= GetAdaptersInfo(nil, BufLen);
  pAdapterInfo:= AllocMem(BufLen);
  try
    Status:= GetAdaptersInfo(pAdapterInfo, BufLen);

    if (Status <> ERROR_SUCCESS) then
      begin
        case Status of
          ERROR_NOT_SUPPORTED:
            strings.Add('GetAdaptersInfo is not supported by the operating ' +
                        'system running on the local computer.');
          ERROR_NO_DATA:
            strings.Add('No network adapter on the local computer.');
        else
            strings.Add('GetAdaptersInfo failed with error #' + IntToStr(Status));
        end;
        Dispose(pAdapterInfo);
        Exit;
      end;
    anyaddressed:=false;
    while (pAdapterInfo <> nil) do
      begin
      //memo1.Lines.Add('');
      //   memo1.Lines.Add('Description: ------------------------' + pAdapterInfo^.Description);
      //   memo1.Lines.Add('Name: ' + pAdapterInfo^.AdapterName);

        strMAC := '';
        for I := 0 to pAdapterInfo^.AddressLength - 1 do
            strMAC := strMAC + '-' + IntToHex(pAdapterInfo^.Address[I], 2);

        Delete(strMAC, 1, 1);
         //memo1.Lines.Add('MAC address: ' + strMAC);
         //memo1.Lines.Add('IP address: ' + pAdapterInfo^.IpAddressList.IpAddress.S);
         if (not anyaddressed) and (strpas(pAdapterInfo^.IpAddressList.IpAddress.S)='0.0.0.0') then
         begin
            //anyaddressed:=true;
            //cmbbind.items.Append(pAdapterInfo^.IpAddressList.IpAddress.S);
         end
         else
             cmbbind.items.Append(pAdapterInfo^.IpAddressList.IpAddress.S);
         //memo1.Lines.Add('IP subnet mask: ' + pAdapterInfo^.IpAddressList.IpMask.S);
         //memo1.Lines.Add('Gateway: ' + pAdapterInfo^.GatewayList.IpAddress.S);
         //memo1.Lines.Add('DHCP enabled: ' + IntTOStr(pAdapterInfo^.DhcpEnabled));
         //memo1.Lines.Add('DHCP: ' + pAdapterInfo^.DhcpServer.IpAddress.S);
         //memo1.Lines.Add('Have WINS: ' + BoolToStr(pAdapterInfo^.HaveWins,True));
         //memo1.Lines.Add('Primary WINS: ' + pAdapterInfo^.PrimaryWinsServer.IpAddress.S);
         //memo1.Lines.Add('Secondary WINS: ' + pAdapterInfo^.SecondaryWinsServer.IpAddress.S);

        pAdapterInfo:= pAdapterInfo^.Next;
    end;
  finally
    Dispose(pAdapterInfo);
    strings.free;
  end;
end;

function GetIpAddrList(): string;
var
  AProcess: TProcess;
  s: string;
  sl: TStringList;
  i, n: integer;

begin
  Result:='';
  sl:=TStringList.Create();
  {$IFDEF WINDOWS}
  AProcess:=TProcess.Create(nil);
  AProcess.CommandLine := 'ipconfig.exe';
  AProcess.Options := AProcess.Options + [poUsePipes, poNoConsole];
  try
    AProcess.Execute();
    Sleep(500); // poWaitOnExit not working as expected
    sl.LoadFromStream(AProcess.Output);
  finally
    AProcess.Free();
  end;
  for i:=0 to sl.Count-1 do
  begin
    if (Pos('IPv4', sl[i])=0) and (Pos('IP-', sl[i])=0) and (Pos('IP Address', sl[i])=0) then Continue;
    s:=sl[i];
    s:=Trim(Copy(s, Pos(':', s)+1, 999));
    if Pos(':', s)>0 then Continue; // IPv6
    Result:=Result+s+'  ';
  end;
  {$ENDIF}
  {$IFDEF UNIX}
  AProcess:=TProcess.Create(nil);
  AProcess.CommandLine := '/sbin/ifconfig';
  AProcess.Options := AProcess.Options + [poUsePipes, poWaitOnExit];
  try
    AProcess.Execute();
    //Sleep(500); // poWaitOnExit not working as expected
    sl.LoadFromStream(AProcess.Output);
  finally
    AProcess.Free();
  end;

  for i:=0 to sl.Count-1 do
  begin
    n:=Pos('inet addr:', sl[i]);
    if n=0 then Continue;
    s:=sl[i];
    s:=Copy(s, n+Length('inet addr:'), 999);
    Result:=Result+Trim(Copy(s, 1, Pos(' ', s)))+'  ';
  end;
  {$ENDIF}
  sl.Free();
end;
procedure TfrmMain.btnGetViewClick(Sender: TObject);
var
  aclient:TAtermisClient;
begin
  aclient:=nil;
  if (trim(stgHost.Cells[1,stgHost.Row])='') and (trim(stgHost.Cells[2,stgHost.Row])='') then
  begin
     exit;
  end;
  IF aclient=nil then
     aclient:=TAtermisClient.Create(true,'client.log');
  aclient.gridindx:=stgHost.Row;
  aclient.atermisidx:=-1*stgHost.Row;
  stgHost.Objects[5,stgHost.Row]:=aclient;
  if aclient.ConnectTo(stgHost.Cells[1,stgHost.Row],strtoint(stgHost.Cells[2,stgHost.Row]),5 )<0 then
  //if aclient.ConnectTo('127.0.0.1',8803,5 )<0 then
  begin
     memo1.Lines.Append('connect to '+stgHost.Cells[1,stgHost.Row]+':'+stgHost.Cells[2,stgHost.Row]+' fail');
     aclient.Free;
     aclient:=nil;
     exit;
  end;
  memo1.Lines.Append('connect to '+stgHost.Cells[1,stgHost.Row]+':'+stgHost.Cells[2,stgHost.Row]+' success');
  if aclient.sendLogin(trim(stgHost.Cells[3,stgHost.Row]))<0 then
  begin
     memo1.Lines.Append('get login fail');
     aclient.Free;
     aclient:=nil;
     exit;
  end;
  memo1.Lines.Append('get login success');
  if aclient.sendGetScreen()<0 then
  begin
     memo1.Lines.Append('get screen fail');
     aclient.Free;
     aclient:=nil;
     exit;
  end;
  memo1.Lines.Append('get screen success');
  aclient.OnShowScreen:=@ShowScreen;
  aclient.OnRemove:=@removeClient;
  aclient.Start;
  curhostrow:=stgHost.Row;
  inc(clientcount);
end;

procedure TfrmMain.btnSendViewClick(Sender: TObject);
var
  aclient:TAtermisClient;
begin
  aclient:=nil;
  if (trim(stgHost.Cells[1,stgHost.Row])='') and (trim(stgHost.Cells[2,stgHost.Row])='') then
  begin

     exit;
  end;
  IF aclient=nil then
     aclient:=TAtermisClient.Create(true,'client.log');
  aclient.gridindx:=stgHost.Row;
  aclient.atermisidx:=-1*stgHost.Row;
  stgHost.Objects[5,stgHost.Row]:=aclient;
  if aclient.ConnectTo(stgHost.Cells[1,stgHost.Row],strtoint(stgHost.Cells[2,stgHost.Row]),5 )<0 then
  //if aclient.ConnectTo('127.0.0.1',8803,5 )<0 then
  begin
     memo1.Lines.Append('connect to '+stgHost.Cells[1,stgHost.Row]+':'+stgHost.Cells[2,stgHost.Row]+' fail');
     aclient.Free;
     exit;
  end;
  memo1.Lines.Append('connect to '+stgHost.Cells[1,stgHost.Row]+':'+stgHost.Cells[2,stgHost.Row]+' success');
  if aclient.sendLogin(trim(stgHost.Cells[3,stgHost.Row]))<0 then
  begin
     memo1.Lines.Append('get login fail');
     aclient.Free;
     exit;
  end;
  memo1.Lines.Append('send login success');
  if aclient.sendRecvScreen() <0 then
  begin
     memo1.Lines.Append('send screen fail');
     aclient.Free;
     exit;
  end;
  memo1.Lines.Append('send screen success');
  if scr=nil then
  begin
     scr:=TScreenMon.Create(Screen.DesktopWidth,Screen.DesktopHeight);
     scr.atermisserver:=atermisserver;
     scr.aclient:=aclient;
     scr.sendFullShot(-1);
     scr.Start;
  end
  else
  begin
    scr.aclient:=aclient;
    scr.sendFullShot(-1);
  end;
  clientSendScreen:=true;
  aclient.OnShowScreen:=@ShowScreen;
  //aclient.Start;
  curhostrow:=stgHost.Row;
end;

procedure TfrmMain.btnStartServerClick(Sender: TObject);
var
  i:integer;
begin
  if not assigned(atermisserver) then
     atermisserver:=TCPServerThread.Create(true,5);
  if atermisserver.bindto(cmbbind.Text ,strtoint(edtPort.text))<0 then
  begin
    memo1.Lines.Append('Server Bind Fail');
    exit;
  end;
  memo1.Lines.Append('Server Bind at:'+cmbbind.Text+':'+edtPort.text);
  for i:=0 to 4 do
  begin
       atermisserver.workers[i].OnShowScreen:=@ShowScreen;
       atermisserver.workers[i].OnRemove:=@removeServer;
       atermisserver.workers[i].OnNewConnect:=@ServerNewConnect;
       atermisserver.workers[i].gridindx:=i+1;
  end;
  atermisserver.Start;
  btnStopServer.Enabled:=true;
  btnStartServer.Enabled:=false;
  PageControl1.PageIndex:=1;
end;

procedure TfrmMain.btnStopServerClick(Sender: TObject);
begin
     if not assigned(atermisserver) then
        atermisserver.doTerminate;
end;

procedure TfrmMain.btnVoiceClick(Sender: TObject);
begin

end;

procedure TfrmMain.FormClose(Sender: TObject; var CloseAction: TCloseAction);
var
  i:integer;
begin
  Closing:=true;
  sleep(50);
  for i:=1 to stgHost.RowCount-1 do
      stgHost.Cells[4,i]:='';
  stgHost.SaveToCSVFile(BOOKNAME);

  //if aclient<>nil then
  //   aclient.doterminate();
  if atermisserver<>nil then
  begin
     atermisserver.doTerminate;
     //while atermisserver.CheckTerminated do;
     //atermisserver.Free;
  end;
  screenshot.free;
  Fbmp1.Free;
  mms.Free;
  if scr<>nil then
     scr.Free;
  ChangeClipboardChain(Handle, FNextClipboardOwner);
end;

procedure TfrmMain.FormCreate(Sender: TObject);
begin
     screenshot:=Graphics.TBitmap.Create;
     FBmp1:=Graphics.TBitmap.Create;
     screenAtermisIndex:=-1;
     clientSendScreen:=false;
     Closing:=false;
     clientcount:=0;
      screenshot.SetSize(Screen.DesktopWidth, Screen.DesktopHeight);
      mms:=TMemoryStream.create;
      RetrieveLocalAdapterInformation;
      PrevWndProc := Windows.WNDPROC(SetWindowLongPtr(Self.Handle, GWL_WNDPROC, PtrUInt(@WndCallback)));
      FNextClipboardOwner := SetClipboardViewer(Self.Handle);
      view:=nil;
      scr:=nil;
      Application.OnEndSession := @OnEndSession;
      Application.OnQueryEndSession := @OnQueryendSession;
      stgHost.LoadFromCSVFile(BOOKNAME);
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin

end;

procedure TfrmMain.stgHostClick(Sender: TObject);
begin
  if (stgHost.Objects[5,stgHost.Row]<>nil) and (curhostrow<>stgHost.Row) then
  begin
    if TAtermisClient(stgHost.Objects[5,curhostrow]).sendStopScreen()<0 then
    begin
      TAtermisClient(stgHost.Objects[5,curhostrow]).disconnect();
      //TAtermisClient(stgHost.Objects[5,curhostrow]).Free;
       stgHost.Objects[5,stgHost.Row]:=nil;
       stgHost.Cells[4,stgHost.Row]:='Disconnected';
    end;
    if TAtermisClient(stgHost.Objects[5,stgHost.Row]).sendGetScreen()<0 then
    begin
      TAtermisClient(stgHost.Objects[5,stgHost.Row]).disconnect();
      //TAtermisClient(stgHost.Objects[5,stgHost.Row]).Free;
       stgHost.Objects[5,stgHost.Row]:=nil;
       stgHost.Cells[4,stgHost.Row]:='Disconnected';
    end;
    curhostrow:=stgHost.Row;
    exit;
  end;
  IF stgHost.Objects[5,stgHost.Row]<>nil then
  begin
    view.aclient:=TAtermisClient(stgHost.Objects[5,stgHost.Row]);
  end;
  curhostrow:=stgHost.Row;
end;

function TfrmMain.WMChangeCBChain(AwParam: WParam; AlParam: LParam): LRESULT;
var
  Remove, NextHandle: THandle;
begin
  Remove := AwParam;
  NextHandle := AlParam;
  if FNextClipboardOwner = Remove then
     FNextClipboardOwner := NextHandle
  else
  if FNextClipboardOwner <> 0 then
      SendMessage(FNextClipboardOwner, WM_ChangeCBChain, Remove, NextHandle) ;
  Result := 0;
end;

function TfrmMain.WMDrawClipboard(AwParam: WParam; AlParam: LParam): LRESULT;
begin
  if Clipboard.HasFormat(CF_TEXT) Then
  Begin
    //ShowMessage(Clipboard.AsText);
    if screenAtermisIndex>-1 then
       atermisserver.workers[screenAtermisIndex].sendClipboard(Clipboard.AsText);
  end;
  SendMessage(FNextClipboardOwner, WM_DRAWCLIPBOARD, 0, 0);   // VERY IMPORTANT
  Result := 0;
end;
procedure TfrmMain.removeClient(idx:integer);
var
  i,j:integer;
begin
  stgHost.Objects[5,idx]:=nil;
  stgHost.Cells[4,idx]:='Disconnected';
  clientcount:=clientcount-1;
  if clientcount=0 then
  begin
    view:=nil;
  end
  else
  begin
    i:=1;
    j:=0;
    while stgHost.Cells[1,i]<>'' do
    begin
      if stgHost.Objects[5,i]<>nil then
      begin
        curhostrow:=i;
        j:=1;
        break;
      end;
      inc(i);
    end;
    if j=1 then
    begin
      view.aclient:=TAtermisClient(stgHost.Objects[5,curhostrow]);
    end;
  end;
end;
procedure TfrmMain.removeServer(idx:integer);
begin
  stgServer.Cells[4,idx]:='Disconnected';
end;
procedure TfrmMain.ServerNewConnect(sip,sport:string;idx:integer);
begin
  stgServer.Cells[4,idx]:='Disconnected';
  stgServer.Cells[1,idx]:=sip;
  stgServer.Cells[2,idx]:=sport;
end;
end.

