unit ServerThread;
{$mode objfpc}{$H+}
interface
uses
  Types,
  {$ifdef unix}cthreads, {$endif}
{$IFDEF WINDOWS}
  winsock2,windows,
{$ENDIF}
  SysUtils,Classes,dateutils,syncobjs,socketfunc,atermisworker;
const
  BUFSIZE=4096*2;
  {$IFDEF unix}
    {$DEFINE TSOCKET := Integer}
  	{$DEFINE closesocket:=close}
  	INVALID_SOCKET = -1;
  	SOCKET_ERROR = -1;
  {$ENDIF}
type
    TCPServerThread = class(TThread)
	public
		mEvent:TEventObject;
    perhapsbeclosed:boolean;
		serverhost:string;
		serverport:integer;
		workers:array of Tatermisworker;
	  function bindto(servIP:string;PORT:integer):integer;
    procedure sendOut(data:pbyte;size:integer);
    procedure close();
		procedure log(s:string);
		constructor Create(b:boolean;maxworkers:integer);
    procedure doTerminate;
		destructor Destroy; override; 
  private
    
    timeouts:integer;
		logger:textfile;
  protected
    svrSock:Integer;//Socket物件
		
    procedure Execute; override;
end;

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
destructor TCPServerThread.Destroy;
var
  i:integer;
begin
	for i:=0 to length(workers)-1 do
		if workers[i].isWaiting then
		begin
      workers[i].free;
		end;
  inherited; // Also called parent class destroyer
end;
constructor TCPServerThread.Create(b:boolean;maxworkers:integer);
var
  i:integer;
begin
  inherited Create(b);
  Freeonterminate:=false;
	mEvent := TEventObject.Create(nil,true,false,'');
	perhapsbeclosed:=true;
	svrSock:=-1;
	setlength(workers,maxworkers);
  assignfile(logger,'server.log');
	rewrite(logger);
	for i:=0 to maxworkers-1 do
	begin
	  workers[i]:=Tatermisworker.create(false,'worker'+Inttostr(i)+'.log');
		workers[i].atermisidx:=i;
	end;
	log('worker created...');
end;

function TCPServerThread.bindto(servIP:string;PORT:integer):integer;
var
  wsd:WSADATA;
  timeout:Ttimeval;
  addr : TSockAddrIn;
begin
  if (WSAStartup(MAKEWORD(2,0),wsd)<0) then 
	 exit(-11);
  svrSock:=socket(AF_INET,SOCK_STREAM,IPPROTO_TCP);
  
  //if (svrSock=INVALID_SOCKET) then
  //   exit(-2);
  ZeroMemory(@addr,sizeof(addr));
  addr.sin_family:=AF_INET;
  addr.sin_port:=htons(port);
  if servIP='0.0.0.0' then
  begin
    addr.sin_addr.S_addr:=htonl(INADDR_ANY);
  end
  else
  begin
     addr.sin_addr.S_addr:=inet_addr(pchar(servIP));
  end;
  if bind(svrSock,addr,sizeof(addr))=SOCKET_ERROR{<>0} then
    exit(-3);
  if listen(svrSock,5)<>0 then
  begin
    exit(-4);
  end;
  perhapsbeclosed:=false;
  result:=0;
	serverhost:=servIP;
	serverport:=port;
end;
procedure TCPServerThread.sendOut(data:pbyte;size:integer);
begin
  send(svrSock,data,size,0);
end;
procedure TCPServerThread.close();
begin
  closesocket(svrSock);
	svrSock:=-1;
	perhapsbeclosed:=true;
end;
procedure TCPServerThread.log(s:string);
begin
  writeln(logger,s);
end;
procedure TCPServerThread.Execute;
var
  res,i:integer;
	timeval:TTimeVal;
	client:PSockAddr;
	namelen:PInteger;
	clientskt:integer;
begin
  timeval.tv_sec:=timeouts*1000;
  timeval.tv_usec:=50;
	if client=nil then
	begin
		new(client);
		new(namelen);
		namelen^:=sizeof(client^);
	end;
	log('TCPServerThread working...');
  while Terminated=false do
	begin
	  if svrSock=-1 then
		begin
		  log('TCPServerThread suspended...');
      mEvent.WaitFor(INFINITE);
      mEvent.ResetEvent;
			if Terminated then
			  continue;
			if svrSock=-1 then
			begin
        res:=bindTo(serverhost,serverport);
  			if res<0 then
  			begin
				  doTerminate();
  			  break;
  			end;
				log('TCPServerThread binded...');
			end;
		end;
		clientskt:=accept(svrSock,client,namelen);
		log('new socket imcoming:'+inttostr(clientskt));
		res:=0;
		for i:=0 to length(workers)-1 do
    begin
	    if workers[i].isWaiting then
			begin
			  log('TCPServerThread workers['+inttostr(i)+'] taken');
        workers[i].doWork(clientskt);
				workers[i].ShowClientInfo;
				res:=1;
        break;
			end;
    end;
		if res=0 then
		 closesocket(clientskt);
  end;//end while true
	dispose(client);
	dispose(namelen);
	closefile(logger);
end;

procedure TCPServerThread.doTerminate;
var
  i:integer;
begin
  // Signal event to wake up the thread
	Terminate;
  mEvent.SetEvent;
  CLOSE();
	for i:=0 to length(workers)-1 do
  begin
      workers[i].doterminate;
  end;
  // Base Terminate method (to set Terminated=true)
end;

//You can use the getsockname function for the local port and address and the getpeername for the remote port like so

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
