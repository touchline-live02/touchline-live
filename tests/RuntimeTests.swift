import Foundation

@main struct RuntimeTests {
    static func main() throws {
        let manager=FileManager.default
        let root=manager.temporaryDirectory.appendingPathComponent("touchline-runtime-"+UUID().uuidString)
        defer {try? manager.removeItem(at:root)}
        var checks=0
        func check(_ condition:Bool,_ message:String) throws {
            checks+=1;if !condition {throw NSError(domain:"RuntimeTests",code:1,userInfo:[NSLocalizedDescriptionKey:message])}
        }
        func interpreter(_ name:String,_ status:Int)->URL {
            let url=root.appendingPathComponent(name+"/python3")
            try! manager.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
            try! Data("#!/bin/sh\nexit \(status)\n".utf8).write(to:url)
            try! manager.setAttributes([.posixPermissions:0o700],ofItemAtPath:url.path)
            return url
        }
        let old=interpreter("old",1),valid=interpreter("supported",0)
        let path=old.deletingLastPathComponent().path+":"+valid.deletingLastPathComponent().path
        try check(!PythonRuntime.isSupported(old) && PythonRuntime.isSupported(valid),"Version-probe success/failure controls compatibility")
        try check(PythonRuntime.resolve(environment:["PATH":path])==valid,"Unsupported first candidate does not hide a compatible installation")
        var attempted:[String]=[]
        let result=PythonRuntime.resolve(environment:["PATH":path+":"+path],supported:{attempted.append($0.path);return false})
        try check(result==nil && Set(attempted).count==attempted.count,"No supported runtime returns nil; duplicate directories tried once")
        try manager.setAttributes([.posixPermissions:0o600],ofItemAtPath:valid.path)
        let selected=PythonRuntime.resolve(environment:["PATH":path],supported:{$0==valid})
        try check(selected==nil,"Non-executable files are not used as interpreters")
        try check(!PythonRuntime.isSupported(root.appendingPathComponent("missing")),"Missing executable fails safely")
        print("Runtime tests passed: \(checks) checks; no UI or FM access")
    }
}
