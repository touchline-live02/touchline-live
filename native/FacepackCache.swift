import Foundation

private struct FacepackStamp:Equatable {
    let path:String
    let size:UInt64
    let modified:UInt64
    static func read(_ path:String,directory:Bool=false)->FacepackStamp? {
        guard let values=try? FileManager.default.attributesOfItem(atPath:path),
              let date=values[.modificationDate] as? Date,
              let size=values[.size] as? NSNumber else {return nil}
        return FacepackStamp(path:path,size:directory ? 0 : size.uint64Value,modified:date.timeIntervalSince1970.bitPattern)
    }
    var fileMatches:Bool {Self.read(path)==self}
    var directoryMatches:Bool {Self.read(path,directory:true)==self}
}

/// Small bounded binary reader. Bad/truncated/obsolete caches are disposable, never fatal.
private struct FacepackReader {
    let bytes:UnsafeRawBufferPointer
    var offset=0
    mutating func u32()->UInt32? {
        guard offset<=bytes.count-4 else {return nil}
        defer {offset+=4}
        return UInt32(bytes[offset]) | UInt32(bytes[offset+1])<<8 | UInt32(bytes[offset+2])<<16 | UInt32(bytes[offset+3])<<24
    }
    mutating func u64()->UInt64? {
        guard let low=u32(),let high=u32() else {return nil}
        return UInt64(low) | UInt64(high)<<32
    }
    mutating func string()->String? {
        guard let count=u32(),Int(count)<=bytes.count-offset else {return nil}
        defer {offset+=Int(count)}
        return String(bytes:bytes[offset..<offset+Int(count)],encoding:.utf8)
    }
    mutating func stamps()->[FacepackStamp]? {
        guard let count=u32(),Int(count)<=(bytes.count-offset)/20 else {return nil}
        var result:[FacepackStamp]=[];result.reserveCapacity(Int(count))
        for _ in 0..<count {
            guard let path=string(),let size=u64(),let modified=u64() else {return nil}
            result.append(FacepackStamp(path:path,size:size,modified:modified))
        }
        return result
    }
}
private struct FacepackWriter {
    var data=Data()
    mutating func u32(_ value:UInt32) {var v=value.littleEndian;withUnsafeBytes(of:&v) {data.append(contentsOf:$0)}}
    mutating func u64(_ value:UInt64) {u32(UInt32(truncatingIfNeeded:value));u32(UInt32(truncatingIfNeeded:value>>32))}
    mutating func string(_ value:String) {let utf8=value.utf8;u32(UInt32(utf8.count));data.append(contentsOf:utf8)}
    mutating func stamps(_ values:[FacepackStamp]) {
        u32(UInt32(values.count));for value in values {string(value.path);u64(value.size);u64(value.modified)}
    }
}

struct FacepackLoadResult {
    let index:FacepackIndex
    let cacheHit:Bool
    let discoverySeconds:Double
    let parseSeconds:Double
    let totalSeconds:Double
}

/// A single root-bound, versioned binary index. No pictures or player-cache data are stored.
enum FacepackCache {
    private static let magic:UInt64=0x3245584449434654 // "TFCIDXE2"; increment on format/layout changes.
    static var defaultURL:URL {
        let base=FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("local.touchline.live/PlayerFaces/index.bin")
    }
    static func load(root:URL,cacheURL:URL=defaultURL)->FacepackLoadResult? {
        let began=Date(),root=root.standardizedFileURL.resolvingSymlinksInPath()
        var discovered:FacepackIndex.Discovery?
        var discoverySeconds=0.0
        // Only stat known configs/directories on the fast path. Directory timestamps
        // detect added/removed configs or subfolders without fingerprinting image files.
        if let data=try? Data(contentsOf:cacheURL,options:.mappedIfSafe) {
            let cached:FacepackIndex?=data.withUnsafeBytes { bytes in
                var reader=FacepackReader(bytes:bytes)
                guard reader.u64()==magic,reader.string()==root.path,
                      let configs=reader.stamps(),let directories=reader.stamps(),!directories.isEmpty,
                      configs.allSatisfy({$0.fileMatches}) else {return nil}
                var changedDirectories=false
                if !directories.allSatisfy({$0.directoryMatches}) {
                    let discoveryStart=Date()
                    guard let next=FacepackIndex.discover(root:root) else {return nil}
                    discovered=next;discoverySeconds=Date().timeIntervalSince(discoveryStart)
                    guard let current=stamps(next.configs,directory:false),current==configs else {return nil}
                    changedDirectories=true // e.g. an image added, but mappings unchanged: do not reparse XML.
                }
                guard let malformed=reader.u32(),Int(malformed)<=configs.count,
                      let directoryCount=reader.u32(),Int(directoryCount)<=(bytes.count-reader.offset)/4 else {return nil}
                var sourceDirectories:[URL]=[]
                for _ in 0..<directoryCount {
                    guard let path=reader.string() else {return nil}
                    sourceDirectories.append(URL(fileURLWithPath:path,isDirectory:true))
                }
                guard let count=reader.u32(),Int(count)<=(bytes.count-reader.offset)/12 else {return nil}
                var faces:[Int:PlayerFaceReference]=[:];faces.reserveCapacity(Int(count))
                for _ in 0..<count {
                    guard let uid=reader.u32(),uid>0,uid<UInt32.max,let directory=reader.u32(),Int(directory)<sourceDirectories.count,
                          let source=reader.string(),!source.isEmpty,!source.hasPrefix("/"),!source.contains(":"),!source.contains("\0"),
                          faces[Int(uid)]==nil else {return nil}
                    faces[Int(uid)]=PlayerFaceReference(directory:sourceDirectories[Int(directory)],source:source)
                }
                guard reader.offset==bytes.count else {return nil}
                let index=FacepackIndex(faces:faces,configurationCount:configs.count,malformedConfigurationCount:Int(malformed))
                if changedDirectories,let next=discovered,let fresh=stamps(next.directories,directory:true) {
                    save(index,root:root,configs:configs,directories:fresh,to:cacheURL)
                }
                return index
            }
            if let cached=cached {
                return FacepackLoadResult(index:cached,cacheHit:true,discoverySeconds:discoverySeconds,parseSeconds:0,totalSeconds:Date().timeIntervalSince(began))
            }
        }
        if discovered==nil {
            let start=Date();discovered=FacepackIndex.discover(root:root);discoverySeconds=Date().timeIntervalSince(start)
        }
        guard let discovery=discovered else {return nil}
        let configs=stamps(discovery.configs,directory:false),directories=stamps(discovery.directories,directory:true)
        let parseStart=Date(),index=FacepackIndex.build(configs:discovery.configs)
        let parseSeconds=Date().timeIntervalSince(parseStart)
        // If the pack changes during parsing, publish the usable index but don't persist stale fingerprints.
        if let configs=configs,let directories=directories,
           configs.allSatisfy({$0.fileMatches}),directories.allSatisfy({$0.directoryMatches}) {
            save(index,root:root,configs:configs,directories:directories,to:cacheURL)
        }
        return FacepackLoadResult(index:index,cacheHit:false,discoverySeconds:discoverySeconds,parseSeconds:parseSeconds,totalSeconds:Date().timeIntervalSince(began))
    }
    private static func stamps(_ urls:[URL],directory:Bool)->[FacepackStamp]? {
        let values=urls.compactMap {FacepackStamp.read($0.path,directory:directory)}
        return values.count==urls.count ? values : nil
    }
    private static func save(_ index:FacepackIndex,root:URL,configs:[FacepackStamp],directories:[FacepackStamp],to url:URL) {
        var writer=FacepackWriter();writer.data.reserveCapacity(index.count*32)
        writer.u64(magic);writer.string(root.path);writer.stamps(configs);writer.stamps(directories)
        writer.u32(UInt32(index.malformedConfigurationCount))
        // Store common config directories once; mapping entries contain UID + directory index + relative source.
        let paths=Array(Set(index.faces.values.map {$0.directory.path})).sorted()
        let directoryIDs=Dictionary(uniqueKeysWithValues:paths.enumerated().map {($0.element,UInt32($0.offset))})
        writer.u32(UInt32(paths.count));paths.forEach {writer.string($0)}
        writer.u32(UInt32(index.count))
        for (uid,reference) in index.faces {
            writer.u32(UInt32(uid));writer.u32(directoryIDs[reference.directory.path]!);writer.string(reference.source)
        }
        do {
            try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
            try writer.data.write(to:url,options:.atomic)
        } catch { /* A full/unwritable cache disk must never disable otherwise usable faces. */ }
    }
}
