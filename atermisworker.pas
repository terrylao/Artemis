unit atermisworker;

{$mode objfpc}{$H+}

interface

uses
  Classes, Forms, Controls, Graphics,winsock2,zlibex,
  StdCtrls, Types, LCLIntf, LCLType, sysutils,windows,Clipbrd,TCPWorkerThread;
const
  DATASIZE = 1048*1024;
	FILEBLOCKS = 16;
  REQUEST_LOGIN=10;
  REQUEST_SCREEN=20;
  FULL_SCREEN=21;
  PART_SCREEN=22;
	STOP_SCREEN=23;
  SEND_SCREEN=29;
  REQUEST_AUDIO=30;
  AUDIO_DATA=31;
  REQUEST_RECEIVE_FILE=50;
  CONFIRM_REQUEST_RECEIVE_FILE=51;
  FILE_CONTENT=52;
  NEXT_BLOCK_FILE_DATA=53;
  REJECT_REQUEST_RECEIVE_FILE=54;
  CLIPBOARD_DATA=60;
  MOUSE_MOVE=70;
  MOUSE_ACTION=71;
  KEYBOARD_ACTION=80;
type
  TShowScreenEvent = procedure(eventid,idx: integer) of Object;
	TRemoveEvent = procedure(idx: integer) of Object;
	TAddClientEvent = procedure(sip,sport:string;idx: integer) of Object;
	patermisworker=^Tatermisworker;
	TShowScreenEvent2 = procedure(eventid: integer;source:patermisworker) of Object;
  Tatermisworker = class(TTCPWorkerThread)
    protected
		  procedure checkdisconnect(r:integer);
		private
		  needCmd:boolean;
			payloadsize,statusid,iDownloadFileHandle,iUploadFileHandle,fileBlockCount,remoteBlockCount:integer;
			nextbytes,curbytes,buftail:integer;//curbytes-->means the start of databuf to be use
			cmdbuf:array [0..4] of byte;
			databuf,outbuf:pbyte;
      actualfilesize,receivedfilesize,outbufsize:integer;
			sendCSec:TRTLCriticalSection;
			FOnShowScreen: TShowScreenEvent;
			FOnRemove: TRemoveEvent;
			FOnNewConnect: TAddClientEvent;
      procedure ShowScreen;
			procedure reinit();
		  function setCmd(cmd,size:integer):integer;
			function fillData(p:pbyte;size:integer):integer;
			function recvFileRequest(filename:string;afilesize:integer):integer;
			function shiftInputFile(pos:integer):integer;
			function writeData2File(ppayload:pbyte):integer;
    public
			mmsin,mmsout:TMemoryStream;
			islogined,needScreen:boolean;
			passwd,sDownloadFileName:string;
			remoteip,remoteport:string;
			atermisidx:integer;
			gridindx:integer;
			mousex,mousey:integer;
			mouseclicked:TMouseButton;
			upanddown,mousescroll:integer;
			sstate:TShiftState;
			akey:word;
			remoteErrCode:integer;
			iUploadFileSize,iUploadCurrentFileSize,filepercent:integer;
			function sendStopScreen():integer;
			function sendGetScreen():integer;
			function sendScreen(itype:integer;p:pbyte;screensize:integer):integer;
			function sendFile(fname:string):integer;
      function sendFileData():integer;
      function sendMouseMove(x,y:integer):integer;
      function sendMouseClick(x,y,delta,updown:integer;Button: TMouseButton; Shift: TShiftState):integer;
			function sendKey(k:Word; Shift: TShiftState;updown:integer):integer;
			function sendRecvScreen():integer;   
      function FileRejected():integer;
			function sendClipboard(s:string):integer;
			function sendLogin(s:string):integer;
		  procedure Event(SocketEvent : Integer; iRead:Integer;rcvbuf: pbyte );override;
			constructor Create(b:boolean;logfile:string);
			destructor Destroy;
			procedure disconnect();override;
			procedure ShowClientInfo;
			property OnShowScreen: TShowScreenEvent read FOnShowScreen write FOnShowScreen;
			property OnRemove: TRemoveEvent read FOnRemove write FOnRemove;
			property OnNewConnect: TAddClientEvent read FOnNewConnect write FOnNewConnect;
	end;
implementation
constructor Tatermisworker.Create(b:boolean;logfile:string);
begin
  inherited Create(b,logfile);
	InitializeCriticalSection(sendCSec);
	databuf:=allocmem(DATASIZE);
	outbuf:=allocmem(DATASIZE);
  reinit();
  mmsin:=TMemoryStream.Create;
  mmsout:=TMemoryStream.Create;
end;
destructor Tatermisworker.Destroy;
begin
  mmsin.free;
	mmsout.free;
	freemem(databuf);
	freemem(outbuf);
	DeleteCriticalSection(sendCSec);
	disconnect();
  inherited;
end;
function Tatermisworker.sendClipboard(s:string):integer;
var
  i,j,k:integer;
begin
  EnterCriticalSection(sendCSec);
  try
	  if length(s)<DATASIZE then
      result := setCmd(CLIPBOARD_DATA,length(s))
		else
      result := setCmd(CLIPBOARD_DATA,DATASIZE);
  	if result<0 then
      exit;
		if length(s)<DATASIZE then
  	 result := fillData( @s[1], length(s) )
		else
		 result := fillData( @s[1],DATASIZE);
		if outbufsize>4096 then
		begin
  		i:=0;
			k:=outbufsize div 4096;
			j:=outbufsize mod 4096;
  		repeat
			  result:= send(skt,outbuf[i],4096,0);
  	    i:=i+4096;
			  dec(k);
  		until (k<1) or (result<0);
			if (result>0) and (j>0) then
			begin
			  result:= send(skt,outbuf[i],j,0);
			end;
		end
		else
		begin
		  result:= send(skt,outbuf[0],outbufsize,0);
		end;
		checkdisconnect(result);
  finally
    LeaveCriticalSection(sendCSec);
  end;
end;

function Tatermisworker.sendLogin(s:string):integer;
begin
  EnterCriticalSection(sendCSec);
  try
    result := setCmd(REQUEST_LOGIN,length(s));
  	if result<0 then
      exit;
  	result := fillData( @s[1], length(s) );
		result:= send(skt,outbuf[0],outbufsize,0);
		checkdisconnect(result);
  finally
    LeaveCriticalSection(sendCSec);
  end;
end;
function Tatermisworker.sendStopScreen():integer;
begin
  EnterCriticalSection(sendCSec);
  try
    result := setCmd(STOP_SCREEN,0);
		result:= send(skt,outbuf[0],outbufsize,0);
		checkdisconnect(result);
  finally
    LeaveCriticalSection(sendCSec);
  end;
end;
function Tatermisworker.sendGetScreen():integer;
begin
  EnterCriticalSection(sendCSec);
  try
    result := setCmd(REQUEST_SCREEN,0);
		result:= send(skt,outbuf[0],outbufsize,0);
		checkdisconnect(result);
  finally
    LeaveCriticalSection(sendCSec);
  end;
end;
function Tatermisworker.sendRecvScreen():integer;
begin
  EnterCriticalSection(sendCSec);
  try
    result := setCmd(SEND_SCREEN,0);
		result:= send(skt,outbuf[0],outbufsize,0);
		checkdisconnect(result);
  finally
    LeaveCriticalSection(sendCSec);
  end;
end;
function Tatermisworker.sendScreen(itype:integer;p:pbyte;screensize:integer):integer;
var
  i,j,k:integer;
begin
  EnterCriticalSection(sendCSec);
  try
    result := setCmd(itype,screensize);
  	if result<0 then
      exit;
  	result := fillData( p, screensize );
		if outbufsize>4096 then
		begin
  		i:=0;
			k:=outbufsize div 4096;
			j:=outbufsize mod 4096;
  		repeat
			  result:= send(skt,outbuf[i],4096,0);
  	    i:=i+4096;
			  dec(k);
  		until (k<1) or (result<0);
			if (result>0) and (j>0) then
			begin
			  result:= send(skt,outbuf[i],j,0);
			end;
		end
		else
		begin
		  result:= send(skt,outbuf[0],outbufsize,0);
		end;
		checkdisconnect(result);
  finally
    LeaveCriticalSection(sendCSec);
  end;
end;
procedure Tatermisworker.checkdisconnect(r:integer);
begin
  if r<0 then
	 disconnect();
end;
procedure Tatermisworker.disconnect();
begin
  if skt=-1 then
	 exit;
  closesocket(skt);
	skt:=-1;
	if iDownloadFileHandle>0 then
	begin
		FileClose(iDownloadFileHandle);
		iDownloadFileHandle:=-2;
	end;
	if iUploadFileHandle>0 then
	begin
		FileClose(iUploadFileHandle);
		iUploadFileHandle:=-2;
	end;
  	statusid:=-1;
  if Assigned(FOnRemove) then
  begin
    FOnRemove(gridindx);
  end;
	reinit();
end;
procedure Tatermisworker.ShowClientInfo;
begin
  if Assigned(FOnNewConnect) then
  begin
    FOnNewConnect(remoteip,remoteport,gridindx);
  end;
end;
procedure Tatermisworker.ShowScreen;
//https://wiki.freepascal.org/Multithreaded_Application_Tutorial
// in mainthread : atermisworker.OnShowStatus := @ShowStatus; ShowStatus is an function with integer parameter
// this method is executed by the mainthread and can therefore access all GUI elements.
begin
  if Assigned(FOnShowScreen) then
  begin
    FOnShowScreen(statusid,atermisidx);
  end;
end;
procedure Tatermisworker.reinit();
begin
  isWaiting:=true;
	needScreen:=false;
	islogined:=false;
	needCmd:=true;
	nextbytes:=5;
	curbytes:=0;
	buftail:=0;
	iUploadFileHandle:=-1;
	iDownloadFileHandle:=-1;
end;
function Tatermisworker.fillData(p:pbyte;size:integer):integer;
begin
	move(p^,outbuf[outbufsize],size);
	outbufsize:=outbufsize+size;
	result := 0;
end;
function Tatermisworker.setCmd(cmd,size:integer):integer;
begin
  outbuf[0]:=cmd;
	//log('sendout:'+inttostr(cmd)+' payloadsize='+inttostr(size)+' bytes.');
	//for intel little encdian
	move(swapendian(size),outbuf[1],4);
  outbufsize:=5;
	result := 0;
end;

procedure Tatermisworker.Event(SocketEvent : Integer; iRead:Integer;rcvbuf: pbyte );
var
  j,iremain : Integer;
  s:string;
	ppayload:pbyte;
begin
	case SocketEvent of
	  1://connected
		begin
		  remoteip:=GetRemoteSocketAddress(skt);
			remoteport:=IntToStr(GetRemoteSocketPort ( skt ));
		end;
    2://seDisconnect :
    begin
		  disconnect();
		end;
    3://seRead :
    begin
			move(rcvbuf[0],databuf[buftail],iRead);
			buftail:=buftail+iRead;
			iremain:=buftail-curbytes;
			log('imcoming:'+inttostr(iRead)+' bytes.');
		  while curbytes<buftail do
			begin
  		  if needCmd then
  			begin
    		  if iremain<nextbytes then
    			begin
  					break
    			end
  				else
  				begin
  				  move(databuf[curbytes],cmdbuf[0],nextbytes);
						curbytes:=curbytes+nextbytes;
  					nextbytes:=0;
						iremain:=buftail-curbytes;
  				end;
  				needCmd:=false;
  				payloadsize:=swapendian(pinteger(@cmdbuf[1])^);
					log('cmd:'+inttostr(cmdbuf[0])+' payload:'+inttostr(payloadsize));
  				if payloadsize>DATASIZE then
  				  exit;
					
  			end;

				if (payloadsize>0) and (payloadsize>iremain) then
				begin
				  //not enough for payload
					log('not enough for payload:'+inttostr(payloadsize)+' remain:'+inttostr(iremain));
					if curbytes>0 then
					begin
  					move(databuf[curbytes],databuf[0],iremain);
  					buftail:=iremain;
  					curbytes:=0;
					end;
					break;
				end;
				  //now data is ready in databuf with size=payloadsize
				statusid:=cmdbuf[0];
				ppayload:=@databuf[curbytes];
				if REQUEST_LOGIN=cmdbuf[0] then//login with password length
				begin
					log('cmd:loging');
					setstring(passwd,pansichar(ppayload),payloadsize);
					islogined:=true;
					Synchronize(@ShowScreen);
					if islogined=false then
					begin
						disconnect();
						exit;
					end;
					needCmd:=true;
					nextbytes:=5;
					curbytes:=curbytes+payloadsize;
					iremain:=buftail-curbytes;
					payloadsize:=0;
					continue;
				end;
				if (islogined=false) and (atermisidx>-1) then
				begin
    		  disconnect();
				 exit;
				end;

				case cmdbuf[0] of
					REQUEST_SCREEN://request server send out screen
					begin
						//start a thread to send out screen capture
            log('cmd:request screen');
							
						Synchronize(@ShowScreen);
					end;
					SEND_SCREEN://request server receive screen
					begin
					end;
					FULL_SCREEN,PART_SCREEN://screenshot received
					begin
						log('cmd:receive screen');
						//load to a bitmap and show on view form
						//j:=FileCreate('d:\ttj3.jpg',fmOpenWrite);
						//FileWrite(j,ppayload[0],payloadsize);
						//FileClose(j);
						mmsin.clear;
            mmsin.Write(ppayload[0],payloadsize);
						mmsin.Position:=0;
						mmsout.clear;

            //ZDecompressStream(mmsin, mmsout);
						mmsout.Position := 0;
						//mmsin.SaveTofile('in.bin');
						Synchronize(@ShowScreen);
					end;
					STOP_SCREEN:
					begin
					  needScreen:=false;
					end;
					REQUEST_AUDIO://request audio
					begin
						//start mic-in thread for send out audio payload
            log('cmd:request audio');
					end;
					AUDIO_DATA://receive and audio data
					begin
						log('cmd:receive audio');
						//decode audio data and play it
					end;
					REQUEST_RECEIVE_FILE://request receive file name+4 byte file size
					begin
            setstring(s,pansichar(ppayload),payloadsize-4);
							
            j:=swapendian(pinteger(@ppayload[payloadsize-4])^);
						log('cmd:request file:'+s+' filesize:'+inttostr(j));
						if recvFileRequest(s,j)<0 then
						begin
						  disconnect();
						end;

					end;
					CONFIRM_REQUEST_RECEIVE_FILE://file write confirm, with 4 bytes position,4 bytes block count
					begin
						j:=swapendian(pinteger(ppayload)^);
						remoteBlockCount:=swapendian(pinteger(@ppayload[4])^);
						log('cmd:file write confirm,shift='+inttostr(j)+',remoteBlockCount='+inttostr(remoteBlockCount));
						shiftInputFile(j);
						remoteErrCode:=sendFileData();
						Synchronize(@ShowScreen);
					end;
					NEXT_BLOCK_FILE_DATA://confirm next  read with block count;
					begin
						  
						remoteBlockCount:=swapendian(pinteger(ppayload)^);
						log('cmd:file next  read count:'+inttostr(remoteBlockCount));
						remoteErrCode:=sendFileData();
						Synchronize(@ShowScreen);
					end;
					REJECT_REQUEST_RECEIVE_FILE://file write reject, with 4 bytes error code
					begin
						log('cmd:file write reject');
						remoteErrCode:=swapendian(pinteger(ppayload)^);
						Synchronize(@ShowScreen);
					end;
					FILE_CONTENT://request receive file content
					begin
            if writeData2File(ppayload)<0 then
						begin
						  disconnect();
						end;
					end;
					CLIPBOARD_DATA://request share clipboard data
					begin
						log('cmd:file clipboard data');
						setstring(s,pansichar(ppayload),payloadsize);
						Clipboard.AsText:=s;
					end;
					//https://wiki.freepascal.org/MouseAndKeyInput
					MOUSE_MOVE://mouse action : move, fixed 8 bytes for x,y
					begin
						//SetCursorPos(cmd^.X, cmd^.Y);
						mousex:=swapendian(pinteger(ppayload)^);
						mousey:=swapendian(pinteger(@ppayload[4])^);
						Synchronize(@ShowScreen);
						log('cmd:mouse move:X='+InttoStr(mousex)+',y='+inttostr(mousey));
              
					end;
					MOUSE_ACTION://mouse action : click fixed 4 bytes for button left,middle,right, 0 or 1 for clicked. and wheel scrolling(255 degree)
					begin
						//1 bytes:left most byte:shift,alt,ctrl,left,middle,right,wheel,up/down,
						//4 bytes: delta of wheel
						//8 bytes: x=4 bytes, y = 4 bytes
						sstate:=[];
            if ppayload[0] and $80 >0 then
						begin
							include(sstate, ssShift);
							log('ssShift clicked');
						end;
            if ppayload[0] and $40>0 then
						begin
							include(sstate, ssAlt);
							log('ssAlt clicked');
						end;
          		 
            if ppayload[0] and $20 > 0  then
						begin
							include(sstate, ssCtrl);
							log('ssCtrl clicked');
						end;
          		 
            if ppayload[0] and $10 > 0  then
						begin
							include(sstate, ssLeft);
							log('ssLeft clicked');
						end;
          		 
            if ppayload[0] and $8 > 0 then
						begin
							include(sstate, ssRight);
							log('ssRight clicked');
						end;
          		 
            if ppayload[0] and $4 > 0 then
						begin
							include(sstate, ssMiddle);
							log('ssMiddle clicked');
						end;
          		 
            if ppayload[0] and $2 > 0 then
						begin
							//mouse wheel scroll
							if swapendian(pinteger(@ppayload[1])^)>0 then
							begin
								//scroll down
								mousescroll:=2;
							end
							else
							begin
								//scroll up
								mousescroll:=1;
							end;
						end;
						mousex:=swapendian(pinteger(@ppayload[5])^);
						mousey:=swapendian(pinteger(@ppayload[9])^);
            if ppayload[0] and $10 > 0  then
							mouseclicked:=mbLeft;
                  
            if ppayload[0] and $8 > 0 then
							mouseclicked:=mbRight;

            if ppayload[0] and $4 > 0 then
							mouseclicked:=mbMiddle;
            if ppayload[0] and $1 > 0 then
						begin
							log('cmd:mouse down:X='+InttoStr(mousex)+',y='+InttoStr(mousey));
							//mouse down
							upanddown:=2;

						end
						else
						begin
							log('cmd:mouse up:X='+InttoStr(mousex)+',y='+InttoStr(mousey));
							upanddown:=1;
            end;
            Synchronize(@ShowScreen);
					end;
					KEYBOARD_ACTION://for keyboard type fixed 4 bytes,key code,shift(0,1 left ,2 right),ctrl,alt
					begin
						//4 bytes:
						//1 bytes:left most byte:shift,alt,ctrl,left,right,middle,
						//1 byte : reserve
						//2 bytes:keycode
						sstate:=[];
            if ppayload[0] and $80 >0 then
						begin
							include(sstate, ssShift);
							log('ssShift clicked');
						end;
            if ppayload[0] and $40>0 then
						begin
							include(sstate, ssAlt);
							log('ssAlt clicked');
						end;
          		 
            if ppayload[0] and $20 > 0  then
						begin
							include(sstate, ssCtrl);
							log('ssCtrl clicked');
						end;
          		 
            if ppayload[0] and $10 > 0  then
						begin
							include(sstate, ssLeft);
							log('ssLeft clicked');
						end;
          		 
            if ppayload[0] and $8 > 0 then
						begin
							include(sstate, ssRight);
							log('ssRight clicked');
						end;
          		 
            if ppayload[0] and $4 > 0 then
						begin
							include(sstate, ssMiddle);
							log('ssMiddle clicked');
						end;
						akey:=swapendian(pword(@ppayload[2])^);
            if ppayload[0] and $1 > 0 then
						begin
							//key down
							upanddown:=2;
							log('cmd:key Down:='+InttoStr(akey));
                
						end
            else
            begin
							upanddown:=1;
							log('cmd:key up:='+InttoStr(akey));

            end;
						Synchronize(@ShowScreen);
					end;
					else
					begin
					  disconnect();
						exit;
					end;
				end;//end case
				curbytes:=curbytes+payloadsize;
				iremain:=buftail-curbytes;
				needCmd:=true;
				nextbytes:=5;
				payloadsize:=0;
			end;//end while < buftail
  		if curbytes>0 then
  		begin
  			move(databuf[curbytes],databuf[0],iremain);
  			buftail:=iremain;
  			curbytes:=0;
  		end;
		end;//end READ
	end;
end;
function Tatermisworker.sendMouseMove(x,y:integer):integer;
var
  axisarray:array[0..7] of byte;
	tmp:integer;
begin
  EnterCriticalSection(sendCSec);
  try
    result := setCmd(MOUSE_MOVE,8);
  	if result<0 then
      exit;
		tmp:=swapendian(x);
		move(tmp,axisarray[0],4);
		tmp:=swapendian(y);
		move(tmp,axisarray[4],4);
		fillData(@axisarray[0],8);
  	result:=send(skt,outbuf[0],outbufsize,0);
		checkdisconnect(result);
  finally
    LeaveCriticalSection(sendCSec);
  end;
end;
function Tatermisworker.sendMouseClick(x,y,delta,updown:integer;Button: TMouseButton; Shift: TShiftState):integer;
var
  axisarray:array[0..7] of byte;
	mouseaction:array[0..3] of byte;
	btn:byte;
	tmp:integer;
begin
  EnterCriticalSection(sendCSec);
  try
    result := setCmd(MOUSE_ACTION,13);
  	if result<0 then
      exit;
		btn:=0;
		//1 bytes:left most byte:shift,alt,ctrl,left,middle,right,wheel,up/down,
		//4 bytes: delta of wheel
		//8 bytes: x=4 bytes, y = 4 bytes
    if ssShift in Shift then 
		 btn := btn or $80;
    if ssAlt in Shift then 
		 btn := btn or $40;
    if ssCtrl in Shift then 
		 btn := btn or $20;
    if ssLeft in Shift then 
		 btn := btn or $10;
    if ssRight in Shift then 
		 btn := btn or $8;
    if ssMiddle in Shift then 
		 btn := btn or $4;

    if Button = mbLeft then
      btn := btn or $10;

		if Button = mbRight  then
      btn := btn or $8;
    if Button = mbMiddle then
		 btn := btn or $4;
		if delta>0 then
		 btn := btn or $2;
		if updown>1 then
		 btn := btn or 1;
		fillData(@btn,1);
		tmp:=swapendian(delta);
		fillData(@tmp,4);
  	if result<0 then
      exit;
		tmp:=swapendian(x);
		move(tmp,axisarray[0],4);
		tmp:=swapendian(y);
		move(tmp,axisarray[4],4);
		fillData(@axisarray[0],8);
  	result:=send(skt,outbuf[0],outbufsize,0);
		checkdisconnect(result);
  finally
    LeaveCriticalSection(sendCSec);
  end;
end;
function Tatermisworker.sendKey(k:Word; Shift: TShiftState;updown:integer):integer;
var
	btn:byte;
	lkey:word;
	keyarray:array[0..3] of byte;
begin
  EnterCriticalSection(sendCSec);
  try
    result := setCmd(KEYBOARD_ACTION,4);
  	if result<0 then
      exit;
		btn:=0;
		//1 bytes:left most byte:shift,alt,ctrl,left,right,middle,0,up/down
		//1 byte : reserve
		//2 bytes:keycode
    if ssShift in Shift then 
		 btn := btn or $80;
    if ssAlt in Shift then 
		 btn := btn or $40;
    if ssCtrl in Shift then 
		 btn := btn or $20;
    if ssLeft in Shift then 
		 btn := btn or $10;
    if ssRight in Shift then 
		 btn := btn or $8;
    if ssMiddle in Shift then 
		 btn := btn or $4;
		if updown>1 then
		 btn := btn or 1;
		lkey:=swapendian(k);
		keyarray[0]:=btn;
		move(lkey,keyarray[2],2);
		fillData(@keyarray[0],4);
  	result:=send(skt,outbuf[0],outbufsize,0);
		checkdisconnect(result);
  finally
    LeaveCriticalSection(sendCSec);
  end;
end;
function Tatermisworker.shiftInputFile(pos:integer):integer;
begin
  if pos=0 then
	 exit(0);
  result:=FileSeek(iUploadFileHandle,pos,fsFromBeginning);
	
	iUploadCurrentFileSize:=pos;
	filepercent:=round(double(iUploadCurrentFileSize) / double(iUploadFileSize) * 100);
end;
function Tatermisworker.recvFileRequest(filename:string;afilesize:integer):integer;
var
	F : File Of byte;
	currentFileSize:integer;
begin
	if afilesize>0 then
	begin
	  result:=0;
		if FileExists(filename) then
		begin
			Assignfile(F,filename);
			Reset (F);
			currentFileSize:=FileSize(F);
			Closefile (F);
			if afilesize>currentFileSize then
			begin
			  iDownloadFileHandle:=FileOpen (filename,fmOpenWrite);
      	if iDownloadFileHandle=-1 then
      	begin
      		setCmd(REJECT_REQUEST_RECEIVE_FILE,4);
					currentFileSize:=1;
					currentFileSize:=swapendian(currentFileSize);
					fillData(@currentFileSize,4);
					result:= send(skt,outbuf[0],outbufsize,0);
					exit;
      	end
      	else
      	begin
				  FileSeek(iDownloadFileHandle,currentFileSize,fsFromBeginning);
			  end;
				setCmd(CONFIRM_REQUEST_RECEIVE_FILE,8);
				fillData(@currentFileSize,4);
				fileBlockCount:=FILEBLOCKS;
				currentFileSize:=swapendian(fileBlockCount);
				fillData(@currentFileSize,4);
				result:= send(skt,outbuf[0],outbufsize,0);
				actualfilesize:=afilesize;
				receivedfilesize:=currentFileSize;
				sDownloadFileName:=filename;
				Synchronize(@ShowScreen);
				exit;
			end
			else
			begin
			  setCmd(REJECT_REQUEST_RECEIVE_FILE,4);
    		currentFileSize:=1;
				currentFileSize:=swapendian(currentFileSize);
    		fillData(@currentFileSize,4);
				result:= send(skt,outbuf[0],outbufsize,0);
				checkdisconnect(result);
				exit;
			end;
		end;
	end;
	iDownloadFileHandle:=FileCreate(filename,fmOpenWrite);
	if iDownloadFileHandle=-1 then
	begin
		setCmd(REJECT_REQUEST_RECEIVE_FILE,4);
		currentFileSize:=1;
		currentFileSize:=swapendian(currentFileSize);
		fillData(@currentFileSize,4);
		result:= send(skt,outbuf[0],outbufsize,0);
		checkdisconnect(result);
	end
	else
	begin
		setCmd(CONFIRM_REQUEST_RECEIVE_FILE,8);
		currentFileSize:=0;
		fillData(@currentFileSize,4);
		fileBlockCount:=FILEBLOCKS;
		currentFileSize:=swapendian(fileBlockCount);
		fillData(@currentFileSize,4);
		result:= send(skt,outbuf[0],outbufsize,0);
		actualfilesize:=afilesize;
		receivedfilesize:=0;
		checkdisconnect(result);
	end;
end;
function Tatermisworker.sendFile(fname:string):integer;
var
  s:string;
	currentFileSize,j:integer;
	F : File Of byte;
begin
  EnterCriticalSection(sendCSec);
  try
	  s:=extractfilename(fname);

  	if iUploadFileHandle<0 then
  	begin
  	  Assignfile (F,fname);
  		Reset (F);
  		currentFileSize:=FileSize(F);
  		Closefile (F);
			iUploadFileHandle:=FileOpen(fname,fmOpenRead);
  		if iUploadFileHandle=-1 then
  		begin
  		  exit(-100);
  		end;
  	end;
    result := setCmd(REQUEST_RECEIVE_FILE,length(s)+4);

		result := fillData( @s[1], length(s) );
		iUploadFileSize:=currentFileSize;
		currentFileSize:=swapendian(currentFileSize);
		result := fillData( @currentFileSize, 4 );
		filepercent:=0;
		result:= send(skt,outbuf[0],outbufsize,0);
		iUploadCurrentFileSize:=0;
		checkdisconnect(result);
  finally
    LeaveCriticalSection(sendCSec);
  end;
  result := 0;
end;
function Tatermisworker.FileRejected():integer;
begin
	FileClose(iUploadFileHandle);
	iUploadFileHandle:=-2;
	result := 0;
end;
function Tatermisworker.writeData2File(ppayload:pbyte):integer;
var
        j:integer;
begin
	if iDownloadFileHandle<0 then
		exit;

	j:=FileWrite(iDownloadFileHandle,ppayload[0],payloadsize);
	if payloadsize<>j then
	begin
		log('file write error');
		FileClose(iDownloadFileHandle);
		iDownloadFileHandle:=-2;
		setCmd(REJECT_REQUEST_RECEIVE_FILE,4);
		j:=swapendian(j);
		fillData(@j,4);
		result:= send(skt,outbuf[0],outbufsize,0);
		checkdisconnect(result);
	end;
	dec(fileBlockCount);
	receivedfilesize:=receivedfilesize+payloadsize;
	log('file receive wrote:'+Inttostr(receivedfilesize));
	if receivedfilesize=actualfilesize then
	begin
		log('file receive done.');
		FileClose(iDownloadFileHandle);
	
	end
	else
  if fileBlockCount=0 then
	begin
		fileBlockCount:=FILEBLOCKS;
		setCmd(NEXT_BLOCK_FILE_DATA,4);
		j:=FILEBLOCKS;
		fillData(@j,4);
		result:= send(skt,outbuf[0],outbufsize,0);
		checkdisconnect(result);
	end;
end;
function Tatermisworker.sendFileData():integer;
var
	j:integer;
begin
  if remoteBlockCount=0 then
	 exit(0);
  EnterCriticalSection(sendCSec);
  try
		repeat
    	j:=FileRead(iUploadFileHandle,outbuf[5],BUFSIZE);
    	if (j=-1) or (j=0) then
    	begin
    	  FileClose(iUploadFileHandle);
    		iUploadFileHandle:=-2;
    	  exit(-101);
    	end;
      result := setCmd(FILE_CONTENT,j);
    	if result<0 then
        exit(-102);
    	//result := fillData( @outbuf[0], j );
			outbufsize:=outbufsize+j;
			result:= send(skt,outbuf[0],outbufsize,0);
			checkdisconnect(result);
    	if result<0 then
        exit(-102);
			dec(remoteBlockCount);
			iUploadCurrentFileSize:=iUploadCurrentFileSize+j;
			filepercent:=round(double(iUploadCurrentFileSize) / double(iUploadFileSize) * 100);
		until  (j<BUFSIZE) or (remoteBlockCount=0);
		if (j<BUFSIZE) then
		begin
		  log('file send done!!');
			FileClose(iUploadFileHandle);
			iUploadFileHandle:=-2;
		end;
  finally
    LeaveCriticalSection(sendCSec);
  end;
  result := 0;
end;
end.

