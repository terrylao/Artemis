unit TCPWorkerThread;
{$mode objfpc}{$H+}
interface
uses
  Types,
  {$ifdef unix}cthreads, {$endif}
{$IFDEF WINDOWS}
  winsock2,windows,
{$ENDIF}
  SysUtils,Classes,dateutils,syncobjs;
const
  BUFSIZE=4096*2;
  {$IFDEF unix}
    {$DEFINE TSOCKET := Integer}
  	{$DEFINE closesocket:=close}
  	INVALID_SOCKET = -1;
  	SOCKET_ERROR = -1;
  {$ENDIF}
type
TTCPWorkerThread = class(TThread)
  public
    isWaiting:boolean;
	  constructor Create(b:boolean;logfile:string);
		destructor Destroy; override;
		procedure doWork(clientSocket:integer);
		procedure Event(SocketEvent : Integer; iRead:Integer;rcvbuf: pbyte );virtual;abstract;
		procedure doterminate();
  protected
	  mEvent:TEventObject;

		skt:integer;
		BufRev:pbyte;//buffer
		logger:textfile;
		procedure log(s:string);
	  procedure Execute; override;
		procedure disconnect();virtual;abstract;
end;

function GetRemoteSocketAddress ( s : TSocket ) : String;
function GetRemoteSocketPort ( s : TSocket ) : Integer;
function GetLocalSocketAddress ( s : TSocket ) : String;
function GetLocalSocketPort ( s : TSocket ) : Integer;
implementation
function GetIPByName(const Name:String):String;
var
  r:PHostEnt;
  a:TInAddr;
begin
  Result:='';
  r:= gethostbyname(PChar(Name));
  if Assigned(r) then
    begin
      a:=PInAddr(r^.h_Addr_List^)^;
      Result:=inet_ntoa(a);
    end;
end;
destructor TTCPWorkerThread.Destroy;
begin
  //doTerminate;
	mEvent.free;
   inherited; // Also called parent class destroyer
end;
constructor TTCPWorkerThread.Create(b:boolean;logfile:string);
var
  i:integer;
begin
  inherited Create(b);
  Freeonterminate:=true;
	mEvent := TEventObject.Create(nil,true,false,'');
	isWaiting:=true;
	skt:=-1;
  assignfile(logger,logfile);
	rewrite(logger);
end;
procedure TTCPWorkerThread.Execute;
var
  res:integer;

begin
  log('TTCPWorkerThread is working');
  BufRev:=allocmem(BUFSIZE);
	if BufRev=nil then
	begin
	 log('BufRev is nil');
	 exit;
	end;
	if skt>0 then
	 Event(1,0,BufRev);
  while Terminated=false do
	begin
	  while  (skt>0)   do
    begin
  		res:=recv(skt,BufRev,BUFSIZE,0);
  		if (res>0) then
  		begin
  			Event(3,res,BufRev);
  		end
  		else
			if (res<=0) then
  		begin
			  log('socket error:'+inttostr(res));
				Event(2,res,BufRev);
  		end;
		end;
		skt:=-1;
		isWaiting:=true;
    mEvent.WaitFor(INFINITE);
    mEvent.ResetEvent;
  end;//end while true
  FreeMem(BufRev);
	log('worker done.');
	closefile(logger);
end;
procedure TTCPWorkerThread.doWork(clientSocket:integer);
begin
  
  skt:=clientSocket;
	Event(1,0,nil);
  mEvent.SetEvent;
  isWaiting:=false;
end;
procedure TTCPWorkerThread.doterminate();
begin
  mEvent.SetEvent;
  Terminate;
  disconnect();
end;
procedure TTCPWorkerThread.log(s:string);
begin
  writeln(logger,s);
end;
//You can use the getsockname function for the local port and address and the getpeername for the remote port like so

function GetLocalSocketPort ( s : TSocket ) : Integer;
var
  Addr                  : TSockAddrIn;
  Size: integer;
begin
  Size := sizeof(Addr);
  getsockname(s, Addr, Size);
  Result := ntohs(Addr.sin_port);
end;

function GetLocalSocketAddress ( s : TSocket ) : String;
var
  Addr                  : TSockAddrIn;
  Size: integer;
begin
  Size := sizeof(Addr);
  getsockname(s, Addr, Size);
  Result := inet_ntoa(Addr.sin_addr);
end;


function GetRemoteSocketPort ( s : TSocket ) : Integer;
var
  Addr                  : TSockAddrIn;
  Size: integer;
begin
  Size := sizeof(Addr);
  getpeername(s, Addr, Size);
  Result := ntohs(Addr.sin_port);
end;

function GetRemoteSocketAddress ( s : TSocket ) : String;
var
  Addr                  : TSockAddrIn;
  Size: integer;
begin
  Size := sizeof(Addr);
  getpeername(s, Addr, Size);
  Result := inet_ntoa(Addr.sin_addr);
end;
{
例子代码：(关键是使用winsock2单元)
var
stLclAddr, stDstAddr: sockaddr_in;
stMreq: ip_mreq;
hSocket: TSOCKET;
stWSAData: TWSADATA;

procedure TForm1.FormCreate(Sender: TObject);
var
nRet:Integer;
fFlag:Boolean;
begin
// Init WinSock
nRet := WSAStartup($0202, stWSAData);
if nRet<>0 then
begin
StatusBar.SimpleText := Format('WSAStartup failed: %d', [nRet]);
Exit;
end;
// Multicast Group Address and Port setting 
StatusBar.SimpleText := Format('Multicast Address:%s, Port:%d, IP TTL:%d, Interval:%d.',[achMCAddr, nPort, lTTL, nInterval]);
// Get a datagram socket 
hSocket := socket(AF_INET,SOCK_DGRAM,0);
if (hSocket = INVALID_SOCKET) then
begin
StatusBar.SimpleText := Format('socket() failed, Err: %d', [WSAGetLastError]);
Exit;
end;
// Bind the socket 
stLclAddr.sin_family := AF_INET;
stLclAddr.sin_addr.s_addr := htonl(INADDR_ANY); // any interface 
stLclAddr.sin_port := 0; //any port 
nRet := bind(hSocket,stLclAddr,sizeof(stLclAddr));
if (nRet = SOCKET_ERROR) then
begin
StatusBar.SimpleText := Format('bind() port: %d failed, Err: %d', [nPort,WSAGetLastError]);
Exit;
end;
// Join the multicast group 
stMreq.imr_multiaddr.s_addr := inet_addr(achMCAddr);
stMreq.imr_interface.s_addr := INADDR_ANY;
nRet := setsockopt(hSocket,IPPROTO_IP,IP_ADD_MEMBERSHIP,@stMreq,sizeof(stMreq));
if (nRet = SOCKET_ERROR) then
begin
StatusBar.SimpleText := Format('setsockopt() IP_ADD_MEMBERSHIP address %s failed, Err: %d',[achMCAddr, WSAGetLastError]);
Exit;
end;
// Set IP TTL to traverse up to multiple routers
nRet := setsockopt(hSocket,IPPROTO_IP,IP_MULTICAST_TTL,@lTTL,sizeof(lTTL));
if (nRet = SOCKET_ERROR) then
begin
StatusBar.SimpleText := Format('setsockopt() IP_MULTICAST_TTL failed, Err: %d',[WSAGetLastError]);
Exit;
end;
// Disable loopback 
fFlag := False;
nRet := setsockopt(hSocket,IPPROTO_IP,IP_MULTICAST_LOOP,@fFlag,sizeof(fFlag));
if (nRet = SOCKET_ERROR) then
begin
StatusBar.SimpleText := Format('setsockopt() IP_MULTICAST_LOOP failed, Err: %d',[WSAGetLastError]);
end;
SndTimer.Enabled := True;
end;

procedure TForm1.SndTimerTimer(Sender: TObject);
var
nRet:Integer;
SndStr:String;
begin
//Get System (UTC) Time 
GetSystemTime(stSysTime);

//Assign our destination address 
stDstAddr.sin_family := AF_INET;
stDstAddr.sin_addr.s_addr := inet_addr(achMCAddr);
stDstAddr.sin_port := htons(nPort);
// Send the time to our multicast group! 
nRet := sendto(hSocket,stSysTime,sizeof(stSysTime),0,stDstAddr,sizeof(stDstAddr));
if (nRet < 0) then
begin
StatusBar.SimpleText := Format('sendto() failed, Error: %d', [WSAGetLastError]);
Exit;
end
else
begin
SndStr:=Format('Sent UTC Time %02d:%02d:%02d:%03d ',[stSysTime.wHour,stSysTime.wMinute,stSysTime.wSecond,stSysTime.wMilliseconds]);
SndStr:=SndStr+Format('Date: %02d-%02d-%02d to: %s:%d',[stSysTime.wMonth,stSysTime.wDay,stSysTime.wYear,inet_ntoa(stDstAddr.sin_addr),ntohs(stDstAddr.sin_port)]);
TimeLog.Lines.Add(SndStr);
end;
end;

}
end.
