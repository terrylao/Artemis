unit header;

{$MODE Delphi}

interface
uses
	Graphics,Messages,winsock,LCLIntf, LCLType, LMessages,sysutils;
const
  WM_LoadDone         = WM_USER + 22;
  WM_FileTransfer     = WM_USER + 23;
  WM_ShowError        = WM_USER + 24;
  
	WM_READSCREEN       = WM_USER + 31;
  WM_STARTSCREEN      = WM_USER + 36;
  WM_SPYSUSPEND       = WM_USER + 37;

	
	WM_DOLOGIN          = WM_USER + 100;
  WM_STATEMESSAGE     = WM_USER + 101;

  WM_VoiceStart       = WM_USER + 111;
  WM_VoiceTerminate   = WM_USER + 112;
	WM_VoiceReject      = WM_USER + 113;
	WM_VoiceFailConnect = WM_USER + 114;

  WM_SENDAUDIO        = WM_USER + 121;
  WM_RECVAUDIO        = WM_USER + 122;
  WM_TERMINATE        = WM_USER + 123;
	WM_DRAWWAVE         = WM_USER + 124;
	
	WM_UndesiredMsg     = WM_USER + 199;

  mtListenStart       = 1;
  mtListening         = 2;

  mtListenClose       = 4;
  mtConnecting        = 5;

  mtRecvStart         = 7;

  mtRecvClose         = 9;
  mtSendStart         = 10;

  mtSendClose         = 12;
  mtRefused           = 13;
  mtInvConnect        = 14;
  mtMustSelIP         = 15;
  mtPeerBusy          = 16;

  mtConnected         = 19;
  mtLogined           = 20;
  mtIdle              = 21;
  mtWorking           = 22;

	mtVoiceConnected    = 27;
	mtVoiceDisconnected = 28;
	mtVoiceReject       = 31;
	mtVoiceTerminate    = 32;
	mtVoiceRecvClose    = 35;
	mtVoiceSendClose    = 36;
	
	errRecv              = -11;
	errSend              = -12;
	errListen            = -13;
	errConnect           = -14;
	
	errCreateVoiceSocket = -21;
	errAcceptVoiceSocket = -22;
	errVoiceRecv         = -23;
	errVoiceSend         = -24;
	
	errFileRead          = -31;
	errFileWrite         = -32;
	errFileCreate        = -33;
	errFileOpen          = -34;
	
	errExceed8K          = -41;
	
  errOutPoc            = -51;
  errInPoc             = -52;
	
	errReadScreen        = -91;
	errSpySend           = -92;
	errSpyExpt           = -93;
  errSpyGetScreen      = -94;
	errUnknowCMD         = -99;

  MOUSE_MOVE          = 1;
  LEFTDOWN            = 2;
  RIGHTDOWN           = 3;
  LEFTUP              = 4;
  RIGHTUP             = 5;
  KEYB_DOWN           = 6;
  KEYB_UP             = 7;
	
	LOGIN               = 10; //follow the length of password in X that less then 8k bytes
	FIRSTSCREEN         = 11;//follow the size of this screen and color depth
	NEXTSCREEN          = 12;//follow the size of this frame
	SUSPENSCREEN        = 13;
	RESUMESCREEN        = 14;
	LOGIN_ACCEPT        = 15;

  START_SPY           = 20;//follow the colordepth of client screen
  SERVER_CLOSED       = 21;
  STOP_SPY            = 22;//client read this for next screen
	ACTIVE_SERVER       = 23;
  SUSPEND_SPY         = 24;
  RESUME_SPY          = 25;
	CLIPBOARD_TRANSFER  = 26;
  CLOSE_SERVICE       = 27;
	
  FILETRANS_BEGIN     = 30;
  FILETRANS_REJECT    = 31;
  FILETRANS_REQUEST   = 32;//x=filename length, y=file size, follow by filename max length 1k
  FILETRANS_ACCEPT    = 33;
  FILETRANS_ERROR     = 34;
  FILETRANS_NEXT      = 35;
  FILETRANS_FINISH    = 36;
	FILETRANS_FINISHED  = 37;
  FILETRANS_RESUME    = 38;//x=start append position
  FILETRANS_START     = 39;
	FILETRANS_DATA      = 40;//x=remain size, follow with data for initialer
	FILESIZEMISMATCH    = 41;
  FILETRANS_BREAK     = 42;
	
  VOICE_REQUEST       = 51;//for Server X is the port it binded, for client X set to 0
	VOICE_ACCEPT        = 52;
	VOICE_READY         = 53;
	VOICE_REJECT        = 54;
	VOICE_CLOSE         = 59;
{
initiator Bind            Adapter
  --VOICE_REQUEST(X=port)-->
  <--VOICE_ACCEPT(X=port)--
	--VOICE_READY-->
	<===Connect to Port===
  <-----Voice until one side closesocket or nothing arrive in 2 seconds or Voice_Close----->
initiator                 Adapter Bind
  --VOICE_REQUEST(X=0)-->
	<--VOICE_ACCEPT(X=Port)--
	<--VOICE_READY--
	===Connect to Port===>
	<-----Voice until one side closesocket or nothing arrive in 2 seconds or Voice_Close----->
}
	
  {
Client                 Server
Server                 Client
  --FILETRANS_BEGIN-->
  
  <--FILETRANS_ACCEPT--
Start:
  --FILETRANS_REQUEST-->
  
  <--FILETRANS_RESUME--
  
  --FILETRANS_DATA-->  block of data(max 4KB) transfer once at time
  
  when transfer finish with filesize....
  
  <--FILETRANS_NEXT--
  go back to "Start" if complete all files transfer then
  
  --FILETRANS_FINISH-->
  }
type
  PCtlCmd = ^TCtlCmd;
  TCtlCmd = record
    Cmd:  integer;
    X, Y: integer;
  end;
implementation
end.