import Foundation
import Darwin
#if canImport(FoundationXML)
import FoundationXML
#endif

/// FM config mappings only. No images are opened while building this index.
struct PlayerFaceReference {
    let directory:URL
    let source:String
    func existingImageURL(fileManager:FileManager = .default)->URL? {
        // FM configs commonly omit the extension; do not assume numbered PNG names.
        let file=directory.appendingPathComponent(source).standardizedFileURL
        let candidates=file.pathExtension.isEmpty
            ? [file]+["png","jpg","jpeg","webp","tif","tiff","heic","bmp","gif"].map {file.appendingPathExtension($0)}
            : [file]
        for candidate in candidates {
            var directory:ObjCBool=false
            if fileManager.fileExists(atPath:candidate.path,isDirectory:&directory),!directory.boolValue,
               fileManager.isReadableFile(atPath:candidate.path) {return candidate}
        }
        return nil
    }
}

private final class FacepackConfigParser:NSObject,XMLParserDelegate {
    let directory:URL
    var faces:[Int:PlayerFaceReference]=[:]
    private var depth=0
    private var mappingDepth:Int?
    init(directory:URL) {self.directory=directory}
    func parser(_ parser:XMLParser,didStartElement elementName:String,namespaceURI:String?,qualifiedName:String?,attributes:[String:String]) {
        depth+=1
        if elementName=="list",attributes["id"]=="maps",mappingDepth==nil {mappingDepth=depth}
        guard elementName=="record",let mappingDepth=mappingDepth,depth>mappingDepth,
              let target=attributes["to"],let source=attributes["from"] else {return}
        let parts=target.replacingOccurrences(of:"\\",with:"/").split(separator:"/",omittingEmptySubsequences:false)
        guard parts.count==5,parts[0]=="graphics",parts[1]=="pictures",parts[2]=="person",parts[4]=="portrait",
              parts[3].allSatisfy({$0.isASCII && $0.isNumber}),let id=Int(parts[3]),id>0,id<Int(UInt32.max) else {return}
        let relative=source.replacingOccurrences(of:"\\",with:"/").trimmingCharacters(in:.whitespacesAndNewlines)
        guard !relative.isEmpty,!relative.hasPrefix("/"),!relative.contains(":"),!relative.contains("\0") else {return}
        faces[id]=PlayerFaceReference(directory:directory,source:relative)
    }
    func parser(_ parser:XMLParser,didEndElement elementName:String,namespaceURI:String?,qualifiedName:String?) {
        if depth==mappingDepth {mappingDepth=nil}
        depth-=1
    }
}

struct FacepackIndex {
    // Shared only with the disposable index serializer; player/model data stays independent.
    let faces:[Int:PlayerFaceReference]
    let configurationCount:Int
    let malformedConfigurationCount:Int
    var count:Int {faces.count}
    func resolvePlayerFace(id:Int)->URL? {faces[id]?.existingImageURL()}

    /// Malformed configs contribute no partial mappings; other valid packs still work.
    static func parseConfiguration(_ url:URL)->[Int:PlayerFaceReference]? {
        guard let stream=InputStream(url:url) else {return nil}
        let parser=XMLParser(stream:stream)
        parser.shouldResolveExternalEntities=false
        let delegate=FacepackConfigParser(directory:url.deletingLastPathComponent());parser.delegate=delegate
        return parser.parse() ? delegate.faces : nil
    }
    static func scan(root:URL,fileManager:FileManager = .default)->FacepackIndex? {
        guard let discovery=discover(root:root,fileManager:fileManager) else {return nil}
        return build(configs:discovery.configs)
    }
    struct Discovery {let configs:[URL];let directories:[URL]}
    static func discover(root:URL,fileManager:FileManager = .default)->Discovery? {
        var directory:ObjCBool=false
        guard root.isFileURL,fileManager.fileExists(atPath:root.path,isDirectory:&directory),directory.boolValue,
              fileManager.isReadableFile(atPath:root.path) else {return nil}
        var configs:[URL]=[],directories:[URL]=[],pending=[root]
        // readdir exposes entry type without fetching metadata for every portrait file.
        // Still recurse through all ordinary directories: packs need not have any fixed layout.
        while let folder=pending.popLast() {
            guard let stream=opendir(folder.path) else {if folder==root {return nil};continue}
            directories.append(folder)
            while let entry=readdir(stream) {
                let name=withUnsafePointer(to:entry.pointee.d_name) {
                    $0.withMemoryRebound(to:CChar.self,capacity:Int(MAXNAMLEN)+1) {String(cString:$0)}
                }
                guard !name.hasPrefix(".") else {continue}
                let type=entry.pointee.d_type
                if name.lowercased()=="config.xml" {configs.append(folder.appendingPathComponent(name))}
                if type==DT_DIR || type==DT_UNKNOWN {
                    let url=folder.appendingPathComponent(name,isDirectory:type==DT_DIR)
                    let keys:Set<URLResourceKey> = [.isDirectoryKey,.isSymbolicLinkKey,.isPackageKey]
                    guard let attributes=try? url.resourceValues(forKeys:keys),attributes.isDirectory==true,
                          attributes.isSymbolicLink != true,attributes.isPackage != true else {continue}
                    pending.append(url)
                }
            }
            closedir(stream)
        }
        return Discovery(configs:configs.sorted {$0.path<$1.path},directories:directories.sorted {$0.path<$1.path})
    }
    static func build(configs:[URL])->FacepackIndex {
        // Stable traversal/override policy: later lexicographic config wins; last record wins within a config.
        var faces:[Int:PlayerFaceReference]=[:],malformed=0
        for url in configs {
            guard let parsed=parseConfiguration(url) else {malformed+=1;continue}
            faces.merge(parsed,uniquingKeysWith:{$1})
        }
        return FacepackIndex(faces:faces,configurationCount:configs.count,malformedConfigurationCount:malformed)
    }
}
