unit UIfileTrans;

{$MODE Delphi}

interface

uses
  LCLIntf, LCLType, LMessages, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs,header,
  winsock,socketfunc, Grids, ComCtrls;

type
  TfrmUIFileTrans = class(TForm)
    sg1: TStringGrid;
    pb1: TProgressBar;
    procedure FormShow(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
  private
    FCCmd:TCTLCmd;
    filesizes:integer;
    transfering,hasclose,hasBreaking:boolean;
    { Private declarations }
    procedure HandleFILEMSG(var Msg: TMessage) ; message WM_FileTransfer;
		procedure FILEACCEPT(var Msg: TMessage) ;
		procedure FILERESUME(var Msg: TMessage) ;
		procedure FILENEXT(var Msg: TMessage) ;
		procedure FILEERROR(var Msg: TMessage) ;
    procedure FILEFINISH(var Msg: TMessage) ;
  public
    curFile,socketid:integer;
    { Public declarations }
  end;

var
  frmUIFileTrans: TfrmUIFileTrans;

implementation

{$R *.lfm}
procedure TfrmUIFileTrans.HandleFILEMSG(var Msg: TMessage);
begin
  case msg.WParam of
    FILETRANS_ERROR:
      FILEERROR(msg);
    FILETRANS_REJECT:
      FILEERROR(msg);
    FILETRANS_ACCEPT:
      FILEACCEPT(msg);
    FILETRANS_NEXT:
      FILENEXT(msg);
    FILETRANS_RESUME:
      FILERESUME(msg);
    FILETRANS_FINISH:
      FILEFINISH(msg);
  end;
end;
procedure TfrmUIFileTrans.FILEFINISH(var Msg: TMessage);
begin
	transfering:=false;
  caption:=inttostr(msg.LParam);
  close;
end;
procedure TfrmUIFileTrans.FILEERROR(var Msg: TMessage);
begin
	transfering:=false;
  caption:=inttostr(msg.LParam);
end;
procedure TfrmUIFileTrans.FILENEXT(var Msg: TMessage);
begin
	inc(curFile);
  Caption:='Next :'+inttostr(curFile)+' and '+inttostr(sg1.RowCount);
  if curFile=sg1.RowCount then
  begin
    FCCmd.Cmd := FILETRANS_FINISH;
    send(socketid,FCCmd, SizeOf(TCtlCmd),0);
    Caption:='ALL file done!';
    close;
    exit;
  end;
	FILEACCEPT(msg);
end;
procedure TfrmUIFileTrans.FILERESUME(var Msg: TMessage);
var
	fileid,i,j,k,l:integer;
	pBuf: array[0..8191] of Byte;
  Filedone:boolean;
begin
	fileid:=fileopen(sg1.Cells[0,curFile],fmOpenRead);
	FileSeek(fileid,0,0);
	if Msg.LParam>0 then
	begin
		j:=fileseek(fileid,Msg.WParam,0);
		if (j<>Msg.LParam) then
		begin
			Filedone:=true;
		end;
	end;
	if Filedone then
	begin
	  FCCmd.Cmd := FILETRANS_ERROR;
	  FCCmd.X := FILESIZEMISMATCH;
	  send(socketid,FCCmd, SizeOf(TCtlCmd),0);
    exit;
	end;
  transfering:=true;
  try
    repeat
      i:=fileread(fileid,pbuf[0],4096);
      FCCmd.Cmd := FILETRANS_DATA;
      FCCmd.X := i;
      send(socketid,FCCmd, SizeOf(TCtlCmd),0);
      j:=send(socketid,pbuf[0],i,0);
			if j=-1 then
			begin
				hasClose:=true;
				break;
			end;
      while i>j do
      begin
    	  sleep(100);
    	  k:=i-j;
				l:=send(socketid,pbuf[j],k,0);
				if l=-1 then
				begin
					hasClose:=true;
					break;
				end;
    	  j:=j+l
      end;
      pb1.Position:=pb1.Position+i;
      application.ProcessMessages;
    until (not transfering) or (i<4096);
  except
    on e:Exception  do
    begin
      if i=-1 then
      begin
        FCCmd.Cmd := FILETRANS_ERROR;
        FCCmd.X :=e.HelpContext;
        send(socketid,FCCmd, SizeOf(TCtlCmd),0);
        exit;
      end;
    end;
  end;
  FileClose(fileid);
  sg1.Cells[1,curFile]:='Done';
  if hasBreaking then
  begin
    FCCmd.Cmd := FILETRANS_BREAK;
    send(socketid,FCCmd, SizeOf(TCtlCmd),0);
  end;
  if hasClose then
  begin
    close;
  end;
end;
procedure TfrmUIFileTrans.FILEACCEPT(var Msg: TMessage);
var
	s:string;
  test: Trect;
begin
	s :=extractfilename(sg1.cells[0,curFile]);
	filesizes:=WideFileSize(sg1.cells[0,curFile]);
	if filesizes=-1 then
	begin
    exit;
	end;
  pb1.Max:=filesizes;
  pb1.Position:=0;
  test:=sg1.CellRect(1,curFile);
  pb1.SetBounds(test.Left+1,test.Top+1,test.Right - test.Left -1 ,test.Bottom - test.Top -1);
  pb1.Visible:=true;
  caption:='Accept Transfer';
  FCCmd.Cmd := FILETRANS_REQUEST;
  FCCmd.X := length(s);
  FCCmd.Y := filesizes;
  send(socketid,FCCmd, SizeOf(TCtlCmd),0);
  send(socketid,s[1], FCCmd.X,0);
end;
procedure TfrmUIFileTrans.FormShow(Sender: TObject);
begin
  curFile:=1;
  pb1.Visible:=false;
  hasClose:=false;
  transfering:=false;
  hasBreaking:=false;
end;

procedure TfrmUIFileTrans.FormClose(Sender: TObject;
  var Action: TCloseAction);
begin
  transfering:=false;
  hasBreaking:=true;
  hasClose:=true;
end;

end.
