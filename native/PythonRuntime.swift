import Foundation

/// Discover a supported local interpreter; never bake the build machine's path into the app.
enum PythonRuntime {
    static func resolve(environment:[String:String]=ProcessInfo.processInfo.environment,
                        supported:(URL)->Bool=isSupported)->URL? {
        let directories=(environment["PATH"] ?? "").split(separator:":").map(String.init)
            + ["/opt/homebrew/bin","/usr/local/bin","/Library/Frameworks/Python.framework/Versions/Current/bin","/usr/bin"]
        var visited=Set<String>()
        for directory in directories where directory.hasPrefix("/") && visited.insert(directory).inserted {
            let url=URL(fileURLWithPath:directory,isDirectory:true).appendingPathComponent("python3")
            if FileManager.default.isExecutableFile(atPath:url.path),supported(url) {return url}
        }
        return nil
    }
    static func isSupported(_ url:URL)->Bool {
        let process=Process();process.executableURL=url
        process.arguments=["-c","import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)"]
        process.standardOutput=FileHandle.nullDevice;process.standardError=FileHandle.nullDevice
        do {try process.run()} catch {return false}
        let deadline=Date().addingTimeInterval(3)
        while process.isRunning && Date()<deadline {Thread.sleep(forTimeInterval:0.02)}
        if process.isRunning {process.terminate();return false}
        process.waitUntilExit();return process.terminationStatus==0
    }
}
