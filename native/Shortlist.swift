import Foundation

/// Names and values mirror the cache; neither is asserted to be FM Person.Id.
struct ShortlistEntry:Codable,Hashable {
    let entity:Int?
    let uid:Int?
    init(entity:Int?,uid:Int?) {self.entity=entity;self.uid=uid}
    init(_ player:Player) {entity=player.entity;uid=player.uid}
}
struct ShortlistDocument:Codable {
    let version:Int
    let entries:[ShortlistEntry]
}
struct ShortlistResolution {
    let rowIndices:IndexSet
    let entryIndicesByRow:[Int:IndexSet]
    let unresolvedCount:Int
    func additions(from selection:IndexSet)->IndexSet {selection.subtracting(rowIndices)}
    func removals(from selection:IndexSet)->IndexSet {
        var entries=IndexSet()
        for row in selection {entries.formUnion(entryIndicesByRow[row] ?? IndexSet())}
        return entries
    }
}

/// Built once for each loaded cache. Duplicate identifiers never pick an arbitrary player.
struct ShortlistIndex {
    private let entities:[Int:[Int]]
    private let uids:[Int:[Int]]
    init(_ rows:[Row]) {
        var entities:[Int:[Int]]=[:],uids:[Int:[Int]]=[:]
        for (index,row) in rows.enumerated() {
            if let entity=row.player.entity {entities[entity,default:[]].append(index)}
            uids[row.player.uid,default:[]].append(index)
        }
        self.entities=entities;self.uids=uids
    }
    func resolve(_ entries:[ShortlistEntry])->ShortlistResolution {
        var found=IndexSet(),byRow:[Int:IndexSet]=[:],unresolved=0
        for (entryIndex,entry) in entries.enumerated() {
            let candidates:[Int]
            switch (entry.entity,entry.uid) {
            case let (entity?,uid?):
                let entityRows=Set(entities[entity] ?? [])
                candidates=(uids[uid] ?? []).filter {entityRows.contains($0)}
            case let (entity?,nil):candidates=entities[entity] ?? []
            case let (nil,uid?):candidates=uids[uid] ?? []
            case (nil,nil):candidates=[]
            }
            if candidates.count==1,let row=candidates.first {
                found.insert(row);byRow[row,default:IndexSet()].insert(entryIndex)
            } else {unresolved+=1}
        }
        return ShortlistResolution(rowIndices:found,entryIndicesByRow:byRow,unresolvedCount:unresolved)
    }
}

final class ShortlistStore {
    static var defaultURL:URL {
        FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("Touchline Live/shortlist.json")
    }
    let url:URL
    private(set) var entries:[ShortlistEntry]=[]
    private(set) var loadError:String?
    init(url:URL) {
        self.url=url
        do {
            let data:Data
            do {data=try Data(contentsOf:url)}
            catch let error as NSError where error.domain==NSCocoaErrorDomain && error.code==NSFileReadNoSuchFileError {return}
            let document=try JSONDecoder().decode(ShortlistDocument.self,from:data)
            guard document.version==1,document.entries.allSatisfy({$0.entity != nil || $0.uid != nil}) else {
                throw Self.error("Unsupported or invalid shortlist file; the original file was preserved.")
            }
            var seen=Set<ShortlistEntry>()
            entries=document.entries.filter {seen.insert($0).inserted}
        } catch {loadError=error.localizedDescription}
    }
    func add(_ entry:ShortlistEntry) throws {
        try add([entry])
    }
    /// Deduplicate and commit the complete batch in one atomic write.
    func add(_ additions:[ShortlistEntry]) throws {
        guard additions.allSatisfy({$0.entity != nil || $0.uid != nil}) else {throw Self.error("Player identifiers are missing.")}
        var seen=Set(entries)
        let unique=additions.filter {seen.insert($0).inserted}
        guard !unique.isEmpty else {return}
        try save(entries+unique)
    }
    func remove(entryIndices:IndexSet) throws {
        try save(entries.enumerated().filter {!entryIndices.contains($0.offset)}.map(\.element))
    }
    private func save(_ next:[ShortlistEntry]) throws {
        if let problem=loadError {throw Self.error("Cannot update the shortlist: "+problem)}
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        let data=try encoder.encode(ShortlistDocument(version:1,entries:next))
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try data.write(to:url,options:.atomic)
        entries=next // Publish only after successful persistence.
    }
    private static func error(_ message:String)->NSError {
        NSError(domain:"Touchline.Shortlist",code:1,userInfo:[NSLocalizedDescriptionKey:message])
    }
}
