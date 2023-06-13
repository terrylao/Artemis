unit AudioThread;

{$MODE Delphi}

interface
uses windows,LCLIntf, LCLType, LMessages, Messages, SysUtils, Variants, Classes, MMSystem, winsock , iLbcCodec,iLBC_define,header;

const

  MAXDELAYTIME   = 50;
  WAVINBUFCOUNT  = 4;
  WAVOUTBUFCOUNT = 4;

  MONO   = 1;
  STEREO = 2;
  CHANNELS = STEREO ;
  BPS = 16;
  ILBCNOOFWORDS_MAX = (NO_OF_BYTES_30MS div 2);
type
  shortArrayType = array[0..1024] of Smallint;
  PAshort = ^shortArrayType;
  TAudioRecvThread = class(TThread)
  protected
    FSpeakerOpen: Boolean;
    WavOutFmt: TWaveFormatEx;
    DevAudioOut: HWAVEOUT;
    WavOutHdr: array [0..WAVOUTBUFCOUNT-1] of WAVEHDR;
    WavOutBuf: PByteArray;
  public
  	AudioOutOpen: Boolean;
    p: PWAVEHDR;
    Buffer_size,socketid,block_size :integer;
    decoded_data:array [0..240*4-1] of Smallint;
    workCount:cardinal;
    constructor Create(hwin: HWND; ip,port:String);
    procedure Execute; override;
    function OpenAudioOut(): Integer;
	  procedure CloseAudioOut;
	  procedure StartAudioOut;
  end;

  TAudioSendThread = class(TThread)
  protected
    FPhoneOpen: Boolean;
    WavInFmt: TWaveFormatEx;
    DevAudioIn: HWAVEIN;
    WavInHdr: array [0..WAVINBUFCOUNT-1] of WAVEHDR;
    WavInBuf: PByteArray;
    FWindow:HWND;
  public
  	AudioInOpen: Boolean;
    p: PWAVEHDR;
    Buffer_size,socketid,block_size :integer;
    encoded_data:array [0..199] of byte;
    workCount:cardinal;
    constructor Create(hwin: HWND; ip,port:String);
    procedure Execute; override;
    function OpenAudioIn(): Integer;
    procedure CloseAudioIn;
    procedure StartAudioIn;
    procedure StopAudioIn;
  end;

{  function SetDelayTime(n: Integer): Integer;}

implementation

{uses AEC_Usage;}

var
  SendThreadID,RcvThreadID:integer;
	FWindow:HWND;
constructor TAudioRecvThread.Create(hwin: HWND; ip,port:String);
begin
  inherited Create(true);
  with WavOutFmt do
  begin
    wFormatTag:=WAVE_FORMAT_PCM;     // simple, uncompressed format
    nChannels:=CHANNELS;                    //  1=mono, 2=stereo
    nSamplesPerSec:=8000;
    wBitsPerSample:=BPS;              //  16 for high quality, 8 for telephone-grade
    nAvgBytesPerSec:=nSamplesPerSec* nChannels*wBitsPerSample div 8;   // = nSamplesPerSec * n.Channels * wBitsPerSample/8
    nBlockAlign:=nChannels * wBitsPerSample div 8;                  // = n.Channels * wBitsPerSample/8
    cbSize:=0; 
  end;
  RcvThreadID:=threadid;
  FreeOnterminate:=true;
  Fwindow:=hwin;
  DevAudioOut:=0;
  workCount:=0;
  Buffer_size := BLOCKL_MAX*8;//因為每次解都只解出一個block of smallint 的資料
  WavOutBuf := nil;
  block_size:=sizeof(Smallint)*Dec_Inst.blockl;
  OpenAudioOut();
  FSpeakerOpen := True;
end;

procedure TAudioRecvThread.Execute;
var i, j, n, len,pli: Integer;
    buf: array[0..Sizeof(Integer)-1] of Byte absolute n;
    ms: MSG;
    rcvBuf:array [0..199] of char;
begin
  while not Terminated do
  begin
    GetMessage(ms, 0, 0, 0);
    case ms.message of
      WM_RECVAUDIO:
      begin
        p := PWAVEHDR(ms.lParam);
        i := recv(socketid,rcvBuf[0],200,0);
        if i<1 then
        begin
        	PostMessage(FWindow, WM_STATEMESSAGE, errVoiceRecv, getLastError);
        	break;
        end;
        j:=i;
        while j<200 do
        begin
        	i := recv(socketid,rcvBuf[j],200-j,0);
	        if i<1 then
	        begin
	        	PostMessage(FWindow, WM_STATEMESSAGE, errVoiceRecv, 0);
	        	break;
	        end;
        	inc(j,i);
      	end;
        pli:=1;
    		len:=decode(@Dec_Inst,@decoded_data[0],len,@rcvBuf[0], 200, pli)*sizeof(smallint);
      	copymemory(@p^.lpData[0],@decoded_data[0],len);
				inc(workCount);
        if FSpeakerOpen then
        begin
          p^.dwFlags := 0;
          p^.dwBufferLength := len;
          p^.dwBytesRecorded := len;
          waveOutPrepareHeader(ms.wParam, p, Sizeof(WAVEHDR));
          waveOutWrite(ms.wParam, p, Sizeof(WAVEHDR));
        end;
				//PostMessage(FWindow, WM_DRAWWAVE, 0, 0);
        //synchronize(mainFrm.DrawWave);
      end;
      WM_TERMINATE: Terminate;
    end; // case
  end; // while
  PostMessage(FWindow, WM_STATEMESSAGE, mtVoiceRecvClose, 0);
	CloseAudioOut;
end;

constructor TAudioSendThread.Create(hwin: HWND; ip,port:String);
begin
  inherited Create(true);
  with WavInFmt do
  begin
    wFormatTag:=WAVE_FORMAT_PCM;     // simple, uncompressed format
    nChannels:=CHANNELS;                    //  1=mono, 2=stereo
    nSamplesPerSec:=8000;            // 8000,11025,22050,44100
    wBitsPerSample:=BPS;              //  16 for high quality, 8 for telephone-grade
    nAvgBytesPerSec:=nSamplesPerSec* nChannels*wBitsPerSample div 8;   // = nSamplesPerSec * n.Channels * wBitsPerSample/8
    nBlockAlign:=nChannels * wBitsPerSample div 8;                  // = n.Channels * wBitsPerSample/8
    cbSize:=0;
  end;
  SendThreadID:=Threadid;
  FreeOnterminate:=true;
  FWindow:=hwin;
  DevAudioIn:=0;
  workCount:=0;
  {公式:SamplesPerSec * 秒 * (BitsPerSample/8) * channel}
  Buffer_size := BLOCKL_MAX*sizeof(smallint)*4;//每次都收四個smallint block 的資料才送出去
  WavInBuf := nil;
  FPhoneOpen := True;
	{ Initialization }
	block_size:=sizeof(Smallint)*Enc_Inst.blockl;
  OpenAudioIn();
end;

procedure TAudioSendThread.Execute;
var i, j, n, len: Integer;
    //buf: array[0..Sizeof(Integer)-1] of Byte absolute len;
    ms: MSG;
    sendBuf: array [0..199] of char;
begin
  while not Terminated do
  begin
    GetMessage(ms, 0, 0, 0);
    case ms.message of
      WM_SENDAUDIO:
      begin
        p := PWAVEHDR(ms.lParam);
        //Synchronize(mainFrm.DrawSin);
        n := p^.dwBytesRecorded;
        len:=0;
        //copymemory(@indata[0],@p^.lpData[0], block_size);
        //AECIT(0,@inData[0],@data[0],block_size div 2);
        len:=encode(@Enc_Inst, @encoded_data, len,@p^.lpData[0],n);
        copymemory(@sendBuf[0],@encoded_data[0],len);
        i:=send(socketid,sendBuf[0], 200,0);
        if i<1 then
        begin
        	PostMessage(FWindow, WM_STATEMESSAGE, errVoiceSend, getLastError());
        	break;
        end;
        j:=i;
        while j<200 do
        begin
	        i:=send(socketid,sendBuf[j], 200-j,0);
	        if i<1 then
	        begin
	        	PostMessage(FWindow, WM_STATEMESSAGE, errVoiceSend, getLastError());
	        	break;
	        end;
	        inc(j,i);
      	end;
      	inc(workCount);
        p^.dwFlags := 0;
        p^.dwBytesRecorded := 0;
        p^.dwBufferLength := Buffer_size;
        waveInPrepareHeader(ms.wParam, p, Sizeof(WAVEHDR));
        waveInAddBuffer(ms.wParam, p, Sizeof(WAVEHDR));
        //Debug
        {Terminate;
        SendThreadID:=0;
        CloseAudioIn;
        Synchronize(mainFrm.DumpSend);}
      end;
      WM_TERMINATE: Terminate;
    end; // case
  end; // while
  PostMessage(FWindow, WM_STATEMESSAGE, mtVoiceSendClose, 0);
	CloseAudioIn;
end;


procedure WaveInProc(hw: HWAVEIN; ms: LongWord; ux: Cardinal; p1: PWAVEHDR; p2: Cardinal); far; stdcall;
begin
  if (ms = WIM_DATA) and (SendThreadID <> 0) then
  begin
    waveInUnprepareHeader(hw, p1, Sizeof(WAVEHDR));
    if not PostThreadMessage(SendThreadID, WM_SENDAUDIO, hw, Integer(p1)) then
    begin
    	PostMessage(FWindow, WM_STATEMESSAGE, errInPoc, 0);
    end;
  end;
end;

function TAudioSendThread.OpenAudioIn(): Integer;
var i: Integer;
begin
  if AudioInOpen then 
  	CloseAudioIn;
  Result := waveInOpen(@DevAudioIn, WAVE_MAPPER, @WavInFmt, Cardinal(@WaveInProc), 0, CALLBACK_FUNCTION);
  AudioInOpen := Result = MMSYSERR_NOERROR;
  if not AudioInOpen then Exit;
  GetMem(WavInBuf, Buffer_size * WAVINBUFCOUNT);
  for i := 0 to WAVINBUFCOUNT - 1 do
  begin
    WavInHdr[i].lpData := @(WavInBuf^[i*Buffer_size]);
    WavInHdr[i].dwBufferLength := Buffer_size;
    WavInHdr[i].dwBytesRecorded := 0;
    WavInHdr[i].dwFlags := 0;
    Result := waveInPrepareHeader(DevAudioIn, @WavInHdr[i], Sizeof(WAVEHDR));
    AudioInOpen := Result = MMSYSERR_NOERROR;
    if not AudioInOpen then
    begin
      waveInClose(DevAudioIn);
      FreeMem(WavInBuf, Buffer_size * WAVINBUFCOUNT);
      WavInBuf := nil;
      Exit;
    end;
    Result := waveInAddBuffer(DevAudioIn, @WavInHdr[i], Sizeof(WAVEHDR));
    AudioInOpen := Result = MMSYSERR_NOERROR;
    if not AudioInOpen then
    begin
      waveInClose(DevAudioIn);
      FreeMem(WavInBuf, Buffer_size * WAVINBUFCOUNT);
      WavInBuf := nil;
      Exit;
    end;
  end;
end;

procedure TAudioSendThread.CloseAudioIn;
begin
  if AudioInOpen then
  begin
  	SendThreadID:=0;
    if waveInStop(DevAudioIn)<>MMSYSERR_NOERROR then
    	exit;
    //這如果hang 住, 表示另一個thread 有在做wavein 的函數, 故deadlock了
    //因為在waveInReset which will generate another WIM_DATA and so on
    waveInReset(DevAudioIn);
    waveInClose(DevAudioIn);
    FreeMem(WavInBuf, Buffer_size * WAVINBUFCOUNT);
    WavInBuf := nil;
    AudioInOpen := False;
  end;
end;

procedure TAudioSendThread.StartAudioIn;
begin
  if AudioInOpen then waveInStart(DevAudioIn);
end;

procedure TAudioSendThread.StopAudioIn;
begin
  if AudioInOpen then waveInStop(DevAudioIn);
end;

procedure WaveOutProc(hw: HWAVEOUT; ms: Integer; ux: Cardinal; p1: PWAVEHDR; p2: Cardinal); far; stdcall;
begin
  if (ms = WOM_DONE) and (RcvThreadID<>0) then
  begin
    waveOutUnprepareHeader(hw, p1, Sizeof(WAVEHDR));
    if not PostThreadMessage(RcvThreadID, WM_RECVAUDIO, hw, Integer(p1)) then
    begin
    	PostMessage(FWindow, WM_STATEMESSAGE, errOutPoc, 0);
    end;
  end;  
end;

function TAudioRecvThread.OpenAudioOut(): Integer;
begin
  if AudioOutOpen then 
  	CloseAudioOut;
  GetMem(WavOutBuf, Buffer_size * WAVOUTBUFCOUNT);
  Result := waveOutOpen(@DevAudioOut, WAVE_MAPPER, @WavOutFmt, Cardinal(@WaveOutProc), 0, CALLBACK_FUNCTION);
  AudioOutOpen := Result = MMSYSERR_NOERROR;
  if not AudioOutOpen then
  begin
    FreeMem(WavOutBuf, Buffer_size * WAVOUTBUFCOUNT);
    WavOutBuf := nil;
  end;
end;

procedure TAudioRecvThread.CloseAudioOut;
begin
  if AudioOutOpen then
  begin
  	RcvThreadID:=0;
    waveOutReset(DevAudioOut);
    waveOutClose(DevAudioOut);
    FreeMem(WavOutBuf, Buffer_size * WAVOUTBUFCOUNT);
    WavOutBuf := nil;
    AudioOutOpen := False;
  end;
end;

procedure TAudioRecvThread.StartAudioOut;
var i,j: Integer;
  k:longbool;
begin
  if AudioOutOpen then 
  for i := 0 to WAVOUTBUFCOUNT - 1 do
  begin
    WavOutHdr[i].lpData := @(WavOutBuf^[i*Buffer_size]);
    WavOutHdr[i].dwBufferLength := Buffer_size;
    WavOutHdr[i].dwBytesRecorded := 0;
    WavOutHdr[i].dwFlags := 0;
    WavOutHdr[i].dwLoops := 1;
    k:=PostThreadMessage(ThreadID, WM_RECVAUDIO, DevAudioOut, Integer(@WavOutHdr[i]));
    if not k then
    begin
    	j:=GetLastError();
    	PostMessage(FWindow, WM_STATEMESSAGE, j, 0);
    end;
  end;
end;

end.
