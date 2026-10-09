import Foundation
import Darwin
import IDMCore

func configuration(_ path:URL) throws -> BrowserBridgeConfiguration {
    let attrs=try FileManager.default.attributesOfItem(atPath:path.path)
    guard (attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600,
          (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
          attrs[.type] as? FileAttributeType == .typeRegular else { throw BrowserProtocolError.invalid }
    let value=try JSONDecoder().decode(BrowserBridgeConfiguration.self,from:Data(contentsOf:path))
    guard value.port > 0,value.token.count >= 32 else { throw BrowserProtocolError.invalid };return value
}
func listening(_ config:BrowserBridgeConfiguration) -> Bool {
    let fd=socket(AF_INET,SOCK_STREAM,0);guard fd >= 0 else { return false };defer { close(fd) }
    var address=sockaddr_in();address.sin_len=UInt8(MemoryLayout<sockaddr_in>.size);address.sin_family=sa_family_t(AF_INET);address.sin_port=config.port.bigEndian;address.sin_addr.s_addr=inet_addr("127.0.0.1")
    return withUnsafePointer(to:&address) { $0.withMemoryRebound(to:sockaddr.self,capacity:1) { connect(fd,$0,socklen_t(MemoryLayout<sockaddr_in>.size)) == 0 } }
}
func forward(_ request:BrowserRequest,config:BrowserBridgeConfiguration) throws -> BrowserResponse {
    let fd=socket(AF_INET,SOCK_STREAM,0);guard fd >= 0 else { throw BrowserProtocolError.invalid };defer { close(fd) }
    var noSig:Int32=1;setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&noSig,socklen_t(MemoryLayout.size(ofValue:noSig)))
    var timeout=timeval(tv_sec:150,tv_usec:0)
    setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,socklen_t(MemoryLayout.size(ofValue:timeout)))
    setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,socklen_t(MemoryLayout.size(ofValue:timeout)))
    var address=sockaddr_in();address.sin_len=UInt8(MemoryLayout<sockaddr_in>.size);address.sin_family=sa_family_t(AF_INET);address.sin_port=config.port.bigEndian;address.sin_addr.s_addr=inet_addr("127.0.0.1")
    let connected=withUnsafePointer(to:&address) { $0.withMemoryRebound(to:sockaddr.self,capacity:1) { connect(fd,$0,socklen_t(MemoryLayout<sockaddr_in>.size)) } };guard connected == 0 else { throw BrowserProtocolError.invalid }
    let message=try NativeMessageFrame.encode(JSONEncoder().encode(BrowserEnvelope(token:config.token,request:request)))
    try message.withUnsafeBytes { bytes in var offset=0;while offset<bytes.count { let n=send(fd,bytes.baseAddress!.advanced(by:offset),bytes.count-offset,0);if n<0 && errno == EINTR { continue };guard n>0 else { throw BrowserProtocolError.invalid };offset += n } }
    let handle=FileHandle(fileDescriptor:fd,closeOnDealloc:false)
    guard let bytes=try NativeMessageFrame.read(from:handle) else { throw BrowserProtocolError.invalid }
    let response=try JSONDecoder().decode(BrowserResponse.self,from:bytes);guard response.id == request.id else { throw BrowserProtocolError.invalid };return response
}
var arguments=Array(CommandLine.arguments.dropFirst())
var configURL=BrowserBridgeConfiguration.defaultURL
let executable=URL(fileURLWithPath:CommandLine.arguments[0]).standardizedFileURL
var appURL=executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
var browserArguments:[String]=[]
var index=0
while index<arguments.count {
    let arg=arguments[index]
    if arg == "--bridge-config" || arg == "--app" {
        guard index+1<arguments.count else { exit(2) };let path=URL(fileURLWithPath:arguments[index+1]);if arg == "--app" { appURL=path } else { configURL=path };index += 2
    } else { browserArguments.append(arg);index += 1 }
}
let chrome="chrome-extension://amdlggemepjploaameacboladklhlndk"
let trusted=browserArguments.first == chrome || browserArguments.first == chrome+"/" || (browserArguments.count >= 2 && browserArguments[1] == "idm-mac@haseeb-heaven" && browserArguments[0].hasSuffix(".json"))
func emit(_ response:BrowserResponse) throws { try FileHandle.standardOutput.write(contentsOf:NativeMessageFrame.encode(JSONEncoder().encode(response))) }
guard trusted else { try? emit(BrowserResponse(id:"",status:"error",message:"Unrecognized browser extension."));exit(2) }
while true {
    var requestID=""
    do {
        guard let data=try NativeMessageFrame.read(from:FileHandle.standardInput) else { break }
        let request=try JSONDecoder().decode(BrowserRequest.self,from:data);requestID=request.id;try request.validate()
        var config=try? configuration(configURL)
        if config == nil || !listening(config!) {
            config=nil
            let process=Process();process.executableURL=URL(fileURLWithPath:"/usr/bin/open");process.arguments=["-a",appURL.path];process.standardOutput=FileHandle.nullDevice;process.standardError=FileHandle.nullDevice;try process.run()
            for _ in 0..<40 { if let ready=try? configuration(configURL), listening(ready) { config=ready;break };Thread.sleep(forTimeInterval:0.1) }
        }
        guard let config else { throw BrowserProtocolError.invalid }
        try emit(forward(request,config:config))
    } catch {
        try? emit(BrowserResponse(id:requestID,status:"error",message:"Browser handoff failed. Open IDM Mac and try again."))
        if requestID.isEmpty { break }
    }
}
