import Foundation

@main struct ProjectionTests {
    struct AttributeCase:Decodable {let positions:[String:Int];let ca:Int;let peak:Int;let raw:[String:Int];let expectedRaw:[String:Int];let expectedDisplay:[String:Int]}
    struct PeakCase:Decodable {let age:Int;let positions:[String:Int];let ca:Int;let pa:Int;let expectedPeak:Int?}
    struct Vectors:Decodable {let attributes:[AttributeCase];let peaks:[PeakCase]}
    static func main() throws {
        var checks=0
        func test(_ valid:Bool,_ label:String) throws {
            guard valid else {throw NSError(domain:"ProjectionTests",code:1,userInfo:[NSLocalizedDescriptionKey:label])};checks+=1
        }
        let vectors=try JSONDecoder().decode(Vectors.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
        for (i,c) in vectors.peaks.enumerated() {
            try test(PlayerProjection.projectedPeak(age:c.age,ca:c.ca,pa:c.pa,positions:c.positions)==c.expectedPeak,"Peak vector \(i)")
        }
        for (i,c) in vectors.attributes.enumerated() {
            let actual=PlayerProjection.attributes(raw:c.raw,ca:c.ca,peak:c.peak,positions:c.positions)
            try test(actual.raw==c.expectedRaw,"Raw vector \(i)")
            try test(actual.displayed==c.expectedDisplay,"Display vector \(i)")
        }
        try test(PlayerProjection.elapsedAge(birthDate:"2001-03-01",gameDate:"2026-03-01")==24,"Elapsed-year boundary")
        try test(PlayerProjection.elapsedAge(birthDate:"2001-03-01",gameDate:"2026-03-02")==25,"Elapsed-year next day")
        try test(PlayerProjection.elapsedAge(birthDate:"2026-03-02",gameDate:"2001-03-01")==25,"Absolute elapsed time")
        for invalid in ["2026-02-30","2026-13-01","", "2026-2-03"] {
            try test(PlayerProjection.elapsedAge(birthDate:invalid,gameDate:"2026-03-02")==nil,"Malformed date rejected")
        }
        try test(PlayerProjection.grow(raw:50,ca:100,peak:110,rate:0.25)==52,"Even rounding down tie")
        try test(PlayerProjection.grow(raw:51,ca:100,peak:110,rate:0.25)==54,"Even rounding up tie")
        try test(PlayerProjection.grow(raw:100,ca:0,peak:200,rate:0.35)==170,"Signed-byte wrap before cap")
        try test(PlayerProjection.display(raw:170)==1,"Wrapped byte displays as 1")
        try test(PlayerProjection.attributes(raw:["natural_fitness":20],ca:100,peak:100,positions:["GK":20]).displayed["natural_fitness"]==4,"NF has no compensating times-five")
        // Exercise the real cache adapter, optional additive decoding and graceful failure.
        var positions=Dictionary(uniqueKeysWithValues:PlayerProjection.positionKeys.map {($0,1)})
        positions["ST"]=20
        let base:[String:Any] = [
            "uid":1,"birthDate":"2001-03-01","ca":100,"pa":180,
            "positions":positions,"rawAttributes":Array(repeating:50,count:54),
            "visibleAttributes":Dictionary(uniqueKeysWithValues:technical.map {($0,10)}),
            "hiddenAttributes":["consistency":10],"footStrengths":["left_foot":10,"right_foot":20],
            "personalityComponents":[String:Int](),"reputation":["rawSlots":[Int]()],
            "traits":["mapped":[Int](),"unresolvedBits":[Int]()],
            "fieldStatus":["ca":"verified","pa":"verified","birthDate":"derived","rawAttributes":"verified"]
        ]
        let cacheObject:[String:Any] = ["modelVersion":3,"capturedAt":"2026-03-01T00:00:00Z",
            "elapsedSeconds":1,"collection":["count":1],"players":[base],
            "gameDate":"2026-03-01","gameDateInfo":["status":"verified"]]
        let snapshot=try JSONDecoder().decode(Snapshot.self,from:JSONSerialization.data(withJSONObject:cacheObject))
        let first=snapshot.players[0]
        func player(_ modify:(inout [String:Any])->Void)throws->Player {
            var json=base;modify(&json)
            return try JSONDecoder().decode(Player.self,from:JSONSerialization.data(withJSONObject:json))
        }
        try test(PlayerProjection.profile(for:first,gameDate:snapshot.projectionDate) != nil,"Cached raw/date inputs project")
        try test(PlayerProjection.profile(for:first,gameDate:nil)==nil,"No date fallback")
        let missing=try player {$0.removeValue(forKey:"rawAttributes")}
        try test(PlayerProjection.profile(for:missing,gameDate:snapshot.projectionDate)==nil,"Old cache remains decodable, projection unavailable")
        let short=try player {$0["rawAttributes"]=[50]}
        try test(PlayerProjection.profile(for:short,gameDate:snapshot.projectionDate)==nil,"Truncated raw vector")
        let unknown=try player {var positions=$0["positions"] as! [String:Any];positions["GK"]=NSNull();$0["positions"]=positions}
        try test(PlayerProjection.profile(for:unknown,gameDate:snapshot.projectionDate)==nil,"Unknown position does not invent group")
        let noGroup=try player {$0["positions"]=Dictionary(uniqueKeysWithValues:PlayerProjection.positionKeys.map {($0,1)})}
        try test(PlayerProjection.profile(for:noGroup,gameDate:snapshot.projectionDate)==nil,"No retained foreign Peak guessed")
        let invalidField=try player {var raw=$0["rawAttributes"] as! [Int];raw[0]=255;$0["rawAttributes"]=raw}
        try test(PlayerProjection.profile(for:invalidField,gameDate:snapshot.projectionDate)?.attributes.displayed["crossing"]==nil,"Invalid cached attribute stays unresolved")
        var legacy=cacheObject;legacy.removeValue(forKey:"gameDate");legacy.removeValue(forKey:"gameDateInfo")
        let older=try JSONDecoder().decode(Snapshot.self,from:JSONSerialization.data(withJSONObject:legacy))
        try test(older.projectionDate==nil,"Legacy snapshot date optional")
        legacy["gameDate"]=snapshot.gameDate;legacy["gameDateInfo"]=["status":"unresolved"]
        let untrusted=try JSONDecoder().decode(Snapshot.self,from:JSONSerialization.data(withJSONObject:legacy))
        try test(untrusted.projectionDate==nil,"Untrusted date ignored")
        let badStatus=try player {var status=$0["fieldStatus"] as! [String:String];status["rawAttributes"]="inconsistent";$0["fieldStatus"]=status}
        try test(PlayerProjection.profile(for:badStatus,gameDate:snapshot.projectionDate)==nil,"Untrusted raw provenance ignored")
        let start=Date()
        for _ in 0..<1000 { _=PlayerProjection.profile(for:first,gameDate:snapshot.projectionDate) }
        print("Mean local projection milliseconds: \(Date().timeIntervalSince(start))") // seconds / 1000 * 1000
        print("Projection checks passed: \(checks); golden peak cases: \(vectors.peaks.count); attribute vectors: \(vectors.attributes.count)")
    }
}
