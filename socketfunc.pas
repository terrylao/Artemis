unit socketfunc;

interface
uses winsock,Messages;
const
  WM_SOCK= WM_USER+1;
Type

 PIP_mreq = ^TIP_mreq;
 TIP_mreq = record
    imr_multiaddr  : in_addr;
    imr_interface  : in_addr;
 end;
function GetRemoteSocketAddress ( s : TSocket ) : ansiString;
function GetRemoteSocketPort ( s : TSocket ) : Integer;
function GetLocalSocketAddress ( s : TSocket ) : ansiString;
function GetLocalSocketPort ( s : TSocket ) : Integer;
implementation
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

function GetLocalSocketAddress ( s : TSocket ) : ansiString;
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

function GetRemoteSocketAddress ( s : TSocket ) : ansiString;
var
  Addr                  : TSockAddrIn;
  Size: integer;
begin
  Size := sizeof(Addr);
  getpeername(s, Addr, Size);
  Result := inet_ntoa(Addr.sin_addr);
end;
{-------UDP Area-----}
{
MultiCast IP Class:
Class Name  Address Bits 	From ... To 	                Pourpose
Class A 	  0 	          0.0.0.0 - 127.255.255.255 	  Public IP address
Class B 	  10 	          128.0.0.0 - 191.255.255.255 	Public IP address
Class C 	  110 	        192.0.0.0 - 223.255.255.255 	Public IP address
Class D 	  1110 	        224.0.0.0 - 239.255.255.255 	Multicast IP Addresses
Class E 	  11110 	      240.0.0.0 - 255.255.255.255 	Reserved

}
function BindUDP(port:integer;handle:integer;MulticastAddr:String):integer;
var
  udpSocket : integer;
	udpBindAddr:TSockAddr;
	imreq:Tip_mreq;
begin
	result:=-1;
  udpSocket:=Socket(PF_INET, SOCK_DGRAM, 0);
  if (udpSocket = INVALID_SOCKET) then
    exit;
	udpBindAddr.sin_family := PF_INET;
	udpBindAddr.sin_addr.S_addr := INADDR_ANY;
	udpBindAddr.sin_port := htons(port);
	if Bind(udpSocket, udpBindAddr, sizeof(udpBindAddr)) <> 0 then
	begin
		result:=-2;
    exit;
	end;
	if MulticastAddr<>'' then
	begin
		imreq.imr_multiaddr.s_addr := inet_addr(pansichar(MulticastAddr));
		imreq.imr_interface.s_addr := INADDR_ANY; // use DEFAULT interface
		if setsockopt(udpSocket,IPPROTO_IP,IP_ADD_MEMBERSHIP,Pansichar(@imreq),sizeof(imreq)) = SOCKET_ERROR then
		begin
			result:=-1;
			exit;
		end;
	end;
	if handle>0 then
		WSAAsyncSelect(udpSocket, Handle , WM_SOCK, FD_READ);
	result:=udpSocket;
end;
{ async read sample
procedure ReadData(var Message: TMessage);
var
	buffer: Array [1..4096] of char;
	len: integer;
	flen: integer;
	Event: word;
	value: string;
	FSockAddrIn:TSockAddr;
begin
	flen:=sizeof(FSockAddrIn);
	FSockAddrIn.SIn_Port := htons(8943);
	Event := WSAGetSelectEvent(Message.LParam);
	if Event = FD_READ then
	begin
		len := recvfrom(udpSocket, buffer, sizeof(buffer), 0, FSockAddrIn, flen);
		value := copy(buffer, 1, len);
    CmdAddr:=INet_NToA(FSockAddrIn.SIn_Addr);
    if remoteAddr='' then
    begin
      remoteAddr:=CmdAddr;
    end
    else
    begin
      if remoteAddr<>CmdAddr then
      begin
        ResponseData(myAddr+' Command by '+remoteAddr+'  now');
        exit;
      end;
    end;
    parseCmd(value);
		logs.Lines.add(value);
	end;
end;}
function UDPBroadCast(Content: pchar;datalength,port:integer):integer;
var
	len,i,optval: integer;
	SockAddrIn:TSockAddr;
	udpSocket: TSocket;
begin
  udpSocket:=Socket(PF_INET, SOCK_DGRAM, IPPROTO_IP);
  if (udpSocket = INVALID_SOCKET) then
  begin
    result:=-1;
    exit;
  end;
  optval:= 1;
	if setsockopt(udpSocket,SOL_SOCKET,SO_BROADCAST,Pansichar(@optval),sizeof(optval)) = SOCKET_ERROR then
	begin
    result:=-1;
    exit;
	end;
	SockAddrIn.SIn_Family := PF_INET;
	SockAddrIn.SIn_Port := htons(port);
	SockAddrIn.SIn_Addr.S_addr := INADDR_BROADCAST;
	len := sendto(udpSocket, Content[0], datalength, 0, SockAddrIn, sizeof(SockAddrIn));
	if (WSAGetLastError() <> WSAEWOULDBLOCK) and (WSAGetLastError() <> 0) then
	begin
		result:=WSAGetLastError()*-1;
		exit;
	end;
	if len = SOCKET_ERROR then
	  result:=-1;
	while len < datalength do
	begin
		i:= sendto(udpSocket, Content[len], datalength-len, 0, SockAddrIn, sizeof(SockAddrIn));
		if i = -1 then
		begin
			result:=WSAGetLastError()*-1;
			exit;
		end;
		len:=len+i;
	end;
	result:=0;
end;
function UDPSend(Content: pchar;datalength:integer;host:String;port:integer):integer;
var
  SockAddrIn: TSockAddr;
  udpSocket: TSocket;
	value: string;
	len,i: integer;
begin
  udpSocket:=Socket(PF_INET, SOCK_DGRAM, IPPROTO_IP);
  if (udpSocket = INVALID_SOCKET) then
  begin
    result:=-1;
    exit;
  end;
  SockAddrIn.sin_family:=PF_INET;
  SockAddrIn.sin_addr.S_addr:=inet_addr(Pansichar(host));
  SockAddrIn.sin_port:=htons(port);
	len := sendto(udpSocket, Content[0], datalength, 0, SockAddrIn, sizeof(SockAddrIn));
	if (WSAGetLastError() <> WSAEWOULDBLOCK) and (WSAGetLastError() <> 0) then
	begin
		result:=WSAGetLastError()*-1;
		exit;
	end;
	if len = SOCKET_ERROR then
	  result:=-1;
	while len < datalength do
	begin
		i:= sendto(udpSocket, Content[len], datalength-len, 0, SockAddrIn, sizeof(SockAddrIn));
		if i = -1 then
		begin
			result:=WSAGetLastError()*-1;
			exit;
		end;
		len:=len+i;
	end;
	result:=0;
end;
function UDPMultiCast(Content: pchar;datalength,port:integer;MulticastAddr:String):integer;
var
	len,i,optval: integer;
	SockAddrIn:TSockAddr;
	udpSocket: TSocket;
	iaddr:TInAddr;
	ttl,one:char;
begin
  udpSocket:=Socket(PF_INET, SOCK_DGRAM, IPPROTO_IP);
  if (udpSocket = INVALID_SOCKET) then
  begin
    result:=-1;
    exit;
  end;
  optval:= 1;
	if setsockopt(udpSocket,SOL_SOCKET,SO_BROADCAST,Pansichar(@optval),sizeof(optval)) = SOCKET_ERROR then
	begin
    result:=-1;
    exit;
	end;
	SockAddrIn.SIn_Family := PF_INET;
	if port>0 then
		SockAddrIn.SIn_Port := htons(port)
	else
		SockAddrIn.SIn_Port := htons(0);// Use the first free port
	SockAddrIn.SIn_Addr.S_addr := htonl(INADDR_ANY); // bind socket to any interface
	//?nbind ??? UDP bind ?~?ব
	if Bind(udpSocket, SockAddrIn, sizeof(SockAddrIn)) <> 0 then
	begin
		result:=-2;
    exit;
	end;
	iaddr.s_addr := INADDR_ANY; // use DEFAULT interface
	if setsockopt(udpSocket,IPPROTO_IP,IP_MULTICAST_IF,Pansichar(@iaddr),sizeof(iaddr)) = SOCKET_ERROR then
	begin
		result:=-1;
		exit;
	end;
   // Set multicast packet TTL to 3; default TTL is 1
	ttl:=#3;
	if setsockopt(udpSocket,IPPROTO_IP,IP_MULTICAST_TTL,Pansichar(@ttl),sizeof(char)) = SOCKET_ERROR then
	begin
		result:=-1;
		exit;
	end;
   // send multicast traffic to myself too
	one:=#1;
	if setsockopt(udpSocket,IPPROTO_IP,IP_MULTICAST_LOOP,Pansichar(@one),sizeof(char)) = SOCKET_ERROR then
	begin
		result:=-1;
		exit;
	end;
   // set destination multicast address
	SockAddrIn.sin_family := PF_INET;
	SockAddrIn.sin_addr.s_addr := inet_addr(Pansichar(MulticastAddr));//MulticastAddr Ex: '226.0.0.1'
	SockAddrIn.sin_port := htons(port);

	len := sendto(udpSocket, Content[0], datalength, 0, SockAddrIn, sizeof(SockAddrIn));
	if (WSAGetLastError() <> WSAEWOULDBLOCK) and (WSAGetLastError() <> 0) then
	begin
		result:=WSAGetLastError()*-1;
		exit;
	end;
	if len = SOCKET_ERROR then
	  result:=-1;
	while len < datalength do
	begin
		i:= sendto(udpSocket, Content[len], datalength-len, 0, SockAddrIn, sizeof(SockAddrIn));
		if i = -1 then
		begin
			result:=WSAGetLastError()*-1;
			exit;
		end;
		len:=len+i;
	end;
	result:=0;
end;
{-------End UPD Area----}
end.
