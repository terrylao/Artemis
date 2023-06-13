unit protocolHandler;

{$MODE Delphi}

{
client 會發出unknow command? 我只有在動mouse 而已呢, 還是收方的問題吧?
ANS:忘了zeromemory? 答案: 不是, 原來是連12bytes 的資料都無法一次recv 收足

client 有畫面卡死的狀況, server 好像也沒再傳畫面

Bug?: when server mode, it is not response any new screen request, and do not display icon in the right down corner, and alt-tab also cannot select it
Bug: when drop file to server, the screespy do not resume?
Bug: 只收到空白畫面一張?
調整: closesocket 只在handler 上處理
結構調整:
protocolhandler 發送/接收PROTOCOL，解碼，送知MAINFORM(由CALL BACK 或 POSTMESSAGE 或 MAINTHREAD FUNCTION)
ScreenSpy(thread?)-->ProtocolHandler(thread)
MainForm --> View -->ProtocolHandler(thread)
}
interface

uses
  windows,LCLIntf, LCLType, LMessages, Messages, SysUtils, Variants, Classes, Graphics, Controls,
  ExtCtrls, ComCtrls, header,winsock,ClipBrd,
  Forms,dialogs,ScreenSpy,AudioThread, {AES,}Logger,socketfunc;
type
  TProtocolHandler = class(TThread)
		protected
			voicePort:integer;
			VoiceSvrSocket,VoiceSocket:integer;
			function encryPassword(s:String):String;
			function decryPassword(s:String):String;
			procedure Execute; override;
		private
			mytargetip:String;
			myPasswd:String;
			yFileBuf:array [0..8191] of char;
			clipboardbuf:array [0..1024*1024] of char;
			ctlCmd: array[0..SizeOf(TCtlCmd) - 1] of Byte;
			nextCmd:integer;
			FileHandle,filesizes:integer;
			client:PSockAddr;
			namelen:PInteger;
			procedure CloseSpy();
			procedure OpenSpy(pixelfmt:integer);
			function processFile(cmd:PCTLCMD):integer;
			function processVoice(cmd,x:integer):integer;
			function handleProtocol(cmd:PCtlCmd):integer;
			function SendData(cmd,x,y:integer;p:pchar):integer;
			function RecvData(x:integer):integer;
			function getColorDepth():integer;
		public
			isLogin,inVoiceMode,isSetClipboard:boolean;
			rs{,ss}:TMemoryStream;
      filefrm:integer;
			mySpy:TScreenSpy;
			myScreenHandle,mystatusMsgHandle:integer;
			rc:TAudioRecvThread;
			se:TAudioSendThread;
			isTerminated:boolean;
			mySocket,svrSocket,fileSocket,waitforMsg:integer;
			logs:TLogger;
			constructor create(socket:integer;frmHandle,statusMsgHandle:integer;passwd:String;logged:boolean;targetIP:String);
			destructor destroy();override;
			procedure StartFileTransfer();
			procedure StopFileTransfer();
			function StartLogin(passwd:String):integer;
			function StartVoice(port:integer):integer;
			function StopVoice():integer;
			function StarPassive():integer;
			procedure reinit(socket:integer;frmHandle:integer;passwd,targetIP:String);
      function waitConnection():integer;
			function sendClipboard(p:pchar;len:integer):integer;
			procedure VoiceStart(skt:integer);
			procedure VoiceTerminate();
  end;
implementation

{uses socketfunc;}
constructor TProtocolHandler.create(socket:integer;frmHandle,statusMsgHandle:integer;passwd:String;logged:boolean;targetIP:String);
begin
	client:=nil;
	namelen:=nil;
	se:=nil;
	rc:=nil;
	logs:=nil;
	voicePort:=-1;
	VoiceSvrSocket:=-1;
	VoiceSocket:=-1;
  mySocket:=-1;
  svrSocket:=-1;
	nextCmd:=0;
	FileHandle:=-1;
	myScreenHandle:=frmHandle;
	mystatusMsgHandle:=statusMsgHandle;
	myPasswd:=passwd;
	mytargetip:=targetIP;
  if targetIP='' then
    svrSocket:=socket
  else
    mySocket:=socket;
	if logged then
	begin
		logs:=TLogger.create;// (nil,'',4);
	end;
  rs := TMemoryStream.Create;
  //ss := TMemoryStream.Create;
	inherited create(true);
end;
destructor TProtocolHandler.destroy();
begin
	if client<>nil then
	begin
		dispose(client);
		dispose(namelen);
	end;
  rs.Free;
  //ss.Free;
	if logs<>nil then
		logs.free;
	CloseSpy();
	VoiceTerminate();
	inherited Destroy;
end;
function TProtocolHandler.sendClipboard(p:pchar;len:integer):integer;
begin
  if mySpy<>nil then
    mySpy.locker.Acquire;
	result:=SendData(CLIPBOARD_TRANSFER,len,0,p);
  if mySpy<>nil then
    mySpy.locker.Release;
end;
procedure TProtocolHandler.reinit(socket:integer;frmHandle:integer;passwd,targetIP:String);
begin
	voicePort:=-1;
	VoiceSvrSocket:=-1;
	VoiceSocket:=-1;
  mySocket:=-1;
  svrSocket:=-1;
	nextCmd:=0;
	FileHandle:=-1;
	mySocket:=socket;
	myScreenHandle:=frmHandle;
	myPasswd:=passwd;
	mytargetip:=targetIP;
  inVoiceMode:=false;
end;
function TProtocolHandler.waitConnection():integer;
begin
	if client=nil then
	begin
		new(client);
		new(namelen);
		namelen^:=sizeof(client^);
	end;
	result:=accept(svrSocket,client,namelen);
end;
procedure TProtocolHandler.Execute;
var
  received:Integer;
begin
  received:=1;
	isTerminated:=false;
  try
    while (not terminated) and (received>0) do
    begin
      if (svrSocket>0) and (mySocket=-1) then
			begin
				PostMessage(mystatusMsgHandle,WM_STATEMESSAGE,mtListening,0);
        isLogin:=false;
        mySocket:=waitConnection();
        if mySocket=-1 then
        begin
					PostMessage(mystatusMsgHandle,WM_STATEMESSAGE,errRecv,GetLastError);
          break;
        end;
			end;
      zeromemory(@ctlCmd[0],SizeOf(TCtlCmd));
			received:=RecvData(SizeOf(TCtlCmd));
			if received<SizeOf(TCtlCmd) then
			begin
				logs.LogError('command size not valid to '+inttostr(SizeOf(TCtlCmd))+'<>'+inttostr(received),'');
			end
			else
			begin
				move(yFileBuf,ctlCmd,SizeOf(TCtlCmd));
			end;
      //received:=recv(mySocket,ctlCmd[0],SizeOf(TCtlCmd),0);
		  if received<1 then
		  begin
			  PostMessage(mystatusMsgHandle,WM_STATEMESSAGE,errRecv,GetLastError);
				closespy;
			  closesocket(mySocket);
        mySocket:=-1;
        if svrSocket>0 then
          received:=1;
		  end
			else
			begin
				received:=handleProtocol(PctlCmd(@ctlCmd[0]));
				if received<1 then
				begin
					PostMessage(mystatusMsgHandle,WM_STATEMESSAGE,received,GetLastError);
					closespy;
					closesocket(mySocket);
					mySocket:=-1;
					if svrSocket>0 then
						received:=1;
				end;
			end;
    end;
  except
		on E: Exception do
		begin
			if logs<>nil then
			begin
				logs.LogError('Exception is :'+E.Message,'');
			end;
			closespy;
		end
  end;
  isTerminated:=true;
end;
procedure TProtocolHandler.CloseSpy;
begin
  if mySpy<>nil then
  begin
    mySpy.Terminate;
    mySpy := nil;
  end;
end;
procedure TProtocolHandler.OpenSpy(pixelfmt:integer);
begin
  if mySpy=nil then
  begin
		mySpy := TScreenSpy.Create;
		mySpy.FSocket := mySocket;
		mySpy.isConnected:=true;
		mySpy.mainfrmHandle:=myScreenHandle;
		if (getColorDepth()<pixelfmt) then
			mySpy.SetPixelFormat(TPixelFormat(pfDevice))
		else
		begin
			case pixelfmt of
				32:pixelfmt:=7;
				24:pixelfmt:=6;
				16:pixelfmt:=5;
				 8:pixelfmt:=3;
				 4:pixelfmt:=2;
				 1:pixelfmt:=1;
			end;
			mySpy.SetPixelFormat(TPixelFormat(pixelfmt));
		end;
		mySpy.Resume;
  end;
end;
//max recv 8KB Data and rerutn
function TProtocolHandler.RecvData(x:integer):integer;
var
	i,j:integer;
begin
	if x>8192 then
	begin
		result:=errExceed8K;
		exit;
	end;
	i:=recv(mySocket,yFileBuf[0],x,0);
	if i<1 then
	begin
		result:=errRecv;
		exit;
	end;
	while i<x do
	begin
    j:=x-i;
    if j>8192 then
      j:=8192;
    j:=recv(mySocket,yFileBuf[i],j,0);
    if j<1 then
    begin
      i:=errRecv;
      break;
    end;
    inc(i,j);
	end;
  result:=i;
end;
function TProtocolHandler.SendData(cmd,x,y:integer;p:pchar):integer;
var
	ctlcmd:TCtlCmd;
	i,j,k:integer;
begin
  ctlcmd.cmd:=cmd;
  ctlcmd.X:=x;
	ctlcmd.Y:=y;
	if logs<>nil then
	begin
		logs.logerror('Send CMD is :'+inttostr(cmd),'');
	end;
  if mySpy<>nil then
  begin
    mySpy.locker.Acquire;
  end;
  result:=send(mySocket,ctlcmd,SizeOf(TCtlCmd),0);
	if result=-1 then
		exit;
	if p<>nil then
	begin
    i:=0;
  	while i<x do
	  begin
			j:=x-i;
			if j>8192 then
				j:=8192;
			k:=send(mySocket,p[i],j,0);
			if k<1 then
			begin
				result:=-1;
				break;
			end;
			inc(i,k);
	  end;
	end;
  if mySpy<>nil then
  begin
    mySpy.locker.Release;
  end;
end;

procedure TProtocolHandler.StartFileTransfer();
begin
  SendData(FILETRANS_BEGIN,0,0,nil);
end;
procedure TProtocolHandler.StopFileTransfer();
begin
  SendData(FILETRANS_FINISH,0,0,nil);
end;
function TProtocolHandler.StartLogin(passwd:String):integer;
var
	s:String;
begin
	s:=encryPassword(passwd);
	result:=SendData(LOGIN,length(s),getColorDepth(),pchar(s));
end;
function TProtocolHandler.StartVoice(port:integer):integer;
begin
  voicePort:=port;
	result:=SendData(VOICE_REQUEST,port,0,nil);
  nextCmd:=VOICE_ACCEPT;
end;
function TProtocolHandler.StopVoice():integer;
begin
	result:=SendData(VOICE_CLOSE,0,0,nil);
end;
procedure TProtocolHandler.VoiceStart(skt:integer);
begin
  rc:=TAudioRecvThread.create(mystatusMsgHandle,'','');
  se:=TAudioSendThread.create(mystatusMsgHandle,'','');
  se.socketid:=skt;
  rc.socketid:=skt;
  se.Resume;
  rc.Resume;
  sleep(1000);//wait for thread message queue created
  rc.StartAudioOut;
  se.StartAudioIn;
end;
procedure TProtocolHandler.VoiceTerminate();
begin
  if se=nil then
    exit;
  StopVoice();
  se.CloseAudioIn;
  rc.CloseAudioOut;
  se.Terminate;
  rc.Terminate;
end;
function TProtocolHandler.StarPassive():integer;
begin
	result:=SendData(ACTIVE_SERVER,0,0,nil);
end;
function TProtocolHandler.decryPassword(s:String):String;
begin
  //result:=DecryptString(s, '沈睡千年清麗的臉孔', kb256);
  //result:=DecryptString(s, '097563002361392', kb256);
  result:='qq123';
end;
function TProtocolHandler.encryPassword(s:String):String;
begin
  //result:=EncryptString(s, '沈睡千年清麗的臉孔', kb256);
  //result:=EncryptString(s, '097563002361392', kb256);
  result:='qq123';
end;
{
Type
    TDevmode = record
    DW : DWORD;
    DH : DWORD;
    DV : DWORD;
    DBit : DWORD;
    end;

// 檢查我要的w,h,bit
function CheckDeviceMode(w,h,bit:Integer):Boolean;
Var
    i : Integer;
    DevMode : TDeviceMode;
begin
    i:=0;
    Result := False;
    while EnumDisplaySettings(nil,i,DevMode) do
    if (DevMode.dmPelsWidth = w) and
    (DevMode.dmPelsHeight = h) and
    (DevMode.dmBitsperPel = bit) then
    begin
    Result := True;
    Exit;
    end else inc(i);
end;

// 取得目前的 w ,h ,bit ,更新頻率
function GetDeviceMode(Hd:Hwnd):TDevmode;
Var
    dc : Cardinal;
begin
    dc := GetWindowDC(Hd);
    with Result do
    begin
    DW := GetDeviceCaps(dc, HORZRES);
    DH := GetDeviceCaps(dc, VERTRES);
    DV := GetDeviceCaps(dc, VREFRESH);
    DBit := GetDeviceCaps(dc, BITSPIXEL);
    end;
    ReleaseDC(Hd, dc);
end;

// 設定我要的 w ,h ,bit ,更新頻率
function SetDeviceMode(Dev:TDevmode):Boolean;
Var
    i : Integer;
    DevMode : TDeviceMode;
begin
    i := 0;
    Result := False;
    while EnumDisplaySettings(nil,i,DevMode) do
    if (DevMode.dmPelsWidth = Dev.DW) and
    (DevMode.dmPelsHeight = Dev.DH) and
    (DevMode.dmDisplayFrequency = Dev.DV) and
    (DevMode.dmBitsperPel = Dev.DBit) then
    begin
    ChangeDisplaySettings(DevMode,0);
    Result := True;
    Exit;
    end else inc(i);
end;
}
function TProtocolHandler.getColorDepth():integer;
var
	h: HDC;
	//Bits: integer ;
begin
	h := GetDC(0);
	result := GetDeviceCaps(h, BITSPIXEL);
	if result>16 then
		result:=16;
	{case Bits of
	1: ShowMessage('Monochrome');
	4: ShowMessage('16 color');
	8: ShowMessage('256 color');
	16: ShowMessage('16-bit color');
	24: ShowMessage('24-bit color');
	end ;}
	ReleaseDC(0, h);
end;

function TProtocolHandler.handleProtocol(cmd:PCtlCmd):integer;
var
	verifyPass,clipb:String;
	readed,i,nextSize:integer;
	ret:longbool;
  msg:TMsg;
begin
	result:=1;
	{if logs<>nil then
	begin
		if (Cmd^.Cmd>14) then
			logs.Log('command is :'+inttostr(Cmd^.Cmd)+'address is'+inttostr(integer(cmd)));
	end;}
	if not isLogin then
	begin
		case Cmd^.Cmd of
			ACTIVE_SERVER:
			begin
				PostMessage(mystatusMsgHandle, WM_DOLOGIN, 0, 0);
				//StartLogin(myPasswd);
			end;
			LOGIN_ACCEPT:
			begin
				isLogin:=true;
				PostMessage(mystatusMsgHandle, WM_STATEMESSAGE, mtLogined, 0);
				result:=sendData(START_SPY,getColorDepth(),0,nil);
			end;
			LOGIN:
			begin
				if (Cmd^.X>8192) then
				begin
					result:=-1;
					exit;
				end;
				i:=recvData(Cmd^.X);
				if i<1 then
				begin
					result:=i;
					exit;
				end;
				verifyPass:=copy(yFileBuf,0,Cmd^.X);
				verifyPass:=trim(decryPassword(verifyPass));
				//if myPasswd<>verifyPass then
				//begin
				//	result:=-1;
          //exit;
				//end;
				isLogin:=true;
				result:=sendData(LOGIN_ACCEPT,0,0,nil);
				PostMessage(mystatusMsgHandle, WM_STATEMESSAGE, mtLogined, 0);
			end
			else
			begin
				result:=errUnknowCMD;
			end;
		end;
	end
	else
	begin
		if Cmd^.Cmd in [MOUSE_MOVE..RIGHTUP] then 
			SetCursorPos(cmd^.X, cmd^.Y);
		case Cmd^.Cmd of
			START_SPY:
			begin
				openSpy(Cmd^.X);
			end;
			STOP_SPY://stop spy
			begin
				PostMessage(mystatusMsgHandle, WM_STATEMESSAGE, mtIdle, 0);
				CloseSpy;
				result:=SendData(STOP_SPY,0,0,nil);
			end;
			VOICE_REQUEST..VOICE_CLOSE://Voice Request
			begin
				result:=processVoice(cmd^.cmd,Cmd^.X);
			end;
			MOUSE_MOVE: ;//mouse move
			LEFTDOWN: mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0);
			RIGHTDOWN: mouse_event(MOUSEEVENTF_RIGHTDOWN, 0, 0, 0, 0);
			LEFTUP: mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0);
			RIGHTUP: mouse_event(MOUSEEVENTF_RIGHTUP, 0, 0, 0, 0);
			KEYB_DOWN: keybd_event(Byte(Cmd^.X), MapVirtualKey(Byte(Cmd^.X), 0), 0, 0);
			KEYB_UP: keybd_event(Byte(Cmd^.X), MapVirtualKey(Byte(Cmd^.X), 0), KEYEVENTF_KEYUP, 0);
			CLIPBOARD_TRANSFER: //ClipBoard Transfer
			begin
				readed:=0;
				i:=Cmd^.X  div 4096;
				nextSize := Cmd^.X  mod 4096;
				while (i>0) do
				begin
					result:=recvData(4096);
					if result<0 then
					begin
						exit;
					end;
					CopyMemory(@clipboardbuf[readed],@yFileBuf[0],4096);
					readed:=readed+result;
					dec(i);
				end;
				if nextSize>0 then
				begin
					result:=recvData(nextSize);
					if result<0 then
					begin
						exit;
					end;
					CopyMemory(@clipboardbuf[readed],@yFileBuf[0],result);
					readed:=readed+result;
					clipboardbuf[readed]:=#0;
				end;
				//TntClipboard.Open;
				clipb:=copy(clipboardbuf,0,Cmd^.X);
        try
					isSetClipboard:=true;
          Clipboard.AsText:=clipb;
          if logs<>nil then
			    begin
				    logs.logerror('Clipboard Received','');
			    end;
        except
          if logs<>nil then
			    begin
				    logs.logerror('Clipboard Exception is :'+IntToStr(GetLastError()),'');
			    end;
        end;
				//TntClipboard.Close;
			end;
			SUSPEND_SPY://Suspend SPY
			begin
				if assigned(mySpy) then
					mySpy.Suspend;
			end;
			RESUME_SPY://resume SPY
			begin
				if assigned(mySpy) then
					if mySpy.Suspended then
						mySpy.Resume;
			end;
			FIRSTSCREEN..NEXTSCREEN:
			begin
				rs.clear;
				readed:=0;
				rs.Position := 0;
				PostMessage(myScreenHandle,WM_STARTSCREEN,readed,Cmd^.X);
				while readed<Cmd^.X do
				begin
					if (Cmd^.x - readed) >= SizeOf(yFileBuf) then
						nextSize := SizeOf(yFileBuf)
					else
						nextSize := (Cmd^.x - Readed);
					nextsize:=recv(mySocket,yFileBuf[0],nextSize,0);
					if nextsize<1 then
					begin
						result:=errConnect;
						exit;
					end;
					rs.WriteBuffer(yFileBuf, nextsize);
					Inc(Readed, nextsize);
					PostMessage(myScreenHandle,WM_STARTSCREEN,readed,Cmd^.X);
				end;
				rs.Position := 0;
				PostMessage(myScreenHandle,WM_READSCREEN,Cmd^.Cmd,0);
				waitforMsg:=1;
				ret := GetMessage(msg,0,0,0); //( msg, FormHandle, 0, 0 );
				waitforMsg:=0;
				if not ret then
				begin
					result:=-1;
				end;
			end;
			SUSPENSCREEN:
			begin
				if myspy<>nil then
				begin
          mySpy.doSuspend;
				end;
			end;
			RESUMESCREEN:
			begin
				if mySpy<>nil then
				begin
          mySpy.doResume;
				end;
			end;
      CLOSE_SERVICE:
      begin
        closespy();
        closesocket(mySocket);
        isLogin:=false;
        mySocket:=-1;
      end;
			FILETRANS_BEGIN..FILETRANS_BREAK:
			begin
				result:=processFile(Cmd);
			end
			else
			begin
				isLogin:=false;
				closesocket(mySocket);
				mySocket:=-1;
				result:=errUnknowCMD;
				CloseSpy;
			end;
		end;//end case
	end;//end if else
	if logs<>nil then
	begin
		if (Cmd^.Cmd>14) then
			logs.Logerror('command done ','');
	end;
end;


function TProtocolHandler.processVoice(cmd,x:integer):integer;
begin
	result:=1;
	Randomize;
	case cmd of
		VOICE_REQUEST:
		begin
			if inVoiceMode then
			begin
				sendData(VOICE_REJECT,0,0,nil);
				exit;
			end;
			nextCmd:=VOICE_ACCEPT;
			inVoiceMode:=true;
			if (x=0) then
			begin
				//bind port and then send Voice accept
				VoiceSvrSocket:=-1;
				repeat
          voicePort:=9001+Random(1000);
					VoiceSvrSocket:=MakeServer('0.0.0.0',voicePort);
				until VoiceSvrSocket>0;
				result:=sendData(VOICE_ACCEPT,voicePort,0,nil);
        if result=-1 then
        begin
        end;
				result:=sendData(VOICE_READY,0,0,nil);
        if result=-1 then
        begin
        end;
				if client=nil then
				begin
					new(client);
					new(namelen);
					namelen^:=sizeof(client^);
				end;
				VoiceSocket:=accept(VoiceSvrSocket,client,namelen);
				if VoiceSocket>0 then
					VoiceStart(VoiceSocket)
				else
					PostMessage(mystatusMsgHandle, WM_STATEMESSAGE, errAcceptVoiceSocket, 0);
			end
			else
			begin
				voicePort:=x;
				result:=sendData(VOICE_ACCEPT,voicePort,0,nil);
			end;
		end;
		VOICE_ACCEPT:
		begin
			if nextCmd<>VOICE_ACCEPT then
			begin
				if voicePort=x then
				begin
					closeSocket(VoiceSvrSocket);
				end;
				inVoiceMode:=false;
				nextCmd:=0;
				voicePort:=-1;
				PostMessage(myScreenHandle, WM_UndesiredMsg, 0, 0);
				exit;
			end;
			if voicePort=x then
			begin
				VoiceSvrSocket:=MakeServer('0.0.0.0',voicePort);
				if VoiceSvrSocket>0 then
				begin
					result:=sendData(VOICE_READY,0,0,nil);
					if client=nil then
					begin
						new(client);
						new(namelen);
						namelen^:=sizeof(client^);
					end;
					VoiceSocket:=accept(VoiceSvrSocket,client,namelen);
					if VoiceSocket>0 then
						VoiceStart(VoiceSocket)
					else
						PostMessage(mystatusMsgHandle, WM_STATEMESSAGE, errAcceptVoiceSocket, 0);
				end
				else
					PostMessage(mystatusMsgHandle, WM_STATEMESSAGE, errCreateVoiceSocket, 0);
			end
			else
				voicePort:=x;
			nextCmd:=VOICE_READY;
			PostMessage(mystatusMsgHandle, WM_STATEMESSAGE, mtVoiceConnected, 0);
		end;
		VOICE_READY:
		begin
			if nextCmd<>VOICE_READY then
			begin
				closeSocket(VoiceSvrSocket);
				inVoiceMode:=false;
				voicePort:=-1;
				nextCmd:=0;
				PostMessage(myScreenHandle, WM_UndesiredMsg, 0, 0);
				exit;
			end;
			if VoiceSvrSocket=-1 then
			begin
				x:=1;
				repeat
					VoiceSocket:=ClientConnect(mytargetip,inttostr(voicePort),4,0,0);
					inc(x);
				until (VoiceSocket>-1) or (x=3);
				if (x=3) and (VoiceSocket=-1) then
				begin
					inVoiceMode:=false;
					voicePort:=-1;
					nextCmd:=0;
					PostMessage(mystatusMsgHandle, WM_STATEMESSAGE, errCreateVoiceSocket, 0);
					exit;
				end;
			end;
			VoiceStart(VoiceSocket);
		end;
		VOICE_REJECT:
		begin
			PostMessage(mystatusMsgHandle, WM_STATEMESSAGE, mtVoiceReject, 0);
		end;
		VOICE_CLOSE://Voice Close
		begin
			PostMessage(mystatusMsgHandle, WM_STATEMESSAGE, mtVoiceTerminate, 0);
		end;
	end;
end;
function TProtocolHandler.processFile(cmd:PCTLCMD):integer;
var
	seekshift,i,j:integer;
	s:String;
	sw:String;
begin
	result:=1;
	case cmd^.cmd of
		FILETRANS_BEGIN:
		begin
			if mySpy<>nil then
			begin
				mySpy.doSuspend();
			end;
			sendData(FILETRANS_ACCEPT,0,0,nil);
			nextCmd:=FILETRANS_REQUEST;
		end;
		FILETRANS_REQUEST:
		begin
			if nextCmd<>FILETRANS_REQUEST then
			begin
				exit;
			end;
			if cmd^.x>1024 then
			begin
				exit;
			end;
			i:=RecvData(cmd^.x);
	  	if i<1 then
	  	begin
				result:=i;
				exit;
	  	end;
	  	s:=copy(yFileBuf,0,Cmd^.X);
			sw:=s;
			if FileExists(sw) then
			begin
				filesizes:=WideFileSize(sw);
				if filesizes=-1 then
				begin
					sendData(FILETRANS_ERROR,errFileOpen,0,nil);
					exit;
				end;
				seekshift:=0;
				if (filesizes>=cmd^.y) then
				begin
					sendData(FILETRANS_NEXT,0,0,nil);
				end
				else
				begin
					if FileHandle<1 then
					begin
						sendData(FILETRANS_ERROR,errFileOpen,0,nil);
						exit;
					end
					else
					begin
						sendData(FILETRANS_RESUME,filesizes-4096,0,nil);
						seekshift:=cmd^.x;
						filesizes:=cmd^.y-cmd^.x;
						FileHandle:=fileopen(sw,fmOpenWrite);
					end;
				end;
				if seekshift>0 then
					result:=fileseek(FileHandle,seekshift,0);
			end
			else
			begin
				FileHandle:= FileCreate(sw);
				if FileHandle<1 then
				begin
					sendData(FILETRANS_ERROR,errFileCreate,0,nil);
					exit;
				end;
				filesizes:=cmd^.y;
				sendData(FILETRANS_RESUME,0,0,nil);
			end;
			nextCmd:=FILETRANS_DATA;
		end;
		FILETRANS_DATA:
		begin
			if nextCmd<>FILETRANS_DATA then
			begin
				exit;
			end;
			repeat
	  		if cmd^.x<4096 then
	  		begin
					i:=RecvData(cmd^.x);
	  			j:=cmd^.x;
	  		end
	  		else
	  		begin
	  			i:=RecvData(4096);
	  			j:=4096;
	  		end;
	    	if i<1 then
	    	begin
					result:=i;
	    		exit;
	    	end;
	    	i:=FileWrite(FileHandle, yFileBuf[0], i);
	    	if i<>j then
	    	begin
					sendData(FILETRANS_ERROR,errFileWrite,0,nil);
					nextCmd:=0;
	    		exit;
	    	end;
	    	cmd^.x:=cmd^.x-i;
	    	filesizes:=filesizes-i;
	  	until cmd^.x=0;
	  	if filesizes=0 then
	  	begin
	    	FileClose(FileHandle);
	    	nextCmd:=FILETRANS_REQUEST;
				sendData(FILETRANS_NEXT,0,0,nil);
			end;
		end;
		FILETRANS_ERROR:
		begin
			PostMessage(filefrm,WM_FileTransfer,FILETRANS_ERROR,cmd^.x);
			FileClose(FileHandle);
		end;
		FILETRANS_REJECT:
		begin
			PostMessage(filefrm,WM_FileTransfer,FILETRANS_REJECT,0);
		end;
		FILETRANS_ACCEPT:
		begin
      result:=FILETRANS_ACCEPT;
			if mySpy<>nil then
			begin
				mySpy.doSuspend();
			end;
			PostMessage(filefrm,WM_FileTransfer,FILETRANS_ACCEPT,0);
		end;
		FILETRANS_NEXT:
		begin
			PostMessage(filefrm,WM_FileTransfer,FILETRANS_NEXT,0);
		end;
		FILETRANS_RESUME:
		begin
			PostMessage(filefrm,WM_FileTransfer,FILETRANS_RESUME,cmd^.x);
		end;
		FILETRANS_BREAK:
		begin
		end;
		FILETRANS_FINISH:
		begin
			if mySpy<>nil then
			begin
				mySpy.doResume();
				mySpy.resume;
			end;
			PostMessage(filefrm,WM_FileTransfer,FILETRANS_FINISH,0);
		end;
		FILETRANS_FINISHED:
		begin
			if mySpy<>nil then
			begin
				mySpy.doResume();
				mySpy.resume;
			end;		
		end;
	end;//end case
end;
end.
