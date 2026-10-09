import Foundation

@main struct PersonalityTests {
    struct Case:Decodable {let input:PlayerPersonality.Inputs;let expected:String?}
    struct AgeCase:Decodable {let birthDate:String;let gameDate:String;let expected:Int}
    struct Vectors:Decodable {let classification:[Case];let ages:[AgeCase];let labels:[String:String]}
    static func main() throws {
        var count=0
        func check(_ condition:Bool,_ message:String)throws {
            guard condition else {throw NSError(domain:"PersonalityTests",code:1,userInfo:[NSLocalizedDescriptionKey:message])};count+=1
        }
        let v=try JSONDecoder().decode(Vectors.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
        for (index,c) in v.classification.enumerated() {
            let actual=PlayerPersonality.classify(c.input)
            try check(actual.label==c.expected,"Classifier vector \(index): expected \(c.expected ?? "unresolved"), got \(actual.display)")
            try check(actual.status==(c.expected == nil ? "unresolved" : "derived"),"Status vector \(index)")
        }
        for c in v.ages {
            try check(PlayerPersonality.classificationAge(birthDate:c.birthDate,gameDate:c.gameDate)==c.expected,"Native classification age \(c.birthDate) / \(c.gameDate)")
        }
        for (code,name) in v.labels {try check(PlayerPersonality.labels[Int(code)!]==name,"Localized label code \(code)")}
        for bad in ["", "2001-02-29", "2000-13-01", "2001-2-03", "1900-01-01"] {
            try check(PlayerPersonality.classificationAge(birthDate:bad,gameDate:"2026-06-02")==nil,"Invalid/sentinel DOB")
        }
        try check(PlayerPersonality.classificationAge(birthDate:"2027-01-01",gameDate:"2026-06-02")==nil,"Future birth date")
        let base:[String:Any] = ["uid":1,"ca":100,"pa":180,"birthDate":"2001-07-21",
            "positions":["ST":20],"rawAttributes":Array(repeating:50,count:54),
            "visibleAttributes":["determination":10,"leadership":10],"hiddenAttributes":[String:Int](),
            "footStrengths":[String:Int](),"personalityComponents":Dictionary(uniqueKeysWithValues:personality.map {($0,10)}),
            "personalityContext":["status":"verified","rawFlagsByte":0,"negativeLabelsAllowed":false],
            "reputation":["rawSlots":[Int]()],"traits":["mapped":[Int](),"unresolvedBits":[Int]()],
            "fieldStatus":["personalityComponents":"verified","rawAttributes":"verified"]]
        func player(_ update:(inout [String:Any])->Void)throws->Player {
            var data=base;update(&data)
            return try JSONDecoder().decode(Player.self,from:JSONSerialization.data(withJSONObject:data))
        }
        let balanced=try player {_ in}
        try check(PlayerPersonality.profile(for:balanced,gameDate:"2026-06-02").label=="Balanced","Cached adapter")
        let citizen=try player {
            $0["personalityComponents"]=Dictionary(uniqueKeysWithValues:personality.map {($0,15)})
            var raw=$0["rawAttributes"] as! [Int];raw[51]=70;$0["rawAttributes"]=raw
        }
        try check(PlayerPersonality.profile(for:citizen,gameDate:nil).label=="Model Citizen","Age-independent high-priority label")
        let leader=try player {var raw=$0["rawAttributes"] as! [Int];raw[40]=100;raw[51]=100;$0["rawAttributes"]=raw}
        try check(PlayerPersonality.profile(for:leader,gameDate:"2026-06-02").label=="Born Leader","Cached raw leadership/determination")
        let negative=try player {var c=$0["personalityComponents"] as! [String:Int];c["temperament"]=4;$0["personalityComponents"]=c;$0["personalityContext"]=["status":"verified","rawFlagsByte":8,"negativeLabelsAllowed":true]}
        try check(PlayerPersonality.profile(for:negative,gameDate:"2026-06-02").label=="Temperamental","Verified negative flag")
        let hiddenNegative=try player {var c=$0["personalityComponents"] as! [String:Int];c["temperament"]=4;$0["personalityComponents"]=c}
        try check(PlayerPersonality.profile(for:hiddenNegative,gameDate:"2026-06-02").label=="Balanced","Native negative-label suppression")
        let legacy=try player {var c=$0["personalityComponents"] as! [String:Int];c["temperament"]=4;$0["personalityComponents"]=c;$0.removeValue(forKey:"personalityContext")}
        try check(PlayerPersonality.profile(for:legacy,gameDate:"2026-06-02").status=="unresolved","Legacy context never guessed")
        let contradiction=try player {var c=$0["personalityComponents"] as! [String:Int];c["temperament"]=4;$0["personalityComponents"]=c;$0["personalityContext"]=["status":"verified","rawFlagsByte":8,"negativeLabelsAllowed":false]}
        try check(PlayerPersonality.profile(for:contradiction,gameDate:"2026-06-02").label==nil,"Contradictory context rejected")
        let loyal=try player {var c=$0["personalityComponents"] as! [String:Int];c["ambition"]=7;c["loyalty"]=20;$0["personalityComponents"]=c}
        try check(PlayerPersonality.profile(for:loyal,gameDate:"2026-06-02").status=="unresolved","Devoted affinity is not invented")
        for bad in [0,21,-1,255] {
            let p=try player {var c=$0["personalityComponents"] as! [String:Int];c["professionalism"]=bad;$0["personalityComponents"]=c}
            try check(PlayerPersonality.profile(for:p,gameDate:"2026-06-02").label==nil,"Invalid component \(bad)")
        }
        let null=try player {var c=$0["personalityComponents"] as! [String:Any];c["adaptability"]=NSNull();$0["personalityComponents"]=c}
        try check(PlayerPersonality.profile(for:null,gameDate:"2026-06-02").label==nil,"Null component")
        let inconsistent=try player {$0["fieldStatus"]=["personalityComponents":"inconsistent","rawAttributes":"verified"]}
        try check(PlayerPersonality.profile(for:inconsistent,gameDate:"2026-06-02").label==nil,"Inconsistent provenance")
        let noRaw=try player {$0.removeValue(forKey:"rawAttributes")}
        try check(PlayerPersonality.profile(for:noRaw,gameDate:"2026-06-02").label==nil,"Old raw-less cache")
        try check(PlayerPersonality.profile(for:balanced,gameDate:nil).label=="Balanced","Age-independent fallback needs no date")
        let missingDate=PlayerPersonality.profile(for:leader,gameDate:nil)
        try check(missingDate.label==nil,"Unknown date can change leadership precedence")
        print("Personality checks passed: \(count); \(v.classification.count) classifier vectors; \(v.ages.count) native-age vectors; all 40 labels")
        if CommandLine.arguments.count>2 {
            let (snapshot,rows,_)=try loadCache(URL(fileURLWithPath:CommandLine.arguments[2]))
            let start=Date();var labels:[String:Int]=[:];var statuses:[String:Int]=[:]
            for row in rows {
                let result=PlayerPersonality.profile(for:row.player,gameDate:snapshot.projectionDate)
                statuses[result.status,default:0]+=1
                if let label=result.label {labels[label,default:0]+=1}
            }
            print("Offline cache \(rows.count) players; personality statuses \(statuses); seconds \(Date().timeIntervalSince(start))")
            for name in ["Erling Haaland","Kylian Mbappé","Alisson","Archie Gray"] {
                if let p=rows.first(where:{$0.name==name})?.player {
                    let result=PlayerPersonality.profile(for:p,gameDate:snapshot.projectionDate)
                    print("Cached \(name): \(result.status) / \(result.display); components \(p.personalityComponents)")
                }
            }
        }
    }
}
