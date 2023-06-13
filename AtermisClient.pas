unit AtermisClient;
interface
uses
  Types,
  {$ifdef unix}cthreads, {$endif}
{$IFDEF WINDOWS}
  winsock2,windows,
{$ENDIF}
  SysUtils,Classes,dateutils,syncobjs,atermisworker;
const
  BUFSIZE=4096;
  {$IFDEF unix}
    {$DEFINE TSOCKET := Integer}
  	{$DEFINE closesocket:=close}
  	INVALID_SOCKET = -1;
  	SOCKET_ERROR = -1;
  {$ENDIF}
type

TAtermisClient = class(Tatermisworker)
	public
    perhapsbeclosed:boolean;
		serverhost:string;
		serverport:integer;
		
	  function ConnectTo(servIP:string;PORT,itimeout:integer):integer;
    procedure sendOut(data:pbyte;size:integer);
  private
    timeouts:integer;
  protected
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
function TAtermisClient.ConnectTo(servIP:string;PORT,itimeout:integer):integer;
var
  wsd:WSADATA;
  ret:integer;
  server:sockaddr_in;
  cTimeOut:integer;
  ul,ul1:uint32;
  timeout:Ttimeval;
  r:Tfdset;
begin
  if (WSAStartup(MAKEWORD(2,0),wsd)<0) then 
	 exit(-11);
  skt:=socket(AF_INET,SOCK_STREAM,IPPROTO_TCP);
  
  if (skt=INVALID_SOCKET) then
     exit(-2);
  //set Recv and Send time out
  //cTimeOut:=6000; //设置发送超时6秒
  //if(setsockopt(skt,SOL_SOCKET,SO_SNDTIMEO,@cTimeOut,sizeof(TimeOut))=SOCKET_ERROR) then
  //begin
  //  exit(-1);
  //end;
  //cTimeOut:=6000;//设置接收超时6秒
  //if(setsockopt(skt,SOL_SOCKET,SO_RCVTIMEO,@cTimeOut,sizeof(TimeOut))=SOCKET_ERROR) then
  //begin
  //  exit(-1);
  //end;
  //设置非阻塞方式连接
  ul := 1;
  ret := ioctlsocket(skt, long(FIONBIO), @ul);
  if(ret<>NO_ERROR) then 
	 exit(-3);
  

  server.sin_family := AF_INET;
  server.sin_port := htons(port);
  server.sin_addr .s_addr := inet_addr(PAnsiChar(GetIPByName(servIP)));
  if (server.sin_addr.s_addr = INADDR_NONE) then 
	 exit(-1);

  ret:=connect(skt,@server,sizeof(sockaddr_in));
  //if ret<0 then
  //begin
  //  ret:=WSAGetLastError;
  //  exit(-12);
  //end;
  //
  //select 模型，即设置超时
  
  FD_ZERO(r);
  FD_SET(skt, r);
  timeout.tv_sec := itimeout; //连接超时 itimeout 秒
  timeout.tv_usec :=0;
  ret := select(0, nil, @r, nil, @timeout);
  if ( ret <= 0 ) then
  begin
    closesocket(skt);
		skt:=-1;
    exit(-4);
  end;
  //一般非锁定模式套接比较难控制，可以根据实际情况考虑 再设回阻塞模式
  ul1 := 0 ;
  ret := ioctlsocket(skt, long(FIONBIO), @ul1);
  if (ret<>NO_ERROR) then
  begin
    closesocket(skt);
		skt:=-1;
    exit(-5);
  end;
  //writeln(stdout,'connect done skt=',skt);
  perhapsbeclosed:=false;
  result:=0;
	serverhost:=servIP;
	serverport:=port;
end;
procedure TAtermisClient.sendOut(data:pbyte;size:integer);
begin
  send(skt,data,size,0);
end;

end.
//
// 一、方法分析
// 
//
//在Linux环境下gethostbyname函数是用来向DNS查询一个域名的IP地址。 由于DNS的查询方式是递归查询，在网络不通的情况下会导致gethostbyname函数在查询一个域名时出现严重超时问题。而该函数又不能像connect和read等函数那样通过setsockopt或者select函数那样设置超时时间，因此常常成为程序开发的瓶颈。
//
//在多线程环境下，gethostbyname会出现一个非常严重的问题，就是如果有一个线程的gethostbyname发生阻塞，其它线程都会在gethostbyname处发生阻塞，直到该线程的gethostbyname函数返回为止。针对这样的问题我们应该怎么处理呢？
//
//下面介绍两种方法：
//
//1、      使用alarm设定信号，如果超时就用sigsetjmp和siglongjmp跳过gethostbyname函数。
//
//2、      独立开启一个线程来调用gethostbyname函数，该线程除了调用此函数外，不做任何事情。
// 
//
//二、方法介绍
//
//1、alarm设定信号方法
//
//    (1)、sigsetjmp和siglongjmp概述
//
//        sigsetjmp:  参数为非0的时候，会保存进程的当前信号屏蔽字
//
//        siglongjmp: 恢复保存的信号屏蔽字
//
//    (2)、使用方法
//
//    #include <setjmp.h>
//    #include <time.h>
//     
//    static sigjmp_buf jmpbuf;
//    static void alarm_func()
//    {
//         siglongjmp(jmpbuf, 1);
//    }
//     
//    static struct hostent *gngethostbyname(char *HostName, int timeout)
//    {
//         struct hostent *lpHostEnt;
//     
//         signal(SIGALRM, alarm_func);
//         if(sigsetjmp(jmpbuf, 1) != 0)
//         {
//               alarm(0); /* 取消闹钟 */
//               signal(SIGALRM, SIG_IGN);
//               return NULL;
//         }
//         alarm(timeout); /* 设置超时时间 */
//         lpHostEnt = gethostbyname(HostName);
//         signal(SIGALRM, SIG_IGN);
//     
//         return lpHostEnt;
//    }
//
//2、多线程方法
//
//    #include <stdio.h>
//    #include <stdlib.h>
//    #include <netdb.h>
//    #include <pthread.h>
//      
//      
//     char address[64] = {"0.0.0.0"};
//     
//     void *_GetHostName2Ip(void *HostName)
//     {
//          char *pstHostName = NULL;
//     
//          struct hostent *hptr;
//     
//          pstHostName = (char *)HostName;
//          hptr = gethostbyname(pstHostName);
//          if(NULL == hptr)
//          {
//              pthread_exit(-1);
//          }
//         
//          inet_ntop(hptr->h_addrtype, hptr->h_addr, address, 32);
//          pthread_exit(0);
//    }
//
//    int main()
//    {
//         int kill_err = 0;
//         static char cHostName[256]; /* 域名地址，根据需要自己设定 */
//     
//         pthread_t gethostname;
//        
//         kill_err = pthread_kill(gethostname, 0);
//         if(ESRCH == kill_err) /* 判断线程是否存在 */
//         {
//             pthread_create(&gethostname, NULL, _GetHostName2Ip, (void *)cHostName);
//         }
//         else if(EINVAL == kill_err) /* 信号非法 */
//         {
//             return -1;
//         }
//     
//        printf("address = %s\n", address);
//
//        return 0;
//     }
//
//
	

//#include <stdio.h>
//#include <sys/socket.h>
//#include <netdb.h>
//#include <arpa/inet.h>
//void print_family(struct addrinfo *aip)
//{
//    printf("Family:");
//    switch (aip->ai_family) {
//    case AF_INET:
//        printf("inet");
//        break;
//    case AF_INET6:
//        printf("inet6");
//        break;
//    case AF_UNIX:
//        printf("unix");
//        break;
//    case AF_UNSPEC:
//        printf("unspecified");
//        break;
//    default:
//        printf("unknown");
//    }
//}
//void print_type(struct addrinfo *aip)
//{
//    printf(" Type:");
//    switch (aip->ai_socktype) {
//    case SOCK_STREAM:
//        printf("stream");
//        break;
//    case SOCK_DGRAM:
//        printf("datagram");
//        break;
//    case SOCK_SEQPACKET:
//        printf("seqpacket");
//        break;
//    case SOCK_RAW:
//        printf("raw");
//        break;
//    default:
//        printf("unknown (%d)", aip->ai_socktype);
//    }
//}
//void print_protocol(struct addrinfo *aip)
//{
//    printf(" Protocol:");
//    switch (aip->ai_protocol) {
//    case 0:
//        printf("default");
//        break;
//    case IPPROTO_TCP:
//        printf("TCP");
//        break;
//    case IPPROTO_UDP:
//        printf("UDP");
//        break;
//    case IPPROTO_RAW:
//        printf("raw");
//        break;
//    default:
//        printf("unknown (%d)", aip->ai_protocol);
//    }
//}
//void print_flags(struct addrinfo *aip)
//{
//    printf(" Flags:");
//    if (aip->ai_flags == 0) {
//        printf(" 0");
//    } else {
//        if (aip->ai_flags & AI_PASSIVE)
//            printf(" passive");
//        if (aip->ai_flags & AI_CANONNAME)
//            printf(" canon");
//        if (aip->ai_flags & AI_NUMERICHOST)
//            printf(" numhost");
//        if (aip->ai_flags & AI_NUMERICSERV)
//            printf(" numserv");
//        if (aip->ai_flags & AI_V4MAPPED)
//            printf(" v4mapped");
//        if (aip->ai_flags & AI_ALL)
//            printf(" all");
//    }
//}
//int main(int argc, char *argv[])
//{
//    if(argc != 2)
//    {
//        printf("ERROR: usage %s\n", argv[0]);
//        return 0;
//    }
//    struct addrinfo *ai, *aip;
//    struct addrinfo hint;
//    struct sockaddr_in *sinp;
//    const char *addr;
//    int err;
//    char buf[1024];
//    hint.ai_flags = AI_CANONNAME;
//    hint.ai_family = 0;
//    hint.ai_socktype = 0;
//    hint.ai_protocol = 0;
//    hint.ai_addrlen = 0;
//    hint.ai_canonname = NULL;
//    hint.ai_addr = NULL;
//    hint.ai_next = NULL;
//    if((err = getaddrinfo(argv[1], NULL, &hint, &ai)) != 0)
//        printf("ERROR: getaddrinfo error: %s\n", gai_strerror(err));
//    for(aip = ai; aip != NULL; aip = aip->ai_next)
//    {
//        print_family(aip);
//        print_type(aip);
//        print_protocol(aip);
//        print_flags(aip);
//        printf("\n");
//        printf("Canonical Name: %s\n", aip->ai_canonname);
//        if(aip->ai_family == AF_INET)
//        {
//            sinp = (struct sockaddr_in *)aip->ai_addr;
//            addr = inet_ntop(AF_INET, &sinp->sin_addr, buf, sizeof buf);
//            printf("IP Address: %s ", addr);
//            printf("Port: %d\n", ntohs(sinp->sin_port));
//        }
//        printf("\n");
//    }
//    return 0;
//}


//#include <stdio.h>
//#include <netinet/in.h>
//#include <sys/socket.h>
//#include <arpa/inet.h>
//#include <string.h>
//#include <netdb.h>
//
//int main(void)
//{
//  struct hostent *stHost = (struct hostent *)NULL;
//  struct in_addr stInAddr, stTempInAddr;
//  int nRet = 0, idx = -1;
//  struct sockaddr_in stSkAddr;
//
//  bzero((void *)&stInAddr, sizeof(struct in_addr));
//  nRet = inet_aton("127.0.0.1", &stInAddr);
//
//  stHost = gethostbyaddr(&stInAddr, \
//    sizeof(struct in_addr), AF_INET);
//  if (stHost == (struct hostent *)NULL) {
//    herror("gethostbyaddr");
//    return 1;
//  }
//
//  printf("gethostbyaddr(): \n");
//  printf("stHost->h_name: %s \n", stHost->h_name);
//  printf("\n");
//
//  idx = 0;
//  do {
//    printf("stHost->h_aliases: %s \n", \
//      stHost->h_aliases[idx++]);
//  } while (stHost->h_aliases[idx] != (char *)NULL);
//  printf("\n");
//
//  printf("stHost->h_addrtype = %d \n", stHost->h_addrtype);
//  printf("stHost->h_length = %d \n", stHost->h_length);
//  printf("\n");
//
//  idx = 0;
//  do {
//    printf("stHost->h_addr_list: %s \n", \
//      stHost->h_addr_list[idx++]);
//  } while (stHost->h_addr_list[idx] != (char *)NULL);
//  // 在<netdb.h>中有定義h_addr就是h_addr_list[0]!! 
//  bzero((void *)&stTempInAddr, sizeof(struct in_addr));
//  bzero((void *)&stSkAddr, sizeof(struct sockaddr_in));
//  memcpy(&stSkAddr.sin_addr.s_addr, stHost->h_addr, 4);
//  stTempInAddr.s_addr = stSkAddr.sin_addr.s_addr;
//  printf("IP Address: %s \n", inet_ntoa(stTempInAddr));
//
//  return 0;
//}

// 代码审计公司 Qualys 的研究人员在 glibc 库中的__nss_hostname_digits_dots() 函数中发现了一个缓冲区溢出的漏洞，这个 bug 可以经过 gethostbyname*() 函数被本地或者远程的触发。
// 
// 1）通过 gethostbyname() 函数或 gethostbyname2() 函数，将可能产生一个堆上的缓冲区溢出。经由 gethostbyname_r() 或 gethostbyname2_r()，则会触发调用者提供的缓冲区溢出 (理论上说，调用者提供的缓冲区可位于堆，栈，.data 节和.bss 节等。但是，我们实际操作时还没有看到这样的情况)。
// 
// 2）漏洞产生时至多 sizeof(char* ) 个字节可被覆盖 (注意是 char*指针的大小，即 32 位系统上为 4 个字节，64 位系统为 8 个字节)。但是 payload 中只有数字 ( '0 '...' 9') ，点 ( “.”) ，和一个终止空字符 ('\0' ) 可用。
// 
// 3）尽管有这些限制，我们依然可以执行任意的代码。
// #include <netdb.h>
// #include <stdio.h>
// #include <stdlib.h>
// #include <string.h>
// #include <errno.h>
// #include <gnu/libc-version.h>
// #define CANARY "in_the_coal_mine"
// struct {
// char buffer[1024];
// char canary[sizeof(CANARY)];
// } temp = { "buffer", CANARY };
// int main(void) {
// struct hostent resbuf;
// struct hostent *result;
// int herrno;
// int retval;
// /*** strlen (name) = size_needed - sizeof (*host_addr) - sizeof (*h_addr_ptrs) - 1; ***/
// size_t len = sizeof(temp.buffer) - 16*sizeof(unsigned char) - 2*sizeof(char *) - 1;
// char name[sizeof(temp.buffer)];
// memset(name, '0', len);
// name[len] = '\0';
// retval = gethostbyname_r(name, &resbuf, temp.buffer, sizeof(temp.buffer), &result, &herrno);
// if (strcmp(temp.canary, CANARY) != 0) {
// puts("vulnerable");
// exit(EXIT_SUCCESS);
// }
// if (retval == ERANGE) {
// puts("not vulnerable");
// exit(EXIT_SUCCESS);
// }
// puts("should not happen");
// exit(EXIT_FAILURE);
// }
