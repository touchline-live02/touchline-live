import Foundation

@main struct ShortlistTests {
    static func main() throws {
        var checks=0
        func check(_ value:Bool,_ message:String) throws {
            checks+=1
            if !value {throw NSError(domain:"ShortlistTests",code:1,userInfo:[NSLocalizedDescriptionKey:message])}
        }
        func row(_ entity:Int?,_ uid:Int,_ name:String,_ ca:Int=150)->Row {
            var data:[String:Any]=[
                "uid":uid,"name":name,"birthDate":"2000-01-01","age":26,"ca":ca,"pa":180,
                "positions":["ST":20],"visibleAttributes":["pace":16],"hiddenAttributes":[:],
                "personalityComponents":[:],"footStrengths":[:],"reputation":["rawSlots":[]],
                "traits":["mapped":[],"unresolvedBits":[]],"fieldStatus":["age":"derived"]
            ]
            if let entity=entity {data["entity"]=entity}
            return Row(try! JSONDecoder().decode(Player.self,from:JSONSerialization.data(withJSONObject:data)))
        }
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let url=root.appendingPathComponent("nested/shortlist.json")
        let store=ShortlistStore(url:url)
        try check(store.entries.isEmpty && store.loadError==nil,"Missing file is an empty shortlist")
        let rows=[row(100,200,"Alpha",120),row(101,201,"Beta",170),row(102,202,"Gamma",160)]
        try check(rows[0].player.entity==100 && rows[0].player.uid==200,"Exact entity/uid cache names and integer types")
        try check(row(nil,9,"Older cache").player.entity==nil,"Older cache without entity still decodes")
        let first=ShortlistEntry(rows[0].player),second=ShortlistEntry(rows[1].player)
        try store.add(first);try store.add(second);try store.add(first)
        try check(store.entries==[first,second],"Add immediately; no duplicate identifiers")
        let reloaded=ShortlistStore(url:url)
        try check(reloaded.entries==store.entries,"Persist and reopen")
        let object=try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as! [String:Any]
        try check(Set(object.keys)==Set(["version","entries"]),"Versioned persistence envelope only")
        let entry=(object["entries"] as! [[String:Any]])[0]
        try check(Set(entry.keys)==Set(["entity","uid"]) && entry["entity"] as? Int==100 && entry["uid"] as? Int==200,"Persist both exact IDs, no records or addresses")
        let index=ShortlistIndex(rows)
        let resolved=index.resolve(store.entries)
        try check(resolved.rowIndices==IndexSet([0,1]) && resolved.unresolvedCount==0,"Resolve against current cache")
        let updatedRows=[row(101,201,"Updated Beta",195),row(100,200,"Updated Alpha",140)]
        let updated=ShortlistIndex(updatedRows).resolve(store.entries)
        try check(updated.rowIndices==IndexSet([0,1]) && updatedRows[0].name=="Updated Beta","Reordered/refreshed cache uses current records")
        let missing=ShortlistIndex([]).resolve(store.entries)
        try check(missing.unresolvedCount==2 && store.entries.count==2,"Missing cache retains unresolved entries")
        let conflicts=ShortlistIndex([row(999,200,"Reused UID"),row(100,999,"Reused entity")]).resolve([first])
        try check(conflicts.rowIndices.isEmpty && conflicts.unresolvedCount==1,"Conflicting pair does not fall back to one ID")
        let duplicate=ShortlistIndex([rows[0],rows[0]]).resolve([first])
        try check(duplicate.rowIndices.isEmpty && duplicate.unresolvedCount==1,"Ambiguous pair never picks an arbitrary record")
        let partial=[ShortlistEntry(entity:nil,uid:200),ShortlistEntry(entity:101,uid:nil)]
        try check(index.resolve(partial).rowIndices==IndexSet([0,1]),"One available ID resolves uniquely")
        try check(ShortlistIndex([rows[0],row(999,200,"Duplicate UID")]).resolve([partial[0]]).unresolvedCount==1,"Ambiguous UID remains unresolved")
        let aliases=index.resolve([first,partial[0]])
        try check(aliases.rowIndices==IndexSet(integer:0) && aliases.entryIndicesByRow[0]==IndexSet([0,1]),"Aliases display once and are removable together")
        try check(selectRows(rows,query:Query(),sort:SortSpec(key:"ca",ascending:false),candidates:resolved.rowIndices)==[1,0],"Shortlist uses existing numeric sorting")
        var q=Query();q.caMin=150;q.position="ST";q.name="beta"
        try check(selectRows(rows,query:q,sort:SortSpec(),candidates:resolved.rowIndices)==[1],"Filters compose with AND inside shortlist")
        q.name="gamma"
        try check(selectRows(rows,query:q,sort:SortSpec(),candidates:resolved.rowIndices).isEmpty,"Matching unshortlisted player remains excluded")
        try check(selectRows(rows,query:Query(),sort:SortSpec(),candidates:IndexSet()).isEmpty,"Empty shortlist is not all players")
        try check(selectRows(rows,query:Query(),sort:SortSpec()).count==3,"Players scope remains unchanged")
        try check(selectRows(rows,query:Query(),sort:SortSpec(),candidates:IndexSet([0,99]))==[0],"Stale candidate index cannot crash")
        try store.remove(entryIndices:resolved.entryIndicesByRow[0]!)
        try check(store.entries==[second] && index.resolve(store.entries).rowIndices==IndexSet(integer:1),"Removing excludes the row immediately")
        try check(ShortlistStore(url:url).entries==[second],"Removal persists")
        try store.remove(entryIndices:IndexSet(integer:0))
        try check(ShortlistStore(url:url).entries.isEmpty,"Empty shortlist persists")
        let invalid=root.appendingPathComponent("broken.json")
        let bytes=Data("broken shortlist".utf8);try bytes.write(to:invalid)
        let broken=ShortlistStore(url:invalid)
        try check(broken.loadError != nil,"Corrupt file surfaced")
        var rejected=false
        do {try broken.add(first)} catch {rejected=true}
        try check(rejected,"Corrupt file must not be overwritten")
        try check(try Data(contentsOf:invalid)==bytes,"Corrupt file preserved exactly")
        let future=try JSONEncoder().encode(ShortlistDocument(version:2,entries:[first]))
        try future.write(to:invalid)
        try check(ShortlistStore(url:invalid).loadError != nil,"Unknown schema not silently interpreted")
        let duplicates=try JSONEncoder().encode(ShortlistDocument(version:1,entries:[first,first]))
        try duplicates.write(to:invalid)
        try check(ShortlistStore(url:invalid).entries==[first],"Duplicate file entries deduplicated")
        let unwritable=ShortlistStore(url:root.appendingPathComponent("later/shortlist.json"))
        try Data().write(to:root.appendingPathComponent("later"))
        rejected=false
        do {try unwritable.add(first)} catch {rejected=true}
        try check(rejected,"Write failure must throw")
        try check(unwritable.entries.isEmpty,"Failed write does not publish in-memory change")
        // Bulk actions use the displayed result selection and one store operation.
        let bulk=ShortlistStore(url:root.appendingPathComponent("bulk.json"))
        try bulk.add([first,second,first])
        try check(bulk.entries==[first,second],"Bulk add deduplicates within batch")
        try bulk.add([first,second])
        try check(bulk.entries.count==2,"Bulk add excludes existing entries")
        let third=ShortlistEntry(rows[2].player)
        let mixedSelection=IndexSet([0,2])
        let membership=index.resolve(bulk.entries)
        try check(membership.additions(from:mixedSelection)==IndexSet(integer:2),"Mixed selection offers only missing rows for add")
        try check(membership.removals(from:mixedSelection)==IndexSet(integer:0),"Mixed selection offers only stored entries for remove")
        try bulk.add(membership.additions(from:mixedSelection).map {ShortlistEntry(rows[$0].player)})
        try check(ShortlistStore(url:bulk.url).entries==[first,second,third],"Bulk additions persist as one complete batch")
        try bulk.remove(entryIndices:index.resolve(bulk.entries).removals(from:mixedSelection))
        try check(bulk.entries==[second] && ShortlistStore(url:bulk.url).entries==[second],"Bulk removal preserves unselected entries and persists")
        try check(aliases.removals(from:IndexSet(integer:0))==IndexSet([0,1]),"Bulk removal includes all aliases for selected players")
        let unresolvedEntry=ShortlistEntry(entity:777,uid:888)
        try bulk.add(unresolvedEntry)
        try bulk.remove(entryIndices:index.resolve(bulk.entries).removals(from:IndexSet(rows.indices)))
        try check(bulk.entries==[unresolvedEntry],"Select All removal never drops unresolved stored entries")
        let before=try Data(contentsOf:bulk.url)
        rejected=false
        do {try bulk.add([first,ShortlistEntry(entity:nil,uid:nil)])} catch {rejected=true}
        try check(rejected && bulk.entries==[unresolvedEntry],"Invalid bulk member rejects complete batch")
        try check(try Data(contentsOf:bulk.url)==before,"Rejected batch leaves file unchanged")
        let filtered=[2,0]
        let selectAll=selectedSourceRows(IndexSet(filtered.indices),visible:filtered)
        try check(selectAll==IndexSet([0,2]),"Select All includes only displayed query rows")
        try check(selectedSourceRows(IndexSet([1,99]),visible:filtered)==IndexSet(integer:0),"Selection translates displayed indexes safely")
        try check(selectedSourceRows(IndexSet(),visible:filtered).isEmpty,"Empty selection targets nothing")
        try check(restoredPlayerSelection(Set([200,202]),results:[1,2,0],rows:rows)==IndexSet([1,2]),"Sort retains all selected players")
        try check(restoredPlayerSelection(Set([200,202]),results:[1,2],rows:rows)==IndexSet(integer:1),"Filtering retains surviving selected players")
        try check(restoredPlayerSelection(Set([200,202]),results:[1],rows:rows)==IndexSet(integer:0),"Removing selection picks a sane remaining player")
        try check(restoredPlayerSelection(Set([200,202]),results:[],rows:rows).isEmpty,"Removing last players leaves empty selection")
        let many=(0..<2000).map {ShortlistEntry(entity:$0,uid:10000+$0)}
        let large=ShortlistStore(url:root.appendingPathComponent("large.json"))
        try large.add(many+many)
        try check(large.entries.count==2000 && ShortlistStore(url:large.url).entries==many,"Large batch remains unique and survives reload")
        try large.remove(entryIndices:IndexSet(large.entries.indices))
        try check(ShortlistStore(url:large.url).entries.isEmpty,"Bulk remove all persists empty shortlist")
        print("Shortlist: \(checks) checks passed; Foundation only, no GUI or live reads.")
    }
}
