/* Observe only IDMan.exe windows in the isolated reference bottle. */
#include <windows.h>
#include <stdio.h>
#include <commctrl.h>
#include <string.h>
static const char *capture_directory;
static int capture_count;
static int quiet, dismiss;
static int text_reads;
static void read_control_text(HWND w,char *text,int capacity) {
    text_reads++;GetWindowTextA(w,text,capacity);
}
static BOOL CALLBACK child(HWND w,LPARAM unused) {
    char text[2048]={0},cls[128]={0};
    GetClassNameA(w,cls,sizeof cls);
    /* Do not read edit controls: registration/credential fields are not evidence. */
    if(!strcmp(cls,"Edit"))return TRUE;
    read_control_text(w,text,sizeof text);
    if(!strcmp(cls,"SysListView32")&&GetDlgCtrlID(w)==1177)printf("CONNECTION_ROWS %ld\n",(long)SendMessageA(w,LVM_GETITEMCOUNT,0,0));
    if(text[0]&&strcmp(cls,"Edit"))printf("CONTROL %d %s %s\n",GetDlgCtrlID(w),cls,text);
    return TRUE;
}
static void capture(HWND w) {
    RECT rect;GetWindowRect(w,&rect);int width=rect.right-rect.left,height=rect.bottom-rect.top;
    if(width<=0||height<=0||width>4000||height>3000)return;
    HDC source=GetWindowDC(w),target=CreateCompatibleDC(source);
    BITMAPINFO info={0};info.bmiHeader.biSize=sizeof(BITMAPINFOHEADER);info.bmiHeader.biWidth=width;
    info.bmiHeader.biHeight=-height;info.bmiHeader.biPlanes=1;info.bmiHeader.biBitCount=32;info.bmiHeader.biCompression=BI_RGB;
    void *pixels=NULL;HBITMAP bitmap=CreateDIBSection(target,&info,DIB_RGB_COLORS,&pixels,NULL,0);
    if(!bitmap){DeleteDC(target);ReleaseDC(w,source);return;}
    HGDIOBJ previous=SelectObject(target,bitmap);BOOL rendered=PrintWindow(w,target,0);
    if(rendered){char path[2048];snprintf(path,sizeof path,"%s\\idm-window-%d.bmp",capture_directory,capture_count++);
        FILE *file=fopen(path,"wb");if(file){BITMAPFILEHEADER header={0};header.bfType=0x4d42;
            header.bfOffBits=sizeof header+sizeof(BITMAPINFOHEADER);header.bfSize=header.bfOffBits+width*height*4;
            fwrite(&header,sizeof header,1,file);fwrite(&info.bmiHeader,sizeof info.bmiHeader,1,file);fwrite(pixels,width*height*4,1,file);fclose(file);printf("CAPTURE %s\n",path);}}
    SelectObject(target,previous);DeleteObject(bitmap);DeleteDC(target);ReleaseDC(w,source);
}
static BOOL CALLBACK visit(HWND w,LPARAM unused) {
    DWORD pid=0;GetWindowThreadProcessId(w,&pid);HANDLE process=OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION,FALSE,pid);
    if(!process)return TRUE;char path[1024];DWORD length=sizeof path;
    int own=QueryFullProcessImageNameA(process,0,path,&length)&&strstr(path,"IDMan.exe");CloseHandle(process);
    if(!own)return TRUE;char title[512]={0},cls[128]={0};GetWindowTextA(w,title,sizeof title);GetClassNameA(w,cls,sizeof cls);
    if(!quiet)printf("WINDOW %p visible=%d class=%s title=%s\n",w,IsWindowVisible(w),cls,title);
    if(dismiss&&IsWindowVisible(w)&&!strcmp(cls,"#32770")) {
        char message[2048]={0};GetDlgItemTextA(w,65535,message,sizeof message);
        if(strstr(message,"days left to use Internet Download Manager")&&GetDlgItem(w,IDNO)) {
            PostMessageA(w,WM_COMMAND,MAKEWPARAM(IDNO,BN_CLICKED),(LPARAM)GetDlgItem(w,IDNO));printf("ACTION Declined standard registration reminder\n");
        }
        GetDlgItemTextA(w,1731,message,sizeof message);
        if(strstr(message,"Administrator privileges")&&GetDlgItem(w,IDOK)) {
            PostMessageA(w,WM_COMMAND,MAKEWPARAM(IDOK,BN_CLICKED),(LPARAM)GetDlgItem(w,IDOK));printf("ACTION Acknowledged administrator warning\n");
        }
        if(!strcmp(title,"Download complete")&&GetDlgItem(w,1079))PostMessageA(w,WM_COMMAND,MAKEWPARAM(1079,BN_CLICKED),(LPARAM)GetDlgItem(w,1079));
    }
    if(!quiet&&IsWindowVisible(w))EnumChildWindows(w,child,0);
    if(capture_directory&&!strcmp(cls,"#32770")&&(strstr(title,"Internet Download Manager")||strstr(title,".dmg")))capture(w);
    return TRUE;
}
static int self_test(void) {
    HWND edit=CreateWindowExA(0,"Edit","private-test-sentinel",0,0,0,100,20,NULL,NULL,GetModuleHandle(NULL),NULL);
    HWND label=CreateWindowExA(0,"Static","public-test-label",0,0,0,100,20,NULL,NULL,GetModuleHandle(NULL),NULL);
    if(!edit||!label){fprintf(stderr,"FAIL could not create test controls\n");return 1;}
    text_reads=0;child(edit,0);
    if(text_reads!=0){fprintf(stderr,"FAIL Edit text was read\n");return 1;}
    child(label,0);
    if(text_reads!=1){fprintf(stderr,"FAIL Static text was not read\n");return 1;}
    DestroyWindow(edit);DestroyWindow(label);
    puts("PASS observer skips Edit text reads and retains Static output");return 0;
}
int main(int argc,char **argv){
    if(argc>1&&!strcmp(argv[1],"--self-test"))return self_test();
    if(argc>2&&!strcmp(argv[1],"--guard")) {
        quiet=dismiss=1;setbuf(stdout,NULL);
        while(GetFileAttributesA(argv[2])==INVALID_FILE_ATTRIBUTES){EnumWindows(visit,0);Sleep(200);}
    } else {capture_directory=argc>1?argv[1]:NULL;EnumWindows(visit,0);}
    return 0;
}
