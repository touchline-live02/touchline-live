import Foundation

@main struct FacepackTests {
    static func main() throws {
        var checks=0
        func check(_ value:Bool,_ message:String) throws {
            checks+=1
            if !value {throw NSError(domain:"FacepackTests",code:1,userInfo:[NSLocalizedDescriptionKey:message])}
        }
        let fm=FileManager.default
        let root=fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("touchline-faces-"+UUID().uuidString)
        defer {try? fm.removeItem(at:root)}
        func write(_ relative:String,_ contents:String="fixture") throws -> URL {
            let url=root.appendingPathComponent(relative)
            try fm.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
            try Data(contents.utf8).write(to:url);return url
        }
        let xml="""
        <?xml version="1.0" encoding="UTF-8"?>
        <record>
          <record from="outside" to="graphics/pictures/person/999/portrait"/>
          <list id="maps">
            <record from="face_29179241" to="graphics/pictures/person/29179241/portrait"/>
            <record from="nested\\mbappe.jpg" to="graphics\\pictures\\person\\85139014\\portrait"/>
            <record from="../shared/gray" to="graphics/pictures/person/2000182795/portrait"/>
            <record from="names/A&amp;B" to="graphics/pictures/person/19058734/portrait"/>
            <record from="missing" to="graphics/pictures/person/123/portrait"/>
            <record from="directory" to="graphics/pictures/person/124/portrait"/>
            <record from="logo" to="graphics/pictures/club/12/logo"/>
            <record from="icon" to="graphics/pictures/person/13/icon"/>
            <record from="bad" to="graphics/pictures/person/0/portrait"/>
            <record from="bad" to="graphics/pictures/person/-1/portrait"/>
            <record from="bad" to="graphics/pictures/person/4294967295/portrait"/>
            <record from="bad" to="graphics/pictures/person/NaN/portrait"/>
            <record from="bad" to="graphics/pictures/person/29179241/portrait/extra"/>
            <record from="/absolute/file" to="graphics/pictures/person/201/portrait"/>
            <record from="C:\\file" to="graphics/pictures/person/202/portrait"/>
            <record from="" to="graphics/pictures/person/203/portrait"/>
          </list>
        </record>
        """
        let config=try write("pack/config.xml",xml)
        let haaland=try write("pack/face_29179241.png")
        let mbappe=try write("pack/nested/mbappe.jpg")
        let gray=try write("shared/gray.jpeg")
        let alisson=try write("pack/names/A&B.png")
        try fm.createDirectory(at:root.appendingPathComponent("pack/directory"),withIntermediateDirectories:true)
        let parsed=FacepackIndex.parseConfiguration(config)
        try check(parsed?.count==6,"Only valid positive external person portrait IDs within maps are indexed")
        try check(parsed?[29179241]?.source=="face_29179241","Preserve source prefix rather than guessing UID filename")
        let index=FacepackIndex.scan(root:root)!
        try check(index.configurationCount==1 && index.malformedConfigurationCount==0,"Recursive config discovery")
        try check(index.resolvePlayerFace(id:29179241)?.resolvingSymlinksInPath().path==haaland.resolvingSymlinksInPath().path,"Extensionless prefixed PNG")
        try check(index.resolvePlayerFace(id:85139014)?.resolvingSymlinksInPath().path==mbappe.resolvingSymlinksInPath().path,"Explicit JPG and Windows separators")
        try check(index.resolvePlayerFace(id:2000182795)?.resolvingSymlinksInPath().path==gray.resolvingSymlinksInPath().path,"Config-relative sibling path and omitted JPEG extension")
        try check(index.resolvePlayerFace(id:19058734)?.resolvingSymlinksInPath().path==alisson.resolvingSymlinksInPath().path,"XML entities decode in source paths")
        try check(index.resolvePlayerFace(id:38044)==nil,"Internal entity index is never a UID fallback")
        try check(index.resolvePlayerFace(id:123)==nil,"Missing mapped file returns nil")
        try check(index.resolvePlayerFace(id:124)==nil,"Directories cannot be used as images")
        try check(index.resolvePlayerFace(id:999)==nil,"Records outside the mapping list are ignored")
        try check(index.resolvePlayerFace(id:12)==nil && index.resolvePlayerFace(id:13)==nil,"Clubs and person icons are out of scope")
        try check(index.resolvePlayerFace(id:-1)==nil,"Unmapped IDs return nil")
        try check(FacepackIndex.scan(root:root.appendingPathComponent("absent"))==nil,"Missing folder disables resolution")
        try check(FacepackIndex.scan(root:haaland)==nil,"File cannot serve as graphics root")
        let empty=root.appendingPathComponent("empty")
        try fm.createDirectory(at:empty,withIntermediateDirectories:true)
        try check(FacepackIndex.scan(root:empty)?.count==0,"Empty folder is a valid empty index")
        _=try write("pack/config.xml","<record><list id=\"maps\"><record from=\"other\" to=\"graphics/pictures/person/29179241/portrait\"/></list></record>")
        try check(index.resolvePlayerFace(id:29179241)?.resolvingSymlinksInPath().path==haaland.resolvingSymlinksInPath().path,"Selection lookup uses indexed mapping, never rescans configs")
        try check(FacepackIndex.scan(root:root)?.resolvePlayerFace(id:29179241)==nil,"Explicit rebuild replaces previous mapping")
        let bad=try write("broken/config.xml","<record><list id=\"maps\"><record from=\"partial\" to=\"graphics/pictures/person/99/portrait\"/>")
        try check(FacepackIndex.parseConfiguration(bad)==nil,"Malformed XML discards partial mappings")
        _=try write("z/config.xml","<record><list id=\"maps\"><record from=\"first\" to=\"graphics/pictures/person/29179241/portrait\"/><record from=\"winner\" to=\"graphics/pictures/person/29179241/portrait\"/></list></record>")
        let winner=try write("z/winner.png")
        let rebuilt=FacepackIndex.scan(root:root)!
        try check(rebuilt.configurationCount==3 && rebuilt.malformedConfigurationCount==1,"Malformed packs do not prevent valid pack indexing")
        try check(rebuilt.resolvePlayerFace(id:29179241)?.resolvingSymlinksInPath().path==winner.resolvingSymlinksInPath().path,"Last record and lexicographically later config override deterministically")
        try check(rebuilt.resolvePlayerFace(id:99)==nil,"Partial invalid mappings never leak into index")
        _=try write(".hidden/config.xml","<record><list id=\"maps\"><record from=\"face\" to=\"graphics/pictures/person/777/portrait\"/></list></record>")
        try check(FacepackIndex.scan(root:root)?.configurationCount==3,"Hidden directories are skipped")
        let cacheDirectory=fm.temporaryDirectory.appendingPathComponent("touchline-face-cache-"+UUID().uuidString)
        defer {try? fm.removeItem(at:cacheDirectory)}
        let cacheURL=cacheDirectory.appendingPathComponent("index.bin")
        let cold=FacepackCache.load(root:root,cacheURL:cacheURL)!
        try check(!cold.cacheHit && cold.index.count==rebuilt.count,"First index builds and saves outside graphics root")
        try check(fm.fileExists(atPath:cacheURL.path),"Binary index is persisted")
        let warm=FacepackCache.load(root:root,cacheURL:cacheURL)!
        try check(warm.cacheHit && warm.parseSeconds==0 && warm.discoverySeconds==0,"Unchanged relaunch skips XML and directory discovery")
        try check(warm.index.resolvePlayerFace(id:29179241)?.resolvingSymlinksInPath().path==winner.resolvingSymlinksInPath().path,"Persistent index preserves external UID mapping")
        try check(warm.index.malformedConfigurationCount==1,"Persistence retains malformed-config handling")
        try fm.removeItem(at:winner)
        let missing=FacepackCache.load(root:root,cacheURL:cacheURL)!
        try check(missing.cacheHit && missing.index.resolvePlayerFace(id:29179241)==nil,"Missing cached image returns nil without XML rebuild")
        _=try write("z/winner.png")
        _=try write("z/config.xml","<record><list id=\"maps\"><record from=\"winner\" to=\"graphics/pictures/person/29179242/portrait\"/></list></record>")
        let changed=FacepackCache.load(root:root,cacheURL:cacheURL)!
        try check(!changed.cacheHit && changed.index.resolvePlayerFace(id:29179242) != nil,"Changed config invalidates cache")
        try check(changed.index.resolvePlayerFace(id:29179241)==nil,"Stale mapping is removed")
        try check(FacepackCache.load(root:root,cacheURL:cacheURL)?.cacheHit==true,"Rebuilt index becomes the next warm cache")
        try fm.removeItem(at:root.appendingPathComponent("z/config.xml"))
        let deleted=FacepackCache.load(root:root,cacheURL:cacheURL)!
        try check(!deleted.cacheHit && deleted.index.resolvePlayerFace(id:29179242)==nil,"Deleted config invalidates cache")
        _=try write("new/nested/config.xml","<record><list id=\"maps\"><record from=\"new\" to=\"graphics/pictures/person/888/portrait\"/></list></record>")
        _=try write("new/nested/new.png")
        let added=FacepackCache.load(root:root,cacheURL:cacheURL)!
        try check(!added.cacheHit && added.index.resolvePlayerFace(id:888) != nil,"Added nested config is detected from directory manifest")
        _=try write("new/nested/unused.png")
        try check(FacepackCache.load(root:root,cacheURL:cacheURL)?.cacheHit==true,"Image-only directory changes reuse mappings")
        let alternate=root.appendingPathComponent("new/nested")
        let other=FacepackCache.load(root:alternate,cacheURL:cacheURL)!
        try check(!other.cacheHit && other.index.count==1,"Graphics-root change cannot reuse another root's cache")
        try check(FacepackCache.load(root:alternate,cacheURL:cacheURL)?.cacheHit==true,"Root-specific cache restores correctly")
        let intact=try Data(contentsOf:cacheURL)
        try intact.prefix(24).write(to:cacheURL)
        try check(FacepackCache.load(root:alternate,cacheURL:cacheURL)?.cacheHit==false,"Truncated cache rebuilds safely")
        var obsolete=intact;obsolete[0] ^= 0xff;try obsolete.write(to:cacheURL)
        try check(FacepackCache.load(root:alternate,cacheURL:cacheURL)?.cacheHit==false,"Unknown cache version rebuilds safely")
        try check(FacepackCache.load(root:root.appendingPathComponent("gone"),cacheURL:cacheURL)==nil,"Missing graphics root never restores stale mappings")
        let blocker=try write("not-a-cache-directory")
        try check(FacepackCache.load(root:alternate,cacheURL:blocker.appendingPathComponent("index.bin"))?.index.count==1,"Unwritable cache target does not disable face resolution")
        // Optional read-only validation against the supplied real facepack; no image decoding/UI.
        if CommandLine.arguments.count>1 {
            let liveRoot=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
            let realCache=cacheDirectory.appendingPathComponent("real.bin")
            let first=FacepackCache.load(root:liveRoot,cacheURL:realCache)
            let real=first?.index
            try check(real != nil,"Real fixture folder indexes")
            for uid in [29179241,85139014,2000182795,19058734] {
                try check(real?.resolvePlayerFace(id:uid) != nil,"Known cached player's UID resolves: \(uid)")
            }
            let restored=FacepackCache.load(root:liveRoot,cacheURL:realCache)!
            try check(restored.cacheHit && restored.index.count==real!.count,"Real-pack cached relaunch preserves all mappings")
            for uid in [29179241,85139014,2000182795,19058734] {
                try check(restored.index.resolvePlayerFace(id:uid) != nil,"Known UID resolves after real-pack restore: \(uid)")
            }
            let size=(try fm.attributesOfItem(atPath:realCache.path)[.size] as! NSNumber).intValue
            print("Real facepack: \(real!.count) mappings; discovery \(first!.discoverySeconds) s; XML/merge \(first!.parseSeconds) s; first build/save \(first!.totalSeconds) s; cached load \(restored.totalSeconds) s; binary bytes \(size)")
        }
        print("Facepack tests passed: \(checks) checks")
    }
}
