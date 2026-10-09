import Foundation

func runTests() throws {
    let args=CommandLine.arguments
    guard let i=args.firstIndex(of:"--self-test"),args.count>i+1 else {throw NSError(domain:"test",code:1,userInfo:[NSLocalizedDescriptionKey:"Pass a cache path"])}
    let (cache,rows,loadSeconds)=try loadCache(URL(fileURLWithPath:args[i+1]))
    func check(_ result:Bool,_ message:String) throws {if !result {throw NSError(domain:"test",code:1,userInfo:[NSLocalizedDescriptionKey:message])}}
    var checks=0
    func test(_ result:Bool,_ name:String) throws {try check(result,name);checks+=1}
    var timings:[String:Double]=[:]
    func timed(_ name:String,_ q:Query,_ sort:SortSpec=SortSpec())->[Int]{let began=Date();let found=selectRows(rows,query:q,sort:sort);timings[name]=Date().timeIntervalSince(began)*1000;return found}
    let all=timed("sortNameMS",Query());try test(all.count==cache.collection.count,"Current vector count preserved")
    try test(zip(all,all.dropFirst()).allSatisfy {rows[$0].nameKey<=rows[$1].nameKey},"Name sorting")
    var q=Query();q.name=rows.first(where:{!$0.nameKey.isEmpty})?.nameKey ?? "";let found=timed("searchMS",q)
    try test(!q.name.isEmpty && !found.isEmpty && found.allSatisfy {rows[$0].nameKey.contains(q.name)},"Name search")
    q=Query();q.caMin=130;q.paMin=150;q.wageMax=200000;q.rules=[NumericRule(source:.attribute,key:"pace",minimum:12,maximum:20),NumericRule(source:.hidden,key:"consistency",minimum:10,maximum:20)]
    let filtered=timed("compoundFilterMS",q,SortSpec(key:"pa",ascending:false))
    try test(filtered.allSatisfy {let r=rows[$0];return r.player.ca>=130 && r.player.pa>=150 && (r.wage ?? Int.max)<=200000 && ((r.player.visibleAttributes["pace"] ?? nil) ?? 0)>=12 && ((r.player.hiddenAttributes["consistency"] ?? nil) ?? 0)>=10},"Composed verified ranges")
    q=Query();q.employment="Free agent";let free=timed("freeAgentsMS",q)
    try test(free.allSatisfy {rows[$0].player.transfers?.freeAgentState.known==true},"Free agents exclude unknown state")
    q=Query();q.employment="Contracted";let contracted=selectRows(rows,query:q,sort:SortSpec())
    try test(contracted.allSatisfy {rows[$0].player.transfers?.employmentContract.status=="verified"},"Contracted field selection")
    q=Query();q.position="GK";let keepers=timed("goalkeepersMS",q)
    try test(!keepers.isEmpty && keepers.allSatisfy {rows[$0].player.isKeeper},"Goalkeeper classification")
    q=Query();q.expiryAfter="2027-01-01";q.expiryBefore="2030-12-31"
    let expiry=timed("expiryFilterMS",q)
    try test(expiry.allSatisfy {if let value=rows[$0].expiry{return value>=q.expiryAfter && value<=q.expiryBefore};return false},"Expiry filters exclude sentinels")
    let wages=timed("sortWageMS",Query(),SortSpec(key:"wage",ascending:false));let known=wages.compactMap {rows[$0].wage}
    try test(zip(known,known.dropFirst()).allSatisfy {$0 >= $1},"Descending wage order")
    if let lastKnown=wages.lastIndex(where:{rows[$0].wage != nil}) {try test(wages.prefix(lastKnown+1).allSatisfy {rows[$0].wage != nil},"Unknown wages sort last")}
    q=Query();q.name="this player name does not exist 619902";try test(selectRows(rows,query:q,sort:SortSpec()).isEmpty,"Empty result")
    try test(normalized("João")==normalized("joao"),"Diacritic-insensitive search")
    let decoder=JSONDecoder()
    var compatibility=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:args[i+1]))) as! [String:Any]
    compatibility["prototype"]="Touchline Live";compatibility["phase"]=3
    compatibility["verifiedPlayers"]=[["referenceName":"Synthetic Forward","referenceCheck":"Structural identity and decoded name","researchCareerDifferences":[:]] as [String:Any]]
    for version in [2,3] {
        compatibility["modelVersion"]=version
        let legacy=try decoder.decode(Snapshot.self,from:JSONSerialization.data(withJSONObject:compatibility))
        try test(legacy.modelVersion==version && legacy.players.map(\.uid)==cache.players.map(\.uid) && legacy.collection.count==cache.collection.count,"Legacy diagnostic metadata remains optional for cache version \(version)")
    }
    for (status,expected) in [("verified","Norway"),("unresolved","Unresolved"),("inconsistent","Unresolved"),("unavailable","Unavailable")] {
        let data=try JSONSerialization.data(withJSONObject:["status":status,"name":"Norway"])
        let nation=try decoder.decode(Nationality.self,from:data)
        try test(nation.display==expected,"Nationality displays only verified names: \(status)")
    }
    let blankNation=try decoder.decode(Nationality.self,from:Data(#"{"status":"verified","name":" "}"#.utf8))
    try test(blankNation.display=="Unresolved","Empty nationality is not presented as verified")
    let traitFixture=Data(#"{"rawMask":"0xe000000080000001","mapped":[{"bit":0,"name":"Runs with ball down left"},{"bit":31,"name":"Arrives late in opponents area"},{"bit":63,"name":"Plays Ball with feet"}],"unresolvedBits":[61,62]}"#.utf8)
    let traitSet=try decoder.decode(Traits.self,from:traitFixture)
    try test(traitSet.mapped.map(\.bit)==[0,31,63] && traitSet.unresolvedBits==[61,62],"Trait cache supports low/mid/high and unknown bits simultaneously")
    try test(traitSet.mapped.map(\.name).joined(separator:" · ")=="Runs with ball down left · Arrives late in opponents area · Plays Ball with feet","Existing profile trait presentation preserves new labels")
    let emptyTraits=try decoder.decode(Traits.self,from:Data(#"{"mapped":[],"unresolvedBits":[]}"#.utf8))
    try test(emptyTraits.mapped.isEmpty && emptyTraits.unresolvedBits.isEmpty,"Empty trait set remains valid")
    let rep=try decoder.decode(Reputation.self,from:Data(#"{"home":1234,"current":5678,"world":9012,"rawSlots":[1234,5678,9012]}"#.utf8))
    try test(rep.home==1234 && rep.current==5678 && rep.world==9012 && rep.rawSlots==[1234,5678,9012],"Exact Home/Current/World reputation ordering")
    let invalidRep=try decoder.decode(Reputation.self,from:Data(#"{"home":null,"current":0,"world":10000,"rawSlots":[65535,0,10000]}"#.utf8))
    try test(invalidRep.home==nil && invalidRep.current==0 && invalidRep.world==10000 && invalidRep.rawSlots[0]==65535,"Invalid reputation remains null with raw provenance; valid boundaries preserved")
    let verified=try decoder.decode(Money.self,from:Data(#"{"status":"verified","raw":0}"#.utf8))
    let unknown=try decoder.decode(Money.self,from:Data(#"{"status":"unresolved","raw":300000000}"#.utf8))
    try test(verified.known==0 && unknown.known==nil,"No monetary inference; zero retained")
    let unresolved=try decoder.decode(Expiry.self,from:Data(#"{"status":"unresolved","date":null,"rawDay":2,"rawYear":1900}"#.utf8))
    try test(unresolved.known==nil,"Sentinel is not a real expiry")
    try test(compare(nil as Int?,5,ascending:true)>0 && compare(nil as Int?,5,ascending:false)>0,"Nulls last in both sort directions")
    let away=rows.filter {r in
        guard let t=r.player.transfers, t.employmentContract.status == "verified",
              let parent=t.employmentContract.team?.club, parent.nameStatus == "verified",
              let parentID=parent.uid, let currentID=t.currentClub.uid else {return false}
        return parentID != currentID
    }
    try test(!away.isEmpty && away.allSatisfy {$0.club == $0.player.transfers!.employmentContract.team!.club!.name!},"Players at other clubs display their main employment club")
    try test(free.allSatisfy {rows[$0].club == "Free Agent"},"Free-agent club display")
    if let sample=away.first {
        var clubQuery=Query();clubQuery.club=normalized(sample.club)
        try test(clubQuery.matches(sample),"Club filtering uses the displayed parent club")
    }
    // Deliberately shuffled ages distinguish numeric sorting from name/string order.
    func ageFixture(_ uid:Int,_ age:Int?,_ status:String="derived",nationality:[String:String]?=nil) throws -> Row {
        var object:[String:Any]=["uid":uid,"name":"Fixture \(uid)","birthDate":"2000-01-01","age":age.map {$0 as Any} ?? NSNull(),"ca":120,"pa":160,"positions":["ST":20],"visibleAttributes":[:],"hiddenAttributes":[:],"footStrengths":[:],"personalityComponents":[:],"reputation":["rawSlots":[]],"traits":["mapped":[],"unresolvedBits":[]],"fieldStatus":["age":status]]
        if let nationality=nationality {object["nationality"]=nationality}
        return Row(try decoder.decode(Player.self,from:JSONSerialization.data(withJSONObject:object)))
    }
    let nationRows=try [
        ageFixture(101,18,nationality:["status":"verified","name":"France"]),
        ageFixture(102,21,nationality:["status":"verified","name":"Norway"]),
        ageFixture(103,30,nationality:["status":"verified","name":"France"]),
        ageFixture(104,18,nationality:["status":"unresolved","name":"France"]),
        ageFixture(105,18,nationality:["status":"unavailable","name":"France"]),
        ageFixture(106,18,nationality:["status":"inconsistent","name":"France"]),
        ageFixture(107,18),
        ageFixture(108,18,nationality:["status":"verified","name":" " ])]
    var nationQuery=Query()
    func nationIDs(_ q:Query)->[Int] {selectRows(nationRows,query:q,sort:SortSpec()).map {nationRows[$0].player.uid}}
    try test(availableNationalities(nationRows)==["France","Norway"],"Nationality options derive from unique verified nonempty cached values")
    try test(nationIDs(nationQuery).count==nationRows.count,"Any nationality includes unavailable and unresolved rows")
    nationQuery.nationality="France"
    try test(nationIDs(nationQuery)==[101,103],"Exact canonical nationality filters out unavailable, unresolved, inconsistent and missing data")
    nationQuery.nationality="Fran"
    try test(nationIDs(nationQuery).isEmpty,"Nationality does not use substring or inferred matching")
    nationQuery.nationality="France";nationQuery.ageMax=21;nationQuery.position="ST";nationQuery.caMin=120;nationQuery.paMin=160
    try test(nationIDs(nationQuery)==[101],"Nationality composes with age, position, CA and PA using AND")
    nationQuery.caMin=121
    try test(nationIDs(nationQuery).isEmpty,"Other constraints still narrow nationality results")
    nationQuery=Query()
    try test(nationQuery.nationality==nil && nationIDs(nationQuery).count==nationRows.count,"Reset query clears nationality to Any")
    if let nation=availableNationalities(rows).first {
        var q=Query();q.nationality=nation
        let matches=selectRows(rows,query:q,sort:SortSpec())
        try test(!matches.isEmpty && matches.allSatisfy {rows[$0].player.nationality?.known==nation},"Full-cache nationality query uses verified canonical values")
    }
    let legacyPlayer=try ageFixture(999,21).player
    try test(legacyPlayer.nationality == nil && legacyPlayer.nationalityDisplay == "Unresolved","Older cache without nationality remains readable")
    if let nation=rows.first(where:{$0.player.nationality?.status == "verified"})?.player.nationality {
        try test(nation.display==nation.name,"Live-cache nationality decodes into the display model")
    }
    let ages=try [ageFixture(1,21),ageFixture(2,100),ageFixture(3,9),ageFixture(4,16),ageFixture(5,nil),ageFixture(6,18,"unresolved"),ageFixture(7,21)]
    func ageIDs(_ query:Query=Query(),_ ascending:Bool=true)->[Int] {selectRows(ages,query:query,sort:SortSpec(key:"age",ascending:ascending)).map {ages[$0].player.uid}}
    try test(ageIDs()==[3,4,1,7,2,5,6],"Numeric age ascending; missing and unresolved last; stable ties")
    try test(ageIDs(Query(),false)==[2,1,7,4,3,5,6],"Numeric age descending; missing and unresolved last")
    var ageQuery=Query();ageQuery.ageMin=16
    try test(ageIDs(ageQuery)==[4,1,7,2],"Minimum age only, inclusive")
    ageQuery=Query();ageQuery.ageMax=21
    try test(ageIDs(ageQuery)==[3,4,1,7],"Maximum age only, inclusive")
    ageQuery.ageMin=16
    try test(ageIDs(ageQuery)==[4,1,7],"Inclusive 16–21; unresolved excluded")
    ageQuery.position="ST";ageQuery.caMin=120;ageQuery.paMin=160
    try test(ageIDs(ageQuery)==[4,1,7],"Age combines with position and CA/PA")
    ageQuery.caMin=121;try test(ageIDs(ageQuery).isEmpty,"Combined ability constraint narrows age results")
    ageQuery=Query();try test(ageIDs(ageQuery).count==ages.count,"Reset query clears age constraints")
    for ascending in [true,false] {
        let sorted=selectRows(rows,query:Query(),sort:SortSpec(key:"age",ascending:ascending))
        let values=sorted.compactMap {rows[$0].age}
        try test(zip(values,values.dropFirst()).allSatisfy {ascending ? $0 <= $1 : $0 >= $1},"Full-cache age order")
    }
    let cad=DisplayCurrency(id:13,name:"Canadian Dollar",shortName:"Dollar",symbol:"$",value:Double(Float(bitPattern:0x3fda9f37)))
    try test(cad.amount(300000000)==512395155 && cad.amount(450000)==768593 && cad.amount(768900)==1313269 && cad.amount(6061)==10352,"Live float32 multiplier promoted before multiplication; CAD evidence")
    try test(cad.amount(17426704)==29764529 && cad.amount(313768)==535911 && cad.amount(0)==0,"Diverse price and zero conversion")
    try test(unknown.display(in:cad)=="Unresolved" && verified.known==0,"Currency does not promote unresolved amounts or mutate raw data")
    let half=DisplayCurrency(id:1,name:"Test",shortName:"Test",symbol:"",value:0.5)
    try test(half.amount(5)==2 && half.amount(7)==4,"Whole-unit ties round to even")
    try test(CurrencyTable(status:"unresolved",definitions:[cad]).available.isEmpty,"Unverified table cannot enable conversion")
    let invalid=DisplayCurrency(id:2,name:"Bad",shortName:"Bad",symbol:"",value:Double.nan)
    try test(CurrencyTable(status:"verified",definitions:[invalid]).available.isEmpty,"Invalid rate cannot enable conversion")
    try test(displayMoney(123,currency:nil)==123.formatted(),"Older caches retain base display")
    try test(half.format(8).hasSuffix(" Test"),"Missing live symbol uses supplied short name")
    let convertStart=Date();var converted=0.0
    for r in rows {if let amount=r.wage {converted += cad.amount(amount)}}
    timings["currencyAllWagesMS"]=Date().timeIntervalSince(convertStart)*1000
    try test(converted.isFinite && converted>0,"Full cache converts locally")
    // Headless tests exercise the shared editor and actual local query, not AppKit.
    var editor=FilterEditor()
    func quickEdit(_ field:FilterField,_ value:String) {editor[field]=value}
    func advancedEdit(_ field:FilterField,_ value:String) {editor[field]=value}
    quickEdit(.caMin,"150")
    try test(editor[.caMin]=="150" && (try editor.makeQuery()).caMin==150,"Quick filter value is the advanced editor's canonical draft")
    advancedEdit(.caMin,"160")
    try test(editor[.caMin]=="160" && (try editor.makeQuery()).caMin==160,"Advanced edits replace the same value consumed by quick controls")
    advancedEdit(.position,"ST");advancedEdit(.ageMin,"16");advancedEdit(.ageMax,"21");advancedEdit(.paMin,"170");advancedEdit(.paMax,"200");advancedEdit(.nationality,"Brazil");advancedEdit(.askingMax,"40000000")
    let draftBefore=FilterField.allCases.map {editor[$0]}
    _=try editor.makeQuery();_=try editor.makeQuery()
    try test(FilterField.allCases.map {editor[$0]}==draftBefore,"Reading/reopening the retained editor never clears draft values")
    for field in FilterField.allCases {editor[field]="filled"}
    editor.rules=[RuleDraft(source:.attribute,key:"pace",minimum:"12",maximum:"20")]
    editor.reset()
    try test(FilterField.allCases.allSatisfy {editor[$0]==$0.initial} && editor.rules.isEmpty,"Shared reset clears every field and dynamic rule")
    try test(try selectRows(ages,query:editor.makeQuery(),sort:SortSpec()).count==ages.count,"Cleared editor returns the full universe")
    let steppedFields:[FilterField]=[.caMin,.caMax,.paMin,.paMax,.ageMin,.ageMax]
    for field in steppedFields {
        editor.reset()
        let bounds=field.stepperBounds!
        try test(editor.stepperValue(for:field)==0 && editor[field].isEmpty,"Empty \(field) initializes only the stepper, preserving Any")
        try test(try editor.makeQuery()==Query(),"Initializing \(field) does not activate a constraint")
        editor.setSteppedValue(1,for:field)
        try test(editor[field]=="1" && editor.stepperValue(for:field)==1,"First upward step from Any for \(field)")
        editor[field]=" 17 "
        try test(editor.stepperValue(for:field)==17,"Manual typing synchronizes \(field)")
        for value in [18,19,18] {editor.setSteppedValue(value,for:field)}
        try test(editor[field]=="18" && editor.stepperValue(for:field)==18,"Repeated native step values share the \(field) draft")
        editor.setSteppedValue(-1,for:field)
        try test(editor[field]=="0" && (try? editor.makeQuery()) != nil,"\(field) clamps to the existing valid zero bound")
        editor.setSteppedValue(bounds.upperBound+1,for:field)
        try test(editor[field]==String(bounds.upperBound) && (try? editor.makeQuery()) != nil,"\(field) clamps to its validation cap")
        for invalid in ["-1","abc","1.5",String(bounds.upperBound+1)] {
            editor[field]=invalid
            try test(editor.stepperValue(for:field)==nil && editor[field]==invalid,"Invalid \(field) draft disables stepping without rewriting typed input")
        }
        editor[field]=""
        try test(editor.stepperValue(for:field)==0 && (try? editor.makeQuery())==Query(),"Clearing \(field) restores Any")
        editor.setSteppedValue(18,for:field);editor.reset()
        try test(editor[field].isEmpty && editor.stepperValue(for:field)==0,"Shared Reset resets \(field) and its stepper")
    }
    editor.reset();editor[.paMin]="170"
    for value in [171,172,171] {editor.setSteppedValue(value,for:.paMin)}
    try test(try editor.makeQuery().paMin==171,"PA step sequence drives the normal query")
    editor[.paMax]="170"
    try test((try? editor.makeQuery())==nil,"Stepping preserves reversed-range validation")
    editor.setSteppedValue(171,for:.paMax)
    try test(try editor.makeQuery().paMin==171 && editor.makeQuery().paMax==171,"Maximum stepping repairs an inclusive shared range")
    for field in FilterField.allCases where !steppedFields.contains(field) {
        try test(field.stepperBounds==nil && editor.stepperValue(for:field)==nil,"No stepper semantics for \(field)")
        let previous=editor[field]
        try test(!editor.setSteppedValue(1,for:field) && editor[field]==previous,"Stepping cannot change unrelated \(field)")
    }
    for (low,high,cap) in [(FilterField.caMin,FilterField.caMax,200),(.paMin,.paMax,200),(.ageMin,.ageMax,150),(.askingMin,.askingMax,Int(UInt32.max)),(.wageMin,.wageMax,Int(UInt32.max))] {
        for (l,h) in [("-1",""),("abc",""),("1.5",""),("2","1"),(String(cap+1),"")] {
            editor.reset();editor[low]=l;editor[high]=h
            try test((try? editor.makeQuery())==nil,"Reject invalid or reversed \(low) range \(l)/\(h)")
        }
        for (l,h) in [("0",""),("",String(cap)),("0",String(cap))] {
            editor.reset();editor[low]=l;editor[high]=h
            try test((try? editor.makeQuery()) != nil,"Accept one-sided and inclusive \(low) ranges")
        }
    }
    for (start,end) in [("2027-02-29",""),("2028-01-01","2027-01-01"),("2028-1-01",""),("","not a date")] {
        editor.reset();editor[.expiryAfter]=start;editor[.expiryBefore]=end
        try test((try? editor.makeQuery())==nil,"Reject invalid/reversed expiry dates")
    }
    editor.reset();editor[.expiryAfter]="2028-02-29";editor[.expiryBefore]="2028-02-29"
    try test((try? editor.makeQuery()) != nil,"Leap-day inclusive expiry is valid")
    editor.rules=[RuleDraft(source:.attribute,key:"pace",minimum:"21",maximum:"")]
    try test((try? editor.makeQuery())==nil,"Attribute validation rejects out-of-range ratings")
    editor.rules=[RuleDraft(source:.hidden,key:"consistency",minimum:"15",maximum:"10")]
    try test((try? editor.makeQuery())==nil,"Hidden rule validation rejects reversed range")
    editor.reset();editor.rules=[RuleDraft(source:.component,key:"ambition")]
    try test(try editor.makeQuery().rules.isEmpty,"Blank dynamic rule does not restrict results")

    func scoutingFixture(_ uid:Int,price:Int?,status:String="verified",known:Bool=true)->Row {
        let money:[String:Any]=["status":known ? "verified" : "unresolved","raw":100]
        let club:[String:Any]=["status":"verified","nameStatus":"verified","name":"Parent Club"]
        let transfers:[String:Any]=[
            "currentTeam":["status":"unresolved"],"currentClub":club,
            "employmentContract":["status":known ? "verified" : "unresolved","team":["status":"verified","club":club]],
            "weeklyWage":money,"contractExpiry":["status":known ? "verified" : "unresolved","date":"2028-06-30"],
            "playerValue":["status":"unresolved"],"askingPrice":["status":status,"raw":price.map {$0 as Any} ?? NSNull()],
            "auxiliaryContracts":["status":"unresolved"],"loanState":["status":"unresolved"],"freeAgentState":["status":known ? "derived" : "unresolved","value":false]]
        let object:[String:Any]=["uid":uid,"name":"Scout \(uid)","birthDate":"2000-01-01","age":18,"ca":150,"pa":180,"positions":["ST":20],"visibleAttributes":known ? ["pace":16] : [:],"hiddenAttributes":known ? ["consistency":15] : [:],"personalityComponents":known ? ["ambition":14] : [:],"footStrengths":[:],"reputation":["rawSlots":[]],"traits":["mapped":[],"unresolvedBits":[]],"fieldStatus":["age":known ? "derived" : "unresolved"],"nationality":["status":known ? "verified" : "unresolved","name":"Brazil"],"transfers":transfers]
        return Row(try! decoder.decode(Player.self,from:JSONSerialization.data(withJSONObject:object)))
    }
    let scouts=[scoutingFixture(201,price:0),scoutingFixture(202,price:100),scoutingFixture(203,price:200),scoutingFixture(204,price:-1),scoutingFixture(205,price:100,status:"unresolved"),scoutingFixture(206,price:nil),scoutingFixture(207,price:100,status:"inconsistent"),scoutingFixture(208,price:100,status:"unavailable"),scoutingFixture(209,price:100,known:false)]
    func scoutIDs(_ editor:FilterEditor) throws -> [Int] {selectRows(scouts,query:try editor.makeQuery(),sort:SortSpec()).map {scouts[$0].player.uid}}
    editor.reset();editor[.askingMax]="0"
    try test(try scoutIDs(editor)==[201],"Verified zero Asking Price is a real inclusive value")
    editor[.askingMin]="100";editor[.askingMax]="200"
    try test(try scoutIDs(editor)==[202,203,209],"Asking Price inclusive range excludes unresolved, invalid, missing and sentinel amounts")
    editor[.askingMax]=""
    try test(try scoutIDs(editor)==[202,203,209],"Asking Price minimum alone")
    editor[.askingMin]="";editor[.askingMax]="100"
    try test(try scoutIDs(editor)==[201,202,209],"Asking Price maximum alone")
    editor.reset()
    try test(try scoutIDs(editor).count==scouts.count,"No Asking Price constraint includes unresolved players")
    let constraints:[(FilterField,String)]=[(.name,"Scout"),(.club,"Parent"),(.nationality,"Brazil"),(.position,"ST"),(.employment,"Contracted"),(.caMin,"150"),(.caMax,"150"),(.paMin,"180"),(.paMax,"180"),(.ageMin,"18"),(.ageMax,"18"),(.askingMin,"100"),(.askingMax,"100"),(.wageMin,"100"),(.wageMax,"100"),(.expiryAfter,"2028-06-30"),(.expiryBefore,"2028-06-30")]
    for (field,value) in constraints {editor[field]=value}
    editor.rules=[RuleDraft(source:.attribute,key:"pace",minimum:"16",maximum:"16"),RuleDraft(source:.hidden,key:"consistency",minimum:"15",maximum:"15"),RuleDraft(source:.component,key:"ambition",minimum:"14",maximum:"14")]
    try test(try scoutIDs(editor)==[202],"All complete ranges and three rule types compose with AND; exact live count is one")
    for (field,value) in [(FilterField.caMax,"149"),(.paMax,"179"),(.ageMax,"17"),(.wageMax,"99")] {
        var single=FilterEditor();single[field]=value
        try test(try scoutIDs(single).isEmpty,"Numeric maximum actually filters: \(field)")
    }
    for (field,value) in [(FilterField.wageMin,"101"),(.caMin,"151"),(.paMin,"181"),(.ageMin,"19"),(.expiryAfter,"2028-07-01"),(.expiryBefore,"2028-06-29"),(.club,"Other"),(.nationality,"Norway"),(.employment,"Free agent"),(.position,"GK")] {
        var single=FilterEditor();single[field]=value
        try test(try scoutIDs(single).isEmpty,"One-sided condition actually excludes mismatches: \(field)")
    }
    for source in [NumericRule.Source.attribute,.hidden,.component] {
        var single=FilterEditor();single.rules=[RuleDraft(source:source,key:source == .attribute ? "pace" : (source == .hidden ? "consistency" : "ambition"),minimum:"1")]
        try test(try !scoutIDs(single).contains(209),"Unresolved numeric rules do not match: \(source)")
    }
    let validQuery=try editor.makeQuery();editor[.ageMin]="oops"
    try test((try? editor.makeQuery())==nil && validQuery.matches(scouts[1]),"Invalid draft does not overwrite last valid query")
    editor.reset();let headerReset=try scoutIDs(editor)
    editor[.nationality]="Brazil";editor.rules=[RuleDraft(source:.hidden,key:"consistency",minimum:"20")];editor.reset()
    try test(try scoutIDs(editor)==headerReset && headerReset.count==scouts.count,"Header Reset and panel Clear All use the same full reset")
    var priceQuery=Query();priceQuery.askingMin=0;priceQuery.askingMax=40000000
    let prices=timed("askingPriceRangeMS",priceQuery)
    try test(prices.allSatisfy {if let p=rows[$0].askingPrice {return p>=0 && p<=40000000};return false},"Full-cache Asking Price filtering uses cached base amounts only")
    // Shared range helper must preserve inactive/unknown and inclusive semantics.
    for value in [nil,-1,0,1,20] as [Int?] {
        for low in [nil,0,1,20] as [Int?] {
            for high in [nil,0,1,20] as [Int?] {
                let expected:Bool
                if low == nil && high == nil {expected=true}
                else if let value=value {expected=(low == nil || value>=low!) && (high == nil || value<=high!)}
                else {expected=false}
                try test(matchesRange(value,minimum:low,maximum:high)==expected,"Range refactor preserves nil, zero, negative and reversed-bound behavior")
            }
        }
    }
    let numericFields:[WritableKeyPath<Query,Int?>]=[\.caMin,\.caMax,\.paMin,\.paMax,\.ageMin,\.ageMax,\.askingMin,\.askingMax,\.wageMin,\.wageMax]
    for field in numericFields {var changed=Query();changed[keyPath:field]=0;try test(changed != Query(),"Every numeric constraint participates in query equality")}
    let textFields:[WritableKeyPath<Query,String>]=[\.name,\.club,\.position,\.employment,\.expiryAfter,\.expiryBefore]
    for field in textFields {var changed=Query();changed[keyPath:field]="changed";try test(changed != Query(),"Every text constraint participates in query equality")}
    var changed=Query();changed.nationality="Brazil"
    try test(changed != Query(),"Nationality participates in query equality")
    changed=Query();changed.rules=[NumericRule(source:.hidden,key:"consistency",minimum:10,maximum:20)]
    var changedRule=changed;changedRule.rules[0].source = .component
    try test(changed != Query() && changed != changedRule,"Rule presence and source participate in query equality")
    changedRule=changed;changedRule.rules[0].maximum=19
    try test(changed != changedRule,"Rule bounds participate in query equality")
    var sameDraft=FilterEditor();sameDraft[.name]=" JOÃO ";let normalizedQuery=try sameDraft.makeQuery();sameDraft[.name]="joao"
    try test(try normalizedQuery==sameDraft.makeQuery(),"Equivalent normalized edits can skip redundant query work")
    try test(rows.allSatisfy {$0.cost == $0.player.cost?.1 && $0.age == $0.player.knownAge},"Cached keys preserve original field/status interpretation")
    for ascending in [true,false] {
        let reference=rows.indices.sorted {left,right in
            let order=compare(rows[left].player.cost?.1,rows[right].player.cost?.1,ascending:ascending)
            return order == 0 ? rows[left].player.uid<rows[right].player.uid : order<0
        }
        try test(reference==selectRows(rows,query:Query(),sort:SortSpec(key:"cost",ascending:ascending)),"Cached cost sort exactly matches original computed comparator, including ties/unknowns")
    }
    let output:[String:Any]=["checksPassed":checks,"playerCount":rows.count,"cacheLoadSeconds":loadSeconds,"queryTimings":timings,"compoundMatches":filtered.count,"freeAgents":free.count,"goalkeepers":keepers.count]
    print(String(data:try JSONSerialization.data(withJSONObject:output,options:[.prettyPrinted,.sortedKeys]),encoding:.utf8)!)
}
